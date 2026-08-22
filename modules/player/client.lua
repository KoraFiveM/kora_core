-- Core.player (client realm) -- client-side reads over the replicated mirror.
-- The heavy lifting lives in Core.replication (the mirror + delta apply); this
-- exposes the familiar player-shaped accessors on top of it.

---Full local PlayerData (live reference) or a sub-path.
---@param path (string|integer)[]|nil
---@return any
function Core.player.getPlayerData(path)
    return Core.replication.getData(path)
end

---Subscribe to PlayerData changes under a path prefix. handler(path, value).
---@param pathPrefix (string|integer)[]
---@param handler fun(path:table, value:any)
---@return integer|nil, string|nil
function Core.player.onPlayerDataChange(pathPrefix, handler)
    return Core.replication.onChange(pathPrefix, handler)
end

---@param id integer
function Core.player.offPlayerDataChange(id)
    Core.replication.offChange(id)
end
