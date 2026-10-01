local h = dofile('test/harness.lua')
local handler, clock, readyAt, controlled = nil, 0, 100, true
local applied, controlCalls = {}, 0
QB = {
    util = { isFiniteNumber = function(value)
        return type(value) == 'number' and value == value and math.abs(value) < math.huge
    end },
    entities = { requestControl = function(entity)
        assert(entity == 42)
        controlCalls = controlCalls + 1
        return controlled, 'no control'
    end },
}
RegisterNetEvent = function(_, callback) handler = callback end
CreateThread = function(callback) callback() end
GetGameTimer = function() return clock end
Wait = function(ms) clock = clock + ms end
NetworkGetEntityFromNetworkId = function(id) return id == 1042 and clock >= readyAt and 42 or 0 end
DoesEntityExist = function(entity) return entity == 42 end
GetEntityType = function() return 2 end
SetVehicleFuelLevel = function(entity, fuel) applied.fuel = fuel; assert(entity == 42) end
SetVehicleEngineHealth = function(entity, health) applied.engine = health; assert(entity == 42) end
dofile('modules/garage/client.lua')

h.test('server condition waits for streaming and applies once after acquiring control', function()
    source = 65535
    handler(1042, 42, 750)
    h.assertEqual(clock, 100)
    h.assertEqual(controlCalls, 1)
    h.assertEqual(applied.fuel, 42)
    h.assertEqual(applied.engine, 750)
end)

h.test('invalid, local, unstreamed and uncontrolled requests do not alter condition', function()
    applied = {}
    source = nil
    handler(1042, 1, 1)
    source = 65535
    handler(0 / 0, 1, 1)
    handler(1042, math.huge, 1)
    local before = clock
    handler(999, 1, 1)
    h.assertEqual(clock - before, 5000)
    controlled = false
    handler(1042, 1, 1)
    h.assertEqual(next(applied), nil)
end)
h.report('garage client')
