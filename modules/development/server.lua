local enabledBySource = {}

---@param src integer
---@return boolean
function Core.development.isDevMode(src)
    return enabledBySource[src] == true
end

---Enable or disable development mode for one loaded player.
---@param src integer
---@param enabled boolean
---@return boolean success
---@return string|nil err
function Core.development.setDevMode(src, enabled)
    if type(src) ~= 'number' or not CoreInternal.player.handle(src) then
        return false, 'player is not loaded'
    end
    if type(enabled) ~= 'boolean' then return false, 'enabled must be a boolean' end

    local current = enabledBySource[src] == true
    if current == enabled then return true end

    enabledBySource[src] = enabled and true or nil
    TriggerClientEvent('kora_core:client:setDevMode', src, enabled)
    TriggerEvent('kora_core:server:devModeChanged', src, enabled)
    return true
end

AddEventHandler('kora_core:server:playerLoaded', function(src)
    TriggerClientEvent('kora_core:client:setDevMode', src, enabledBySource[src] == true)
end)

AddEventHandler('kora_core:server:playerDropped', function(src)
    enabledBySource[src] = nil
end)
