local function playerCanTakeNeedsDamage()
    if Core.development.isDevMode() then return nil end

    local ped = Kora.cache.ped()
    if not ped or ped == 0 or IsEntityDead(ped) then return nil end

    local metadata = Core.player.getPlayerData({ 'metadata' }) or {}
    if metadata.isdead == true or metadata.inlaststand == true then return nil end
    return ped
end

local function subscribeToEmptyNeed(key, configuredDamage)
    Core.player.onPlayerDataChange({ 'metadata', key }, function(_, value)
        local need = tonumber(value)
        local damage = tonumber(configuredDamage) or 0
        if not need or need > 0 or damage <= 0 then return end

        local ped = playerCanTakeNeedsDamage()
        if ped then ApplyDamageToPed(ped, damage, false) end
    end)
end

subscribeToEmptyNeed('hunger', Config.needs.hungerDamage)
subscribeToEmptyNeed('thirst', Config.needs.thirstDamage)
