local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua')
local handle = mocks.install({ client = true })

dofile('config.lua')
dofile('build/initiate.lua')
dofile('modules/util/shared.lua')
dofile('compat/shared/coreobject.lua')

_G.GetEntityModel = function(vehicle) return vehicle * 10 end
_G.GetDisplayNameFromVehicleModel = function(model) return 'MODEL_' .. model end
_G.VehToNet = function(vehicle) return vehicle + 1000 end
_G.DoesEntityExist = function(vehicle) return vehicle ~= 0 end
QBCore.Functions.GetPlate = function(vehicle) return 'PLATE' .. vehicle end
_G.GetPedInVehicleSeat = function(vehicle, seat) return vehicle * 100 + seat end

dofile('compat/client/qb-core-events.lua')

h.test('cache entry attempt emits the legacy EnteringVehicle event', function()
    local info
    AddEventHandler('QBCore:Client:EnteringVehicle', function(data) info = data end)

    handle.setCache('enteringSeat', -1)
    handle.setCache('enteringVehicle', 200)

    h.assertTrue(info ~= nil, 'EnteringVehicle should fire once the cache sees an entry attempt')
    h.assertEqual(info.vehicle, 200)
    h.assertEqual(info.seat, -1)
    h.assertEqual(info.name, 'MODEL_2000')
    h.assertEqual(info.plate, 'PLATE200')
end)

h.test('cache vehicle/seat changes emit EnteredVehicle and LeftVehicle with the occupied seat', function()
    local entered, left
    AddEventHandler('QBCore:Client:EnteredVehicle', function(data) entered = data end)
    AddEventHandler('QBCore:Client:LeftVehicle', function(data) left = data end)

    handle.setCache('seat', 1)
    handle.setCache('vehicle', 200)

    h.assertTrue(entered ~= nil, 'EnteredVehicle should fire from the vehicle cache edge')
    h.assertEqual(entered.vehicle, 200)
    h.assertEqual(entered.seat, 1)

    handle.setCache('seat', false)
    handle.setCache('vehicle', false)

    h.assertTrue(left ~= nil, 'LeftVehicle should fire from the vehicle cache edge')
    h.assertEqual(left.vehicle, 200)
    h.assertEqual(left.seat, 1, 'the prior occupied seat should survive cache exit ordering')
end)

h.test('a cleared entry attempt emits AbortVehicleEntering only when not entered', function()
    local aborted = 0
    AddEventHandler('QBCore:Client:AbortVehicleEntering', function() aborted = aborted + 1 end)

    handle.setCache('enteringSeat', 0)
    handle.setCache('enteringVehicle', 300)
    handle.setCache('enteringVehicle', false)
    handle.drainTimeouts()

    h.assertEqual(aborted, 1, 'a vanished attempt while on foot should abort')

    handle.setCache('enteringVehicle', 400)
    handle.setCache('enteringVehicle', false)
    handle.setCache('seat', 0)
    handle.setCache('vehicle', 400)
    handle.drainTimeouts()

    h.assertEqual(aborted, 1, 'a completed entry must not also emit an abort')
end)

h.test('a kora_lib restart re-registers the vehicle bridge listeners', function()
    local onChange, registered = Kora.cache.onChange, {}
    Kora.cache.onChange = function(key, handler)
        registered[#registered + 1] = key
        return onChange(key, handler)
    end
    TriggerEvent('onClientResourceStart', 'kora_target')
    h.assertEqual(#registered, 0, 'other resources starting do not re-register')
    TriggerEvent('onClientResourceStart', 'kora_lib')
    Kora.cache.onChange = onChange
    table.sort(registered)
    h.assertEqual(table.concat(registered, ','), 'enteringVehicle,seat,vehicle')
end)

h.report('vehicle_cache_events')
