Kora.callback.register('qb-multicharacter:server:GetUserCharacters', function(src)
    local license = Core.identity.primary(src)
    if not license then return {} end
    return Kora.sql.query('SELECT * FROM `players` WHERE `license` = ? AND `deleted_at` IS NULL', { license }) or {}
end)

Kora.callback.register('qb-multicharacter:server:GetNumberOfCharacters', function(src)
    local license = Core.identity.primary(src)
    if not license then return Config.identity.maxCharacters, {} end
    return Core.users.getMaxCharacters(license), {}
end)

Kora.callback.register('qb-multicharacter:server:setupCharacters', function(src)
    return Core.multichar.getCharacters(src)
end)

Kora.callback.register('qb-multicharacter:server:getSkin', function(_src, _citizenid)
    return nil
end)

RegisterNetEvent('qb-multicharacter:server:disconnect', function(reason)
    DropPlayer(source, reason or 'Disconnected.')
end)

RegisterNetEvent('qb-multicharacter:server:loadUserData', function(cData)
    local src = source
    if type(cData) ~= 'table' or not cData.citizenid then return end

    local ok, err = Core.multichar.selectCharacter(src, cData.citizenid)
    if not ok then
        TriggerClientEvent('multichar:client:selectFailed', src, err)
        return
    end

    cData.position = Core.player.getPlayerData(src, { 'position' })

    TriggerClientEvent('qb-spawn:client:setupSpawns', src, cData, false, nil)
    TriggerClientEvent('qb-spawn:client:openUI', src, true)
end)

RegisterNetEvent('qb-multicharacter:server:createCharacter', function(data)
    local src = source
    data = data or {}
    local citizenid, err = Core.player.createCharacter(src, data)
    if not citizenid then
        TriggerClientEvent('multichar:client:selectFailed', src, err)
        return
    end

    TriggerClientEvent('qb-multicharacter:client:closeNUIdefault', src)
end)

RegisterNetEvent('qb-multicharacter:server:deleteCharacter', function(citizenid)
    Core.multichar.deleteCharacter(source, citizenid)
end)

Kora.callback.register('qb-multicharacter:server:deleteCharacter', function(src, citizenid)
    return Core.multichar.deleteCharacter(src, citizenid)
end)
