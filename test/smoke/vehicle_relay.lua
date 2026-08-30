-- Server-side legacy vehicle spawn callback smoke tests. Vehicle lifecycle
-- compatibility moved to vehicle_cache_events.lua, where qblib cache changes
-- re-fire the local QBCore client events without an extra poll or server relay.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('build/initiate.lua')
dofile('shared/items.lua'); dofile('shared/vehicles.lua'); dofile('shared/jobs.lua')
dofile('shared/gangs.lua'); dofile('shared/weapons.lua'); dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua')
dofile('modules/player/shared.lua')
dofile('modules/inventory/shared.lua')
dofile('compat/shared/coreobject.lua')

dofile('modules/registry/server.lua')
dofile('modules/identity/server.lua')
dofile('modules/replication/server.lua')
dofile('modules/persistence/server.lua')
dofile('modules/persistence/migrate.lua')
dofile('modules/player/server.lua')
dofile('modules/money/server.lua')
dofile('modules/jobs/server.lua')
dofile('modules/dispatch/server.lua')
dofile('modules/paycheck/server.lua')
dofile('modules/metadata/server.lua')
dofile('modules/needs/server.lua')
dofile('modules/inventory/server.lua')
dofile('modules/inventory/gateway.lua')
dofile('modules/multichar/server.lua')
dofile('modules/permissions/server.lua')
dofile('modules/commands/server.lua')
dofile('modules/logging/server.lua')
dofile('modules/garage/server.lua')
dofile('modules/consumables/server.lua')
dofile('modules/jail/server.lua')
dofile('compat/server/qb-core.lua')
dofile('compat/server/qb-core-events.lua')

-- QBCore:Server:SpawnVehicle / CreateVehicle -- real qb-core's own two
-- standard vehicle-spawn callbacks (server/events.lua), wired up in
-- compat/server/qb-core-events.lua onto the already-present
-- QBCore.Functions.SpawnVehicle/CreateAutomobile. Stubbed here rather than
-- exercising the real native-heavy spawn loop (that's ported verbatim and
-- native-only, nothing this test harness can usefully mock) -- what's under
-- test is that TriggerCallback('QBCore:Server:SpawnVehicle', ...) actually
-- reaches a handler and replies, which is exactly what was broken before
-- (the callback was never registered, so every call timed out and replied
-- with nothing).
h.test('QBCore:Server:SpawnVehicle spawns via QBCore.Functions.SpawnVehicle and replies with a netId', function()
    local spawnArgs
    QBCore.Functions.SpawnVehicle = function(source, model, coords, warp)
        spawnArgs = { source = source, model = model, coords = coords, warp = warp }
        return 999 -- fake vehicle entity handle
    end
    _G.DoesEntityExist = function(ent) return ent == 999 end
    _G.NetworkGetNetworkIdFromEntity = function() return 555 end

    handle.fireEvent('QBCore:Server:TriggerCallback', 7, 'QBCore:Server:SpawnVehicle', 'police', { x = 1, y = 2, z = 3 }, true)

    local ev = handle.lastClient('QBCore:Client:TriggerCallback')
    h.assertTrue(ev ~= nil, 'a reply must be sent')
    h.assertEqual(ev.args[1], 'QBCore:Server:SpawnVehicle')
    h.assertEqual(ev.args[2], 555, 'the reply must carry the spawned vehicle netId')
    h.assertEqual(spawnArgs.source, 7)
    h.assertEqual(spawnArgs.model, 'police')
    h.assertTrue(spawnArgs.warp)
end)

h.test('QBCore:Server:SpawnVehicle replies with nil (not a timeout) when the vehicle failed to spawn', function()
    QBCore.Functions.SpawnVehicle = function() return 0 end
    _G.DoesEntityExist = function() return false end

    handle.fireEvent('QBCore:Server:TriggerCallback', 7, 'QBCore:Server:SpawnVehicle', 'police')

    local ev = handle.lastClient('QBCore:Client:TriggerCallback')
    h.assertTrue(ev ~= nil, 'a reply must still be sent even on a failed spawn')
    h.assertTrue(ev.args[2] == nil, 'a failed spawn must reply with nil')
end)

h.test('QBCore:Server:CreateVehicle spawns via QBCore.Functions.CreateAutomobile and replies with a netId', function()
    local called = false
    QBCore.Functions.CreateAutomobile = function() called = true; return 999 end
    _G.DoesEntityExist = function() return true end
    _G.NetworkGetNetworkIdFromEntity = function() return 777 end

    handle.fireEvent('QBCore:Server:TriggerCallback', 7, 'QBCore:Server:CreateVehicle', 'ambulance')

    h.assertTrue(called, 'CreateAutomobile must be invoked, not SpawnVehicle')
    local ev = handle.lastClient('QBCore:Client:TriggerCallback')
    h.assertEqual(ev.args[2], 777)
end)

h.report('vehicle_relay')
