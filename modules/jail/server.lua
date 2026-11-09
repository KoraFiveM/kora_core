local PI = CoreInternal.player

---@return boolean deferred True if an external prison resource is running and should handle this instead.
local function deferToExternal(src, minutes, reason)
    for _, resourceName in ipairs(Config.jail.deferToResources) do
        if GetResourceState(resourceName) == 'started' then
            TriggerEvent('qbcore:server:onJailRequest', src, minutes, reason, resourceName)
            return true
        end
    end
    return false
end

local function scheduleRelease(src, player, releaseAt)
    SetTimeout(math.max(0, releaseAt - os.time()) * 1000, function()
        local current = PI.handle(src)
        if current ~= player or current.PlayerData.metadata.jailed ~= releaseAt then return end

        if releaseAt > os.time() then
            scheduleRelease(src, player, releaseAt)
            return
        end

        Core.jail.release(src)
    end)
end

---@param src integer
---@param minutes number
---@param reason string|nil
---@return boolean, string|nil
function Core.jail.jailPlayer(src, minutes, reason)
    local p = PI.handle(src)
    if not p then return false, 'no such player' end
    minutes = tonumber(minutes)
    if not minutes or minutes <= 0 then return false, 'minutes must be positive' end

    if deferToExternal(src, minutes, reason) then
        return true
    end

    local releaseAt = os.time() + math.floor(minutes * 60)
    Core.player.setPath(src, { 'metadata', 'jailed' }, releaseAt)
    Core.player.setPath(src, { 'metadata', 'injail' }, releaseAt)
    TriggerClientEvent('qbcore:client:jailTeleport', src, Config.jail.coords, minutes * 60)
    TriggerEvent('qbcore:server:playerJailed', src, minutes, reason)
    scheduleRelease(src, p, releaseAt)

    return true
end

---Releases a player from Core.jail's own jail (not an external prison
---resource's -- that resource owns its own release flow once it has
---accepted a request via deferToExternal).
---@param src integer
---@return boolean
function Core.jail.release(src)
    local p = PI.handle(src)
    if not p then return false end
    if (p.PlayerData.metadata.jailed or 0) == 0 then return false end

    Core.player.setPath(src, { 'metadata', 'jailed' }, 0)
    Core.player.setPath(src, { 'metadata', 'injail' }, 0)
    TriggerClientEvent('qbcore:client:jailRelease', src)
    TriggerEvent('qbcore:server:playerReleased', src)

    return true
end

---@param src integer
---@return integer seconds Remaining jail time, or 0 if not jailed (or already expired).
function Core.jail.getRemaining(src)
    local p = PI.handle(src)
    if not p then return 0 end
    local releaseAt = p.PlayerData.metadata.jailed or 0
    if releaseAt == 0 then return 0 end
    return math.max(0, releaseAt - os.time())
end

---@param src integer
---@return boolean
function Core.jail.isJailed(src)
    return Core.jail.getRemaining(src) > 0
end

AddEventHandler('qbcore:server:playerLoaded', function(src)
    local p = PI.handle(src)
    if not p or (p.PlayerData.metadata.jailed or 0) == 0 then return end

    for _, resourceName in ipairs(Config.jail.deferToResources) do
        if GetResourceState(resourceName) == 'started' then return end
    end

    local remaining = Core.jail.getRemaining(src)
    if remaining <= 0 then
        Core.jail.release(src)
        return
    end

    TriggerClientEvent('qbcore:client:jailTeleport', src, Config.jail.coords, remaining)
    scheduleRelease(src, p, p.PlayerData.metadata.jailed)
end)

Core.commands.addCommand('jail', 'Jail a player', {
    { name = 'id', help = 'Player server id' },
    { name = 'minutes', help = 'Sentence length in minutes' },
    { name = 'reason', help = 'Reason (optional)' },
}, true, function(_, args)
    local target = tonumber(args[1])
    local minutes = tonumber(args[2])
    if not target or not minutes then return end
    Core.jail.jailPlayer(target, minutes, table.concat(args, ' ', 3))
end, 'admin')

Core.commands.addCommand('unjail', 'Release a player from jail', {
    { name = 'id', help = 'Player server id' },
}, true, function(_, args)
    local target = tonumber(args[1])
    if not target then return end
    Core.jail.release(target)
end, 'admin')
