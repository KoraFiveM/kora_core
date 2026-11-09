local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
Config.compat.vehicleSpawnCallbacks = 'admin'
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

handle.setPlayers({ 1 })
assert(Core.player.login(2, 'VEH2', CoreInternal.player.freshData('VEH2', 'license:veh2', 1, { firstname = 'C', lastname = 'D' })))
handle.setAce(1, 'qbcore.admin', true)
local function call(name, src, ...)
    local before = #handle.clientEvents
    handle.fireEvent('QBCore:Server:TriggerCallback', src, name, ...)
    for i = #handle.clientEvents, before + 1, -1 do
        if handle.clientEvents[i].name == 'QBCore:Client:TriggerCallback' then return handle.clientEvents[i].args[2] end
    end
    return 'no-reply'
end

h.test('admin mode refuses ordinary players and audits the refusal', function()
    h.assertEqual(call('QBCore:Server:SpawnVehicle', 2, 'reaper', nil, false), nil)
    h.assertEqual(#created, 0)
    h.assertEqual(logged[#logged].data.refused, 'permission')
end)

h.test('admin mode lets a kora admin spawn any model at any distance', function()
    local netId = call('QBCore:Server:SpawnVehicle', 1, 'customaddon', { x = 900.0, y = 0.0, z = 0.0, w = 1.0 }, false)
    h.assertTrue(type(netId) == 'number')
    h.assertEqual(created[1].fn, 'CreateVehicle')
    h.assertEqual(call('QBCore:Server:SpawnVehicle', 1, 'bad;name', nil, false), nil)
    h.assertEqual(#created, 1)
end)

h.report('vehicle_spawn_admin')
