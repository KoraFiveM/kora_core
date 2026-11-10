local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua')
local handle = mocks.install()

local invokingResource
_G.GetInvokingResource = function() return invokingResource end

dofile('config.lua')
dofile('shared/items.lua'); dofile('shared/jobs.lua'); dofile('shared/gangs.lua')
dofile('shared/vehicles.lua'); dofile('shared/weapons.lua'); dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua'); dofile('modules/registry/server.lua')
dofile('modules/player/shared.lua')
dofile('modules/replication/server.lua')
dofile('modules/persistence/server.lua')
dofile('modules/player/server.lua')

h.test('resource fields hydrate before the initial snapshot without becoming dirty columns', function()
    invokingResource = 'kora_skills'
    local registered, err = Core.player.registerPlayerDataField('skills', function(src, citizenid)
        h.assertEqual(src, 1)
        h.assertEqual(citizenid, 'FIELD1')
        return { mining = { level = 4 } }
    end)
    h.assertTrue(registered, err)
    invokingResource = nil

    local data = CoreInternal.player.freshData('FIELD1', 'license:test', 1, { firstname = 'Field', lastname = 'Test' })
    h.assertTrue(Core.player.login(1, 'FIELD1', data))
    local snapshot = handle.lastClient('kora_core:rep:snapshot')
    h.assertEqual(snapshot.args[2].skills.mining.level, 4)
    h.assertEqual(next(CoreInternal.player.handle(1)._dirty), nil, 'replicated-only fields must not dirty player columns')
end)

h.test('only the registering resource can update its field', function()
    invokingResource = 'other-resource'
    local updated = Core.player.setPlayerDataField(1, 'skills', { mining = { level = 99 } })
    h.assertEqual(updated, false)
    updated = Core.player.setPath(1, { 'skills' }, { mining = { level = 99 } })
    h.assertEqual(updated, false, 'generic setPath must also enforce field ownership')

    invokingResource = 'kora_skills'
    updated = Core.player.setPlayerDataField(1, 'skills', { mining = { level = 5 } })
    h.assertTrue(updated)
    h.assertEqual(Core.player.getPlayerData(1, { 'skills', 'mining', 'level' }), 5)
    invokingResource = nil
end)

h.test('stopping the owner removes its replicated field', function()
    TriggerEvent('onResourceStop', 'kora_skills')
    h.assertEqual(Core.player.getPlayerData(1, { 'skills' }), nil)
end)

h.report('player_data_fields')
