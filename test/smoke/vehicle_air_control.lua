local H = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua')
mocks.install({ client = true })

Config = nil
dofile('config.lua')

local cache, listeners = { vehicle = false, seat = false }, {}
Kora = { cache = {
    vehicle = function() return cache.vehicle end,
    seat = function() return cache.seat end,
    onChange = function(key, fn) listeners[key] = fn end,
} }
local function setCache(key, value) cache[key] = value; listeners[key](value) end

local threads, disabled = {}, {}
local air, allWheels, class = false, false, 1
function CreateThread(fn) threads[#threads + 1] = coroutine.create(fn) end
function Wait(ms) coroutine.yield(ms) end
function DoesEntityExist() return true end
function IsEntityInAir() return air end
function IsVehicleOnAllWheels() return allWheels end
function GetVehicleClass() return class end
function DisableControlAction(_, control) disabled[control] = true end

local function step()
    disabled = {}
    for i = #threads, 1, -1 do
        local co = threads[i]
        if coroutine.status(co) == 'dead' then table.remove(threads, i)
        else assert(coroutine.resume(co)) end
    end
end

dofile('modules/vehicleAirControl/client.lua')

H.test('defaults: enabled, aircraft/boats/bikes/cycles/trains exempt, cars not', function()
    H.assertTrue(Config.vehicleAirControl.disable)
    local exempt = {}
    for _, c in ipairs(Config.vehicleAirControl.exemptClasses) do exempt[c] = true end
    H.assertTrue(exempt[8] and exempt[21] and exempt[13] and exempt[14] and exempt[15] and exempt[16])
    H.assertFalse(exempt[1] or false)
end)

H.test('no worker for a passenger or on foot', function()
    setCache('seat', 0); setCache('vehicle', 7)
    H.assertEqual(#threads, 0)
end)

H.test('driver on the ground keeps controls, airborne loses them, upside down on ground keeps them', function()
    setCache('seat', -1)
    H.assertEqual(#threads, 1)
    step(); H.assertEqual(next(disabled), nil)
    air = true; step(); step()
    H.assertTrue(disabled[59] and disabled[60] and disabled[63] and disabled[64])
    air = false; step()
    H.assertEqual(next(disabled), nil)
    air, allWheels = true, true; step(); step()
    H.assertEqual(next(disabled), nil)
    allWheels = false
end)

H.test('leaving the vehicle stops the worker', function()
    setCache('vehicle', false)
    air = true; step(); step()
    H.assertEqual(next(disabled), nil)
    H.assertEqual(#threads, 0)
end)

H.test('exempt class and disable=false start no worker', function()
    class = 15; setCache('vehicle', 8); H.assertEqual(#threads, 0)
    class = 8; setCache('vehicle', false); setCache('vehicle', 10); H.assertEqual(#threads, 0)
    class = 1; Config.vehicleAirControl.disable = false
    setCache('vehicle', false); setCache('vehicle', 9); H.assertEqual(#threads, 0)
    Config.vehicleAirControl.disable = true
    setCache('vehicle', false); setCache('vehicle', 9); H.assertEqual(#threads, 1)
end)

H.test('a kora_lib restart re-registers the cache listeners and re-seeds the vehicle', function()
    setCache('vehicle', false)
    for i = #threads, 1, -1 do table.remove(threads, i) end
    listeners = {}             -- the restarted kora_lib forgot every onChange
    cache.vehicle, cache.seat = 12, -1
    TriggerEvent('onClientResourceStart', 'kora_lib')
    H.assertEqual(#threads, 1, 'the driver seat read from the new cache starts a worker')
    H.assertTrue(type(listeners.vehicle) == 'function' and type(listeners.seat) == 'function')
    setCache('vehicle', false)
    air = true; step(); step()
    H.assertEqual(next(disabled), nil)
    air = false
end)

H.report('vehicle_air_control')
