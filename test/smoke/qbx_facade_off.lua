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
dofile('modules/inventory/shared.lua'); dofile('modules/inventory/server.lua')
dofile('modules/permissions/server.lua')
dofile('modules/commands/server.lua')
dofile('compat/shared/coreobject.lua')
dofile('compat/server/qb-core.lua')
dofile('compat/server/qb-core-events.lua')

local function exportCount(identity, name)
    local n = 0
    for _ in ipairs(handle.eventHandlers[('__cfx_export_%s_%s'):format(identity, name)] or {}) do n = n + 1 end
    return n
end

local watched = {
    'qbx_core:server:playerLoggedOut', 'qbx_core:server:onGroupUpdate',
}
local function snapshotHandlers()
    local counts = {}
    for name, list in pairs(handle.eventHandlers) do counts[name] = #list end
    return counts
end

local before = snapshotHandlers()

h.test('default config has the facade off', function()
    h.assertEqual(Config.compat.qbxFacade, false)
end)

h.test('loading qbx.lua while off registers no handler of any kind', function()
    dofile('compat/server/qbx.lua')
    local after = snapshotHandlers()
    for name, n in pairs(after) do h.assertEqual(n, before[name] or 0, 'handlers changed for ' .. name) end
    for _, fn in ipairs({ 'GetPlayer', 'GetPlayersData', 'CanUseItem', 'GetGroups', 'IsGradeBoss' }) do
        h.assertEqual(exportCount('qbx_core', fn), 0, 'qbx_core:' .. fn)
    end
    h.assertEqual(exportCount('qbx_vehicles', 'GetVehicleIdByPlate'), 0)
end)

h.test('no state bag or qbx event traffic from a login/logout while off', function()
    dofile('compat/server/qbx.lua')
    local data = CoreInternal.player.freshData('OFF1', 'license:off1', 1, { firstname = 'A', lastname = 'B', gender = 0 })
    Core.player.login(1, 'OFF1', data)
    handle.drainTimeouts()
    h.assertEqual(handle.playerStates[1].loadInventory, nil)
    Core.player.logout(1)
    for _, ev in ipairs(handle.clientEvents) do
        h.assertFalse(ev.name:find('^qbx_core:'), 'unexpected ' .. ev.name)
    end
    for _, name in ipairs(watched) do h.assertEqual(#(handle.eventHandlers[name] or {}), 0) end
end)

h.test('enabled but a real qbx_core exists: refuses and publishes nothing', function()
    Config.compat.qbxFacade = true
    handle.resourceStates.qbx_core = 'started'
    dofile('compat/server/qbx.lua')
    handle.resourceStates.qbx_core = nil
    Config.compat.qbxFacade = false
    h.assertEqual(exportCount('qbx_core', 'GetPlayer'), 0)
end)

h.report('qbx_facade_off')
