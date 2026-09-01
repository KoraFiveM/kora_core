-- Core.development (server realm) -- ephemeral, per-player development-mode
-- authority. The public setter is the only activation path; the client owns
-- ped natives while the server-owned needs loop consults this same state.

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
    TriggerClientEvent('qbcore:client:setDevMode', src, enabled)
    TriggerEvent('qbcore:server:devModeChanged', src, enabled)
    return true
end

-- A character switch keeps the same connection/source. Re-announce the
-- ephemeral session state after the new character is adopted so the client
-- and server always converge even if another resource toggled during unload.
AddEventHandler('qbcore:server:playerLoaded', function(src)
    TriggerClientEvent('qbcore:client:setDevMode', src, enabledBySource[src] == true)
end)

AddEventHandler('qbcore:server:playerDropped', function(src)
    enabledBySource[src] = nil
end)
