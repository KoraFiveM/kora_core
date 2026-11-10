local PI = CoreInternal.player

local CLIENT_METADATA_RULES = {
    hunger = { type = 'number', min = 0, max = 100 },
    thirst = { type = 'number', min = 0, max = 100 },
    stress = { type = 'number', min = 0, max = 100 },
}

RegisterNetEvent('QBCore:Server:SetMetaData', function(key, value)
    local src = source
    if type(key) ~= 'string' or key == 'starterItems' or Config.compat.clientMetadataKeys[key] ~= true then
        print(("^3[kora_core]^7 rejected client metadata write from %s for key '%s'"):format(src, tostring(key)))
        return
    end
    local rule = CLIENT_METADATA_RULES[key]
    if rule then
        if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then
            print(("^3[kora_core]^7 rejected client metadata write from %s for key '%s': not a finite number"):format(src, key))
            return
        end
        value = math.min(rule.max, math.max(rule.min, value))
    end
    Core.metadata.setMetaData(src, key, value)
end)

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
        print(("^3[kora_core]^7 rejected QBCore:ToggleDuty from %s: no job"):format(tostring(src)))
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

AddEventHandler('chatMessage', function(_, _, message)
    if string.sub(message, 1, 1) == '/' then
        CancelEvent()
    end
end)

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local src = source
    if Config.compat.deferClientPlayerLoaded ~= true then return end
    local handle = PI.handle(src)
    if not handle or handle._clientLoadedSent then return end
    handle._clientLoadedSent = true
    TriggerClientEvent('QBCore:Client:OnPlayerLoaded', src)
end)

RegisterNetEvent('QBCore:Server:UpdateObject', function()
end)

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

local debugCooldowns = {}
RegisterNetEvent('QBCore:DebugSomething', function(...)
    local src = source
    local now = GetGameTimer()
    if debugCooldowns[src] and (now - debugCooldowns[src]) < 1000 then return end
    debugCooldowns[src] = now

    QBCore.Debug(...)
end)

AddEventHandler('kora_core:server:playerDropped', function(src)
    updateCooldowns[src] = nil
    debugCooldowns[src] = nil
    dutyCooldowns[src] = nil
end)

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

RegisterNetEvent('QBCore:Command:TeleportToCoords', function(x, y, z)
    TriggerClientEvent('QBCore:Command:TeleportToCoords', source, x, y, z)
end)
RegisterNetEvent('QBCore:CallCommand', function(name, args)
    local src = source
    if type(name) ~= 'string' or name == '' then return end

    local cmd = QBCore.Commands.List[name]
    if not cmd then return end

    if not IsPlayerAceAllowed(src, 'command.' .. name) then
        TriggerClientEvent('QBCore:Notify', src, 'No access to this command', 'error')
        return
    end

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

if Config.compat.fireSharedUpdateAtLogin then
    AddEventHandler('kora_core:server:playerLoaded', function(src)
        TriggerClientEvent('QBCore:Client:SharedUpdate', src, QBCore.Shared)
    end)
end

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

AddEventHandler('kora_core:server:playerDropped', function(src)
    stressLast[src] = nil
end)

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
