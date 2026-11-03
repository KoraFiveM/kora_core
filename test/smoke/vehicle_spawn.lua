-- QBCore:Server:SpawnVehicle / CreateVehicle (compat/server/qb-vehicles.lua) in
-- 'limited' mode: stock args and netId return, validated and rate limited.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
Config.compat.vehicleSpawnCallbacks = 'limited'
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
dofile('modules/persistence/migrate.lua')
dofile('modules/player/server.lua')
dofile('modules/money/server.lua')
dofile('modules/jobs/server.lua')
dofile('modules/metadata/server.lua')
dofile('modules/inventory/server.lua')
dofile('modules/inventory/gateway.lua')
dofile('modules/multichar/server.lua')
dofile('modules/permissions/server.lua')
dofile('modules/commands/server.lua')
dofile('compat/server/qb-core.lua')
dofile('compat/server/qb-core-events.lua')
dofile('compat/server/qb-vehicles.lua')

local logged = {}
Core.logging = { logEvent = function(category, src, data) logged[#logged + 1] = { category = category, src = src, data = data } end }
handle.resourceStates.kora_vehiclekeys = 'started'
local keys = {}
exports.kora_vehiclekeys = { giveKeys = function(_, src, plate) keys[#keys + 1] = { src, plate }; return true end }

local now, nextEntity = 10000, 500
local created, deleted, alive = {}, {}, {}
_G.GetGameTimer = function() return now end
_G.GetPlayerPed = function(id) return id + 100 end
_G.GetEntityCoords = function() return { x = 0.0, y = 0.0, z = 0.0 } end
_G.GetEntityHeading = function() return 45.0 end
_G.CreateVehicle = function(model, x, y, z, heading)
    nextEntity = nextEntity + 1
    created[#created + 1] = { fn = 'CreateVehicle', model = model, x = x, y = y, z = z, heading = heading, entity = nextEntity }
    alive[nextEntity] = true
    return nextEntity
end
_G.CreateVehicleServerSetter = function(model, vtype, coords, heading)
    nextEntity = nextEntity + 1
    created[#created + 1] = { fn = 'CreateVehicleServerSetter', model = model, vtype = vtype, entity = nextEntity }
    alive[nextEntity] = true
    return nextEntity
end
_G.DoesEntityExist = function(e) return alive[e] == true end
_G.DeleteEntity = function(e) alive[e] = nil; deleted[#deleted + 1] = e end
_G.NetworkGetEntityOwner = function() return 1 end
_G.NetworkGetNetworkIdFromEntity = function(e) return e + 9000 end
_G.GetVehicleNumberPlateText = function(e) return 'PL' .. e end
_G.GetVehiclePedIsIn = function() return 0 end
_G.TaskWarpPedIntoVehicle = function() end

assert(Core.player.login(1, 'VEH1', CoreInternal.player.freshData('VEH1', 'license:veh1', 1, { firstname = 'A', lastname = 'B' })))
handle.setPlayers({ 1 })

local vehicleName = next(QBCore.Shared.Vehicles)
local function call(name, src, ...)
    local before = #handle.clientEvents
    handle.fireEvent('QBCore:Server:TriggerCallback', src, name, ...)
    for i = #handle.clientEvents, before + 1, -1 do
        if handle.clientEvents[i].name == 'QBCore:Client:TriggerCallback' then return handle.clientEvents[i].args[2] end
    end
    return 'no-reply'
end
local function step() now = now + 5000 end

h.test('SpawnVehicle returns the netId of a server-created networked vehicle', function()
    local netId = call('QBCore:Server:SpawnVehicle', 1, vehicleName, { x = 10.0, y = 5.0, z = 2.0, w = 90.0 }, false)
    h.assertEqual(netId, created[1].entity + 9000)
    h.assertEqual(created[1].fn, 'CreateVehicle')
    h.assertEqual(created[1].heading, 90.0)
    h.assertEqual(keys[#keys][2], 'PL' .. created[1].entity, 'keys are granted through kora_vehiclekeys')
    h.assertEqual(logged[#logged].category, 'vehicle')
end)

h.test('CreateVehicle uses the server setter and also returns a netId', function()
    step()
    local netId = call('QBCore:Server:CreateVehicle', 1, vehicleName, nil, false)
    h.assertEqual(created[#created].fn, 'CreateVehicleServerSetter')
    h.assertEqual(netId, created[#created].entity + 9000)
end)

h.test('model names outside the shared list and the allow-list are refused', function()
    step(); local count = #created
    h.assertEqual(call('QBCore:Server:SpawnVehicle', 1, 'notarealcar', nil, false), nil)
    h.assertEqual(call('QBCore:Server:SpawnVehicle', 1, 'bad;name', nil, false), nil)
    h.assertEqual(call('QBCore:Server:SpawnVehicle', 1, { 'x' }, nil, false), nil)
    h.assertEqual(#created, count)
    Config.compat.vehicleSpawn.allowModels = { 'notarealcar' }
    step()
    h.assertTrue(type(call('QBCore:Server:SpawnVehicle', 1, 'notarealcar', nil, false)) == 'number')
    Config.compat.vehicleSpawn.allowModels = {}
end)

h.test('a model hash of a shared vehicle is accepted', function()
    step()
    h.assertTrue(type(call('QBCore:Server:SpawnVehicle', 1, joaat(vehicleName), nil, false)) == 'number')
end)

h.test('coords beyond maxDistance or malformed are refused', function()
    step(); local count = #created
    h.assertEqual(call('QBCore:Server:SpawnVehicle', 1, vehicleName, { x = 500.0, y = 0.0, z = 0.0 }, false), nil)
    step()
    h.assertEqual(call('QBCore:Server:SpawnVehicle', 1, vehicleName, { x = 'a', y = 0, z = 0 }, false), nil)
    step()
    h.assertEqual(call('QBCore:Server:SpawnVehicle', 1, vehicleName, { x = 0 / 0, y = 0, z = 0 }, false), nil)
    step()
    h.assertEqual(call('QBCore:Server:SpawnVehicle', 1, vehicleName, 'x', false), nil)
    h.assertEqual(#created, count)
    h.assertTrue(logged[#logged].data.refused ~= nil, 'refusals are audited')
end)

h.test('requests inside the cooldown are refused', function()
    step(); local count = #created
    h.assertTrue(type(call('QBCore:Server:SpawnVehicle', 1, vehicleName, nil, false)) == 'number')
    now = now + 100
    h.assertEqual(call('QBCore:Server:SpawnVehicle', 1, vehicleName, nil, false), nil)
    h.assertEqual(#created, count + 1)
end)

h.test('only maxLive vehicles stay alive; the oldest is deleted', function()
    Config.compat.vehicleSpawn.maxLive = 2
    local spawned = {}
    for i = 1, 4 do step(); call('QBCore:Server:SpawnVehicle', 1, vehicleName, nil, false); spawned[i] = created[#created].entity end
    h.assertFalse(alive[spawned[1]]); h.assertFalse(alive[spawned[2]])
    h.assertTrue(alive[spawned[3]]); h.assertTrue(alive[spawned[4]])
end)

h.test('callers that are not loaded players are refused', function()
    step(); local count = #created
    h.assertEqual(call('QBCore:Server:SpawnVehicle', 7, vehicleName, nil, false), nil)
    h.assertEqual(#created, count)
end)

h.test('leaving the server deletes the player\'s compat-spawned vehicles', function()
    step(); call('QBCore:Server:SpawnVehicle', 1, vehicleName, nil, false)
    local entity = created[#created].entity
    TriggerEvent('qbcore:server:playerDropped', 1, 'VEH1')
    h.assertFalse(alive[entity])
end)

h.report('vehicle_spawn')
