-- Core.player (client realm) -- client-side reads over the replicated mirror.
-- The heavy lifting lives in Core.replication (the mirror + delta apply); this
-- exposes the familiar player-shaped accessors on top of it.

---Full local PlayerData (live reference) or a sub-path.
---@param path (string|integer)[]|nil
---@return any
function Core.player.getPlayerData(path)
    return Core.replication.getData(path)
end

---Uses the same drawable lists as the legacy glove check.
---@return boolean
function Core.player.isWearingGloves()
    local ped = PlayerPedId()
    local noGloves
    if GetEntityModel(ped) == joaat('mp_m_freemode_01') then
        noGloves = QBCore.Shared.MaleNoGloves
    else
        noGloves = QBCore.Shared.FemaleNoGloves
    end
    return not (noGloves or {})[GetPedDrawableVariation(ped, 3)]
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
