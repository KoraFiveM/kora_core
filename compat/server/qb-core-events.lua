-- compat/server/qb-core-events.lua -- inbound legacy net events a third-party
-- resource might trigger on the server, wired to the internal Core.* functions.
-- Outbound legacy events (PlayerLoaded, OnJobUpdate, OnMoneyChange, ...) are
-- fired at their source inside the modules; this file only handles the inbound
-- side + a couple of admin command relays.

local PI = CoreInternal.player

-- Value rules for allow-listed client metadata keys. Stock qb-core's own
-- QBCore:Server:SetMetaData only ever accepted hunger/thirst/stress (numeric,
-- clamped to 0..100); those are the defaults in Config.compat.clientMetadataKeys.
-- A key that is allow-listed but has no rule here (an operator addition) is
-- accepted as-is, exactly as before -- adding rules for it is the operator's
-- responsibility. Everything else stays server-authoritative (money, jail,
-- isdead, inlaststand, licences, criminalrecord, callsign, ...).
local CLIENT_METADATA_RULES = {
    hunger = { type = 'number', min = 0, max = 100 },
    thirst = { type = 'number', min = 0, max = 100 },
    stress = { type = 'number', min = 0, max = 100 },
}

RegisterNetEvent('QBCore:Server:SetMetaData', function(key, value)
    local src = source
    -- Starter eligibility is created and consumed exclusively by the server.
    if type(key) ~= 'string' or key == 'starterItems' or Config.compat.clientMetadataKeys[key] ~= true then
        print(("^3[qbcore]^7 rejected client metadata write from %s for key '%s'"):format(src, tostring(key)))
        return
    end
    local rule = CLIENT_METADATA_RULES[key]
    if rule then
        if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then
            print(("^3[qbcore]^7 rejected client metadata write from %s for key '%s': not a finite number"):format(src, key))
            return
        end
        value = math.min(rule.max, math.max(rule.min, value))
    end
    Core.metadata.setMetaData(src, key, value)
end)

-- Stock client-inbound `QBCore:ToggleDuty` (qb-policejob / qb-ambulancejob / qb-mechanicjob duty points).
-- kora_core cannot know a job resource's approved duty locations, but duty is a low-impact flag
-- (gates paychecks and dispatch for a job the player ALREADY holds; grants no job, grade, item or money),
-- so it is registered behind Config.compat.toggleDutyEvent (default true; false restores strict
-- "job resources own duty transitions"). Anti-abuse: the caller must be loaded, hold a real job
-- (not the default/unemployed one), and is rate-limited per source. The flip goes through
-- Core.jobs.setJobDuty so the duty index and QBCore:Server:SetDuty / QBCore:Client:SetDuty still fire.
local TOGGLE_DUTY_COOLDOWN_MS = 2000
local dutyCooldowns = {}
RegisterNetEvent('QBCore:ToggleDuty', function()
    local src = source
    if Config.compat.toggleDutyEvent ~= true then return end
    local now = GetGameTimer()
    if dutyCooldowns[src] and (now - dutyCooldowns[src]) < TOGGLE_DUTY_COOLDOWN_MS then return end
    dutyCooldowns[src] = now

    local handle = PI.handle(src)
    if not handle then return end
    local job = handle.PlayerData.job
    if type(job) ~= 'table' or type(job.name) ~= 'string' or job.name == Config.jobs.defaultJob then
        print(("^3[qbcore]^7 rejected QBCore:ToggleDuty from %s: no job"):format(tostring(src)))
        return
    end
    local nextDuty = not job.onduty
    if Core.jobs.setJobDuty(src, nextDuty) then
        TriggerClientEvent('QBCore:Notify', src, nextDuty and 'You are now on duty!' or 'You are now off duty!')
    end
end)

RegisterNetEvent('QBCore:Server:Logout', function()
    Core.player.logout(source)
end)

-- Real qb-core's server/events.lua: a chat resource (e.g. [gameplay]/chat)
-- fires 'chatMessage' for every line a player sends BEFORE it knows whether
-- the line was actually a command; a leading '/' means it's a command
-- attempt, not a chat line, so cancel the event to stop the chat resource
-- from also displaying it as a message.
AddEventHandler('chatMessage', function(_, _, message)
    if string.sub(message, 1, 1) == '/' then
        CancelEvent()
    end
end)

-- Stock qb-core answers this client event (sent by qb-spawn / qb-multicharacter
-- after spawn) with QBCore:Client:OnPlayerLoaded. kora_core fires that at login
-- by default, so this stays a no-op unless Config.compat.deferClientPlayerLoaded
-- moves the client event to this point (once per login).
RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local src = source
    if Config.compat.deferClientPlayerLoaded ~= true then return end
    local handle = PI.handle(src)
    if not handle or handle._clientLoadedSent then return end
    handle._clientLoadedSent = true
    TriggerClientEvent('QBCore:Client:OnPlayerLoaded', src)
end)

-- UpdateObject: legacy resources call this to grab a fresh core object handle
-- server-side. It re-broadcasts the object to the caller via the client event.
RegisterNetEvent('QBCore:Server:UpdateObject', function()
    -- No-op server-side: the object is a live table already; nothing to refresh.
end)

-- QBCore:UpdatePlayer -- the stock qb-hud fires this on a timer to have the
-- server tick hunger/thirst down and persist. Our `needs` module ALREADY owns
-- hunger/thirst decay on its own timer, so we deliberately do NOT decrement here
-- (that would double-tick); we honor the event's other duties -- refresh the
-- stock HUD with the current values and persist -- so a stock qb-hud keeps
-- working without fighting our decay loop.
--
-- This is a CLIENT-INBOUND event (any connected client can trigger it) with
-- no rate limit upstream would otherwise provide, and an unconditional
-- Core.persistence.saveNow is a spam/DB-write hole. Real qb-core enforces a
-- 10-second per-source cooldown on this exact handler; mirror it here.
local updateCooldowns = {}
RegisterNetEvent('QBCore:UpdatePlayer', function()
    local src = source
    local now = GetGameTimer()
    if updateCooldowns[src] and (now - updateCooldowns[src]) < 10000 then return end
    updateCooldowns[src] = now

    local handle = PI.handle(src)
    if not handle then return end
    local md = handle.PlayerData.metadata or {}
    TriggerClientEvent('hud:client:UpdateNeeds', src, md.hunger or 100, md.thirst or 100)
    Core.persistence.saveNow(handle)
end)

-- QBCore:DebugSomething -- real qb-core exposes QBCore.Debug (a recursive
-- table-printer, compat/shared/coreobject.lua) to CLIENTS via this net event.
-- This is CLIENT-INBOUND (any connected client can trigger it) and upstream
-- has ZERO rate limiting on it, which is a print-spam hole -- mirror the same
-- per-source cooldown pattern QBCore:UpdatePlayer above uses (a plain
-- GetGameTimer() cooldown table), just with a tighter ~1/second window since
-- this has no persistence cost to justify UpdatePlayer's longer one. Excess
-- calls are silently dropped -- no notify, no log, matching how a rate limit
-- with no upstream equivalent should stay invisible to a legitimate caller.
local debugCooldowns = {}
RegisterNetEvent('QBCore:DebugSomething', function(...)
    local src = source
    local now = GetGameTimer()
    if debugCooldowns[src] and (now - debugCooldowns[src]) < 1000 then return end
    debugCooldowns[src] = now

    QBCore.Debug(...)
end)

-- Prevent an unbounded table leak across server uptime.
AddEventHandler('qbcore:server:playerDropped', function(src)
    updateCooldowns[src] = nil
    debugCooldowns[src] = nil
    dutyCooldowns[src] = nil
end)

-- Server open/close (admin menus). Guarded by the same 'admin' permission real
-- qb-core uses; on close, kick every connected player without the whitelist
-- permission. QBCore + QBCore.Config.Server are assembled in
-- compat/server/qb-core.lua, which loads before this file.
RegisterNetEvent('QBCore:Server:CloseServer', function(reason)
    local src = source
    if not QBCore.Functions.HasPermission(src, 'admin') then
        QBCore.Functions.Kick(src, 'You do not have permission to do that.')
        return
    end
    reason = reason or 'No reason specified'
    QBCore.Config.Server.Closed = true
    QBCore.Config.Server.ClosedReason = reason
    for k in pairs(QBCore.Players) do
        if not QBCore.Functions.HasPermission(k, QBCore.Config.Server.WhitelistPermission) then
            QBCore.Functions.Kick(k, reason)
        end
    end
end)
RegisterNetEvent('QBCore:Server:OpenServer', function()
    local src = source
    if not QBCore.Functions.HasPermission(src, 'admin') then
        QBCore.Functions.Kick(src, 'You do not have permission to do that.')
        return
    end
    QBCore.Config.Server.Closed = false
end)

-- QBCore:Server:OnPlayerUpdated -- server-LOCAL (AddEventHandler, not a net
-- event, matching upstream: this is never triggered directly by a client).
-- Real qb-core, when called with key == 'all' (or key == nil), re-fires both
-- OnJobUpdate and OnGangUpdate for that player using their CURRENT job/gang.
-- Payloads must be legacy-shaped (zero-based grade.level) -- same guarded-call
-- idiom Core.jobs.setJob/setGang use (modules/jobs/server.lua) when firing
-- these same event names.
AddEventHandler('QBCore:Server:OnPlayerUpdated', function(src, key)
    if key ~= nil and key ~= 'all' then return end

    local job = Core.jobs.getJob(src)
    if job then
        local legacyJob = Core.compat.toLegacyJobOrGang and Core.compat.toLegacyJobOrGang(job, 'jobs') or job
        TriggerEvent('QBCore:Server:OnJobUpdate', src, legacyJob)
    end

    local gang = Core.jobs.getGang(src)
    if gang then
        local legacyGang = Core.compat.toLegacyJobOrGang and Core.compat.toLegacyJobOrGang(gang, 'gangs') or gang
        TriggerEvent('QBCore:Server:OnGangUpdate', src, legacyGang)
    end
end)

-- Admin command relays (teleport / spawn) that legacy admin menus fire.
RegisterNetEvent('QBCore:Command:TeleportToCoords', function(x, y, z)
    TriggerClientEvent('QBCore:Command:TeleportToCoords', source, x, y, z)
end)
-- QBCore:CallCommand -- real qb-core looks the command up in QBCore.Commands.List
-- and, if found, invokes its callback DIRECTLY (never ExecuteCommand, which
-- would run in server-console context and bypass every per-player ACE check a
-- command handler would normally get). Ported to match that exactly:
--   1. Unknown command -> return silently (no error, no notify -- upstream
--      behaviour).
--   2. `command.<name>` ACE permission required of the INVOKING player. No
--      blanket-ACE or Core.permissions fallback -- upstream has neither; a
--      caller either holds the specific per-command ACE or is told 'No access'.
--   3. If the definition declares argsrequired and the caller didn't supply
--      enough (fewer than #params), notify and stop -- never runs the callback.
--   4. Otherwise call List[name].callback(src, args) in-process.
RegisterNetEvent('QBCore:CallCommand', function(name, args)
    local src = source
    if type(name) ~= 'string' or name == '' then return end

    local cmd = QBCore.Commands.List[name]
    if not cmd then return end

    if not IsPlayerAceAllowed(src, 'command.' .. name) then
        TriggerClientEvent('QBCore:Notify', src, 'No access to this command', 'error')
        return
    end

    -- args come straight from the client: only a short array is meaningful.
    if type(args) ~= 'table' or #args > 16 then args = {} end
    local declared = cmd.arguments or cmd.params
    if cmd.argsrequired and type(declared) == 'table' and #declared ~= 0 and args[#declared] == nil then
        TriggerClientEvent('QBCore:Notify', src, 'All arguments must be filled out!', 'error')
        return
    end

    if type(cmd.callback) == 'function' then
        cmd.callback(src, args)
    end
end)

-- QBCore:Client:SharedUpdate (opt-in) -- real qb-core fires this ONCE per
-- player, right after playerConnecting, with the ENTIRE QBCore.Shared table --
-- a full push at connect time, distinct from the incremental
-- QBCore:Client:OnSharedUpdate(Multiple) delta events those handle separately
-- (compat/client/qb-core-events.lua). Our registry snapshot mechanism already
-- gets a joining client Items/Jobs/Gangs/etc (modules/registry/client.lua's
-- snapshot-request-on-load), so this is OFF by default (Config.compat.
-- fireSharedUpdateAtLogin) -- it exists only for the rare third-party script
-- that hooks the EVENT NAME itself rather than reading the data it carries.
-- Hooked off 'qbcore:server:playerLoaded' (fired alongside QBCore:Client:OnPlayerLoaded) rather than adding compat logic to the Core.* module.
if Config.compat.fireSharedUpdateAtLogin then
    AddEventHandler('qbcore:server:playerLoaded', function(src)
        TriggerClientEvent('QBCore:Client:SharedUpdate', src, QBCore.Shared)
    end)
end

-- QBCore:Server:SpawnVehicle / CreateVehicle live in compat/server/qb-vehicles.lua.

-- Stock qb-hud stress events. Client-triggerable by design in stock (stress is cosmetic and already writable through the allow-listed QBCore:Server:SetMetaData), so they are type-checked, clamped and rate-limited per source. Yields to a running qb-hud so the change is not applied twice.
local stressLast = {}

local function stressDelta(src, amount, sign)
    local cfg = Config.compat.stress
    if cfg.disabled then return end
    if GetResourceState('qb-hud') == 'started' then return end
    if type(amount) ~= 'number' or amount ~= amount or amount == math.huge or amount == -math.huge then return end
    amount = math.floor(amount)
    if amount < 1 or amount > 100 then return end
    local handle = PI.handle(src)
    if not handle then return end
    local job = handle.PlayerData.job
    if job and (cfg.whitelistedJobs[job.name] or cfg.whitelistedJobs[job.type]) then return end
    local now = GetGameTimer()
    if stressLast[src] and (now - stressLast[src]) < cfg.cooldownMs then return end
    stressLast[src] = now
    local value = Core.metadata.incrementMetaData(src, 'stress', sign * amount, 0, 100)
    if value == nil then return end
    TriggerClientEvent('hud:client:UpdateStress', src, value)
    return value
end

RegisterNetEvent('hud:server:GainStress', function(amount)
    local src = source
    if stressDelta(src, amount, 1) then
        TriggerClientEvent('QBCore:Notify', src, 'Feeling More Stressed!', 'error', 1500)
    end
end)

RegisterNetEvent('hud:server:RelieveStress', function(amount)
    local src = source
    if stressDelta(src, amount, -1) then
        TriggerClientEvent('QBCore:Notify', src, 'Feeling More Relaxed!')
    end
end)

AddEventHandler('qbcore:server:playerDropped', function(src)
    stressLast[src] = nil
end)

-- Stock qb-smallresources log event, server-local only (never RegisterNetEvent: a client must not be able to write the log). Forwarded onto Kora logging; webhook URLs are never read.
AddEventHandler('qb-log:server:CreateLog', function(name, title, color, message, tagEveryone, imageUrl)
    if type(name) ~= 'string' or name == '' then return end
    local function text(value, max)
        if value == nil then return nil end
        return tostring(value):sub(1, max)
    end
    pcall(Core.logging.logEvent, text(name, 64), 0, {
        title = text(title, 128),
        color = text(color, 32),
        message = text(message, 2000),
        tagEveryone = tagEveryone == true,
        imageUrl = text(imageUrl, 256),
        source = 'qb-log',
    })
end)
