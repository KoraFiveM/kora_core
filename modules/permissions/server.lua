local LEVELS = { 'god', 'admin', 'mod', 'user' }
local PREFIX = 'qbcore'

---@param src integer
---@return string
function Core.permissions.getPermission(src)
    return Kora.permissions.getLevel(src, LEVELS, PREFIX)
end

---@param src integer
---@param permission string
---@return boolean
function Core.permissions.hasPermission(src, permission)
    return Kora.permissions.hasPermission(src, permission, PREFIX)
end

---Grant a runtime permission by adding an ace principal for the player's license.
---@param src integer
---@param permission string
function Core.permissions.addPermission(src, permission)
    local license = Core.identity.primary(src)
    if not license then return false end
    ExecuteCommand(('add_principal identifier.%s:%s qbcore.%s'):format(Config.identity.primaryIdentifier, license:gsub('^%w+:', ''), permission))
    return true
end

---Revoke a runtime permission by removing the ace principal added by addPermission.
---@param src integer
---@param permission string
function Core.permissions.removePermission(src, permission)
    local license = Core.identity.primary(src)
    if not license then return false end
    ExecuteCommand(('remove_principal identifier.%s:%s qbcore.%s'):format(Config.identity.primaryIdentifier, license:gsub('^%w+:', ''), permission))
    return true
end

---@param src integer
---@return boolean  -- whether the player opted into admin/dev features (a privileged level; PlayerData.optin == false opts out)
function Core.permissions.isOptin(src)
    if Core.permissions.getPermission(src) == 'user' then return false end
    local player = CoreInternal.player and CoreInternal.player.handle and CoreInternal.player.handle(src)
    return not (player and player.PlayerData.optin == false)
end
