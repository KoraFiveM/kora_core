-- compat/server/qb-multicharacter.lua -- event-level compat only. We do NOT
-- `provide 'qb-multicharacter'` (see fxmanifest): hijacking the name would
-- silently disable a real character-select UI a server wants to keep. Instead we
-- listen for the legacy events and route them to Core.multichar.

RegisterNetEvent('qb-multicharacter:server:setupCharacters', function()
    local src = source
    TriggerClientEvent('qb-multicharacter:client:setupCharacters', src, Core.multichar.getCharacters(src))
end)

RegisterNetEvent('qb-multicharacter:server:loadUserData', function(citizenid)
    local src = source
    Core.multichar.selectCharacter(src, citizenid)
end)

RegisterNetEvent('qb-multicharacter:server:createCharacter', function(data)
    local src = source
    Core.player.createCharacter(src, data or {})
end)

RegisterNetEvent('qb-multicharacter:server:deleteCharacter', function(citizenid)
    Core.multichar.deleteCharacter(source, citizenid)
end)
