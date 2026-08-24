-- Core.needs (client realm) -- applies the physical consequence of the
-- server-authoritative hunger/thirst decay. The server remains the clock and
-- metadata authority; this file only reacts to its replicated need updates.

local function playerCanTakeNeedsDamage()
    local ped = PlayerPedId()
    if not ped or ped == 0 or IsEntityDead(ped) then return nil end

    -- Ambulance flows can mark a player dead/last-stand before GTA reports the
    -- ped as natively dead. Respect both states so needs damage never interferes
    -- with a death or revival flow.
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

-- Deliberately separate subscriptions/calls: when both values are empty the
-- same server tick produces both deltas and therefore both damage amounts.
subscribeToEmptyNeed('hunger', Config.needs.hungerDamage)
subscribeToEmptyNeed('thirst', Config.needs.thirstDamage)
