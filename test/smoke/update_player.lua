local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
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

h.test('QBCore:UpdatePlayer saves once, then a repeat within the cooldown window is a no-op', function()
    Core.metadata.setMetaData(1, 'hunger', 77)

    local before = #handle.sqlCalls.enqueue
    handle.fireEvent('QBCore:UpdatePlayer', 1)
    h.assertEqual(#handle.sqlCalls.enqueue, before + 1, 'first call should save')

    Core.metadata.setMetaData(1, 'hunger', 55)
    handle.fireEvent('QBCore:UpdatePlayer', 1)
    h.assertEqual(#handle.sqlCalls.enqueue, before + 1, 'repeat within cooldown must not save again')
end)

h.test('QBCore:UpdatePlayer saves again once the cooldown has elapsed', function()
    Core.metadata.setMetaData(1, 'hunger', 33)
    local before = #handle.sqlCalls.enqueue

    for _ = 1, 700 do GetGameTimer() end

    handle.fireEvent('QBCore:UpdatePlayer', 1)
    h.assertEqual(#handle.sqlCalls.enqueue, before + 1, 'call after the cooldown window should save again')
end)

h.test('qbcore:server:playerDropped clears the cooldown entry (no leak)', function()
    TriggerEvent('qbcore:server:playerDropped', 1, 'CID1', 'test')

    Core.metadata.setMetaData(1, 'hunger', 11)
    local before = #handle.sqlCalls.enqueue
    handle.fireEvent('QBCore:UpdatePlayer', 1)
    h.assertEqual(#handle.sqlCalls.enqueue, before + 1, 'cooldown must be cleared by playerDropped, not left stale')
end)

h.report('update_player')
