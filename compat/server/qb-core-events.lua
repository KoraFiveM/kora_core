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

-- Stock client-inbound `QBCore:ToggleDuty` (qb-policejob / qb-ambulancejob /
-- qb-mechanicjob duty points trigger it). It used to be left unregistered
-- because kora_core cannot know a job resource's approved duty locations: any
-- client can fire it from anywhere. Duty is a low-impact flag (it gates
-- paychecks and dispatch for a job the player ALREADY holds, and flipping it
-- grants no job, grade, item or money), so it is registered behind
-- Config.compat.toggleDutyEvent (default true; set false to restore the strict
-- "job resources own duty transitions" behaviour). Anti-abuse kept: the caller
-- must be loaded, must hold a real job (not the default/unemployed one), and is
-- rate-limited per source. The flip goes through Core.jobs.setJobDuty so the
-- duty index and QBCore:Server:SetDuty / QBCore:Client:SetDuty still fire.
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
    Core.jobs.setJobDuty(src, not job.onduty)
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

-- Registered so the name is dispatchable at all -- FXServer silently drops a
-- client TriggerServerEvent for a net event name no resource has
-- RegisterNetEvent'd server-side, so real qb-spawn/qb-multicharacter's own
-- TriggerServerEvent('QBCore:Server:OnPlayerLoaded') (and any third-party
-- AddEventHandler for it) would otherwise be a complete no-op here. No Core.*
-- action needed: Core.player.login's adopt() already fires the equivalent
-- PlayerLoaded/OnPlayerLoaded signals, at character-select time rather than
-- at spawn-confirm time like upstream -- a pre-existing timing difference,
-- out of scope to rearchitect for this compat shim.
RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function() end)

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
--      caller either holds the specific per-command ACE or the call is denied.
--   3. If the definition declares argsrequired and the caller didn't supply
--      enough (fewer than #params), notify and stop -- never runs the callback.
--   4. Otherwise call List[name].callback(src, args) in-process.
RegisterNetEvent('QBCore:CallCommand', function(name, args)
    local src = source
    if type(name) ~= 'string' or name == '' then return end

    local cmd = QBCore.Commands.List[name]
    if not cmd then return end

    if not IsPlayerAceAllowed(src, 'command.' .. name) then
        return
    end

    -- args come straight from the client: only a short array is meaningful.
    if type(args) ~= 'table' or #args > 16 then args = {} end
    if cmd.argsrequired and cmd.params and #args < #cmd.params then
        TriggerClientEvent('QBCore:Notify', src, 'Missing arguments for this command!', 'error')
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
-- Hooked off the same modern 'qbcore:server:playerLoaded' event
-- modules/player/server.lua fires immediately alongside (same tick as)
-- TriggerClientEvent('QBCore:Client:OnPlayerLoaded', src), rather than adding
-- compat-specific logic to that Core.* module directly.
if Config.compat.fireSharedUpdateAtLogin then
    AddEventHandler('qbcore:server:playerLoaded', function(src)
        TriggerClientEvent('QBCore:Client:SharedUpdate', src, QBCore.Shared)
    end)
end

-- Deliberately do not register QBCore:Server:SpawnVehicle or
-- QBCore:Server:CreateVehicle. Their legacy wire shape gives every client an
-- arbitrary server-side entity creation capability: kora_core cannot infer which
-- job, garage, model, or location authorized the request. Trusted server
-- resources can still call QBCore.Functions.SpawnVehicle/CreateVehicle
-- directly; player-facing resources must expose their own guarded callback and
-- derive model/coordinates from server-owned configuration.
