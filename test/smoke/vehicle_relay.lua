-- With Config.compat.vehicleSpawnCallbacks = 'off' the generic legacy vehicle
-- callbacks stay absent (the default 'limited' is covered by vehicle_spawn.lua).
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
Config.compat.vehicleSpawnCallbacks = 'off'
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
dofile('modules/persistence/schema.lua')
dofile('modules/persistence/boot.lua')
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
dofile('compat/server/qb-vehicles.lua')

for _, callbackName in ipairs({ 'QBCore:Server:SpawnVehicle', 'QBCore:Server:CreateVehicle' }) do
    h.test(callbackName .. ' is not reachable from the raw client callback wire', function()
        local called = false
        QBCore.Functions.SpawnVehicle = function() called = true; return 999 end
        QBCore.Functions.CreateAutomobile = function() called = true; return 999 end

        handle.fireEvent('QBCore:Server:TriggerCallback', 7, callbackName, 'police', { x = 1, y = 2, z = 3 }, true)

        h.assertFalse(called, 'an unauthorised request must not reach an entity creation native')
        h.assertTrue(handle.lastClient('QBCore:Client:TriggerCallback') == nil,
            'an absent callback must not manufacture a successful reply')
    end)
end

h.report('vehicle_relay')
