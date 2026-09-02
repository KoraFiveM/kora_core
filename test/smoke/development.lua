-- Core.development smoke test -- server export authority plus client ped
-- effects, ped replacement, disable, and resource-stop cleanup.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('build/initiate.lua')

local loaded = { [1] = true }
CoreInternal.player = {
    handle = function(src) return loaded[src] and { source = src } or nil end,
}

dofile('modules/development/server.lua')

h.test('setDevMode validates the target and boolean state', function()
    local ok, err = Core.development.setDevMode(99, true)
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)

    ok, err = Core.development.setDevMode(1, 'true')
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
end)

h.test('server export activates one player and pushes the client state', function()
    local before = #handle.clientEvents
    local ok = Core.development.setDevMode(1, true)

    h.assertTrue(ok)
    h.assertTrue(Core.development.isDevMode(1))
    h.assertEqual(#handle.clientEvents, before + 1)
    local event = handle.clientEvents[#handle.clientEvents]
    h.assertEqual(event.name, 'qbcore:client:setDevMode')
    h.assertEqual(event.target, 1)
    h.assertTrue(event.args[1])

    Core.development.setDevMode(1, true)
    h.assertEqual(#handle.clientEvents, before + 1, 'setting the current state should be idempotent')
end)

h.test('server export disables the mode and disconnect forgets it', function()
    local ok = Core.development.setDevMode(1, false)
    h.assertTrue(ok)
    h.assertFalse(Core.development.isDevMode(1))

    Core.development.setDevMode(1, true)
    handle.fireEvent('qbcore:server:playerDropped', 0, 1)
    h.assertFalse(Core.development.isDevMode(1))
end)

-- Exercise the client realm with a fresh Core namespace. The mock event bus is
-- retained so the real registered net event drives activation/deactivation.
_G.Core = setmetatable({}, { __index = function(self, key)
    local module = {}
    rawset(self, key, module)
    return module
end })

local currentPed = 41
local exists = { [41] = true, [52] = true }
local invincible = {}
local moveRate = {}
local staminaRestores = {}

QB.cache.ped = function() return currentPed end
QB.cache.playerId = function() return 7 end
_G.DoesEntityExist = function(ped) return exists[ped] == true end
_G.SetEntityInvincible = function(ped, state) invincible[ped] = state end
_G.SetPedMoveRateOverride = function(ped, rate) moveRate[ped] = rate end
_G.RestorePlayerStamina = function(playerId, amount)
    table.insert(staminaRestores, { playerId = playerId, amount = amount })
end

dofile('modules/development/client.lua')

h.test('client activation applies god mode and the configured fast walk rate', function()
    h.assertFalse(Core.development.isDevMode())
    TriggerEvent('qbcore:client:setDevMode', true)

    h.assertTrue(Core.development.isDevMode())
    h.assertTrue(invincible[41], 'current ped should be invincible')
    h.assertEqual(moveRate[41], Config.development.walkSpeed)
    h.assertTrue(#staminaRestores > 0, 'stamina should be refilled while active')
    h.assertEqual(staminaRestores[#staminaRestores].playerId, 7)
    h.assertEqual(staminaRestores[#staminaRestores].amount, 1.0)
end)

h.test('a replacement ped is protected and the previous ped is restored', function()
    currentPed = 52
    Core.development._tick()

    h.assertFalse(invincible[41], 'previous ped invincibility should be restored')
    h.assertEqual(moveRate[41], 1.0, 'previous ped move rate should be restored')
    h.assertTrue(invincible[52], 'replacement ped should be invincible')
    h.assertEqual(moveRate[52], Config.development.walkSpeed)
end)

h.test('client deactivation restores the active ped', function()
    TriggerEvent('qbcore:client:setDevMode', false)
    local restoresBefore = #staminaRestores
    Core.development._tick()
    h.assertEqual(#staminaRestores, restoresBefore, 'stamina refill should stop when disabled')

    h.assertFalse(Core.development.isDevMode())
    h.assertFalse(invincible[52], 'active ped invincibility should be restored')
    h.assertEqual(moveRate[52], 1.0, 'active ped move rate should be restored')
end)

h.test('resource stop also restores an active mode', function()
    TriggerEvent('qbcore:client:setDevMode', true)
    handle.fireEvent('onClientResourceStop', 0, 'qbcore')

    h.assertFalse(Core.development.isDevMode())
    h.assertFalse(invincible[52])
    h.assertEqual(moveRate[52], 1.0)
end)

h.report('development')
