local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
Config.compat.fireSharedUpdateAtLogin = true

dofile('shared/items.lua'); dofile('shared/jobs.lua'); dofile('shared/gangs.lua')
dofile('shared/vehicles.lua'); dofile('shared/weapons.lua'); dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua'); dofile('modules/registry/server.lua')
dofile('modules/player/shared.lua')
dofile('modules/replication/server.lua'); dofile('modules/persistence/server.lua')
dofile('modules/player/server.lua')
dofile('modules/money/server.lua')
dofile('modules/jobs/server.lua')
dofile('modules/metadata/server.lua')
dofile('modules/permissions/server.lua')
dofile('modules/commands/server.lua')
dofile('compat/shared/coreobject.lua')
dofile('compat/server/qb-core.lua')
dofile('compat/server/qb-core-events.lua')

local data = CoreInternal.player.freshData('CID1', 'license:abc', 1, { firstname = 'A', lastname = 'B' })
Core.player.login(1, 'CID1', data)

h.test('fireSharedUpdateAtLogin = true fires QBCore:Client:SharedUpdate with the current QBCore.Shared table', function()
    local before = #handle.clientEvents
    TriggerEvent('kora_core:server:playerLoaded', 1, 'CID1')

    local found
    for i = before + 1, #handle.clientEvents do
        if handle.clientEvents[i].name == 'QBCore:Client:SharedUpdate' then found = handle.clientEvents[i] end
    end
    h.assertTrue(found ~= nil, 'must fire QBCore:Client:SharedUpdate when the opt-in is on')
    h.assertEqual(found.target, 1, 'must target the invoking source')
    h.assertEqual(found.args[1], QBCore.Shared, 'payload must be the live QBCore.Shared table')
end)

h.report('qb_core_events_shared_update_opt_in')
