-- Core.permissions (server realm) -- the legacy QBCore permission vocabulary
-- ('user'/'mod'/'admin'/'god') mapped onto ace principals under the
-- 'qbcore.' namespace. The generic ACE lookup lives in qblib
-- (modules/permissions) so other resources can share it under their own
-- namespace; addPermission stays here because it needs Core.identity.

local LEVELS = { 'god', 'admin', 'mod', 'user' }   -- most-privileged first
local PREFIX = 'qbcore'

---@param src integer
---@return string
function Core.permissions.getPermission(src)
    return QB.permissions.getLevel(src, LEVELS, PREFIX)
end

---@param src integer
---@param permission string
---@return boolean
function Core.permissions.hasPermission(src, permission)
    return QB.permissions.hasPermission(src, permission, PREFIX)
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
---@return boolean  -- whether the player opted into admin/dev features
function Core.permissions.isOptin(src)
    -- Opt-in only makes sense for privileged players; default to their perm.
    return Core.permissions.getPermission(src) ~= 'user'
end
