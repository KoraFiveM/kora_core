-- Core.consumables smoke test -- the generic item-effect bridge: deferred
-- registration against kora_inventory's 'usingItem' hook, and the actual
-- effect/hunger/thirst/stress playback once registered.
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
dofile('modules/metadata/server.lua')

local data = CoreInternal.player.freshData('CID1', 'license:abc', 1, { firstname = 'A', lastname = 'B' })
Core.player.login(1, 'CID1', data)

Core.registry.registerShared('items', 'weed_joint', {
    name = 'weed_joint', label = 'Joint', weight = 10, type = 'item', useable = true,
    effect = { duration = 1000, hungerDelta = 5, thirstDelta = -5, stressDelta = -10 },
})
Core.registry.registerShared('items', 'water_bottle', {
    name = 'water_bottle', label = 'Water', weight = 500, type = 'item', useable = true,
    -- no `effect` table -- this item should be a no-op for Core.consumables
})

local registeredHookCallback

handle.resourceStates.kora_inventory = 'missing'
_G.exports.kora_inventory = {
    RegisterHook = function(_, eventName, callback)
        h.assertEqual(eventName, 'usingItem')
        registeredHookCallback = callback
    end,
}

dofile('modules/consumables/server.lua')

h.test('registration is deferred while qbinventory is not running', function()
    h.assertFalse(Core.consumables.isRegistered())
    h.assertTrue(registeredHookCallback == nil, 'the hook must not be registered before qbinventory starts')
end)

h.test('onResourceStart for qbinventory registers the hook', function()
    handle.resourceStates.kora_inventory = 'started'
    handle.fireEvent('onResourceStart', nil, 'kora_inventory')

    h.assertTrue(Core.consumables.isRegistered())
    h.assertTrue(registeredHookCallback ~= nil)
end)

h.test('a second onResourceStart for qbinventory (a restart) re-registers the hook, not skipped by a stale latch', function()
    -- This is the regression test for the latch bug: register() must not
    -- permanently no-op after its first success. Fire onResourceStart a
    -- SECOND time (simulating kora_inventory restarting mid-session, having
    -- already been registered once) and assert RegisterHook is actually
    -- called again -- a stale `if registered then return end` guard would
    -- make this a silent no-op and leave kora_inventory's own (fresh,
    -- post-restart) hook table without our hook.
    h.assertTrue(Core.consumables.isRegistered(), 'precondition: already registered from the prior onResourceStart')

    local hookCallCount = 0
    _G.exports.kora_inventory.RegisterHook = function(_, eventName, callback)
        h.assertEqual(eventName, 'usingItem')
        hookCallCount = hookCallCount + 1
        registeredHookCallback = callback
    end

    handle.fireEvent('onResourceStart', nil, 'kora_inventory')

    h.assertEqual(hookCallCount, 1, 'register() must re-run RegisterHook on a qbinventory restart, not be skipped by a permanent latch')
    h.assertTrue(Core.consumables.isRegistered())
    h.assertTrue(registeredHookCallback ~= nil)
end)

h.test('onResourceStart for an unrelated resource does not re-trigger anything', function()
    local before = registeredHookCallback
    handle.fireEvent('onResourceStart', nil, 'some_other_resource')
    h.assertTrue(registeredHookCallback == before)
end)

h.test('using an item with an effect table applies the status effect and metadata deltas', function()
    Core.metadata.setMetaData(1, 'hunger', 50)
    Core.metadata.setMetaData(1, 'thirst', 50)
    Core.metadata.setMetaData(1, 'stress', 50)

    local appliedName, appliedOpts
    handle.Kora.status.apply = function(target, name, opts)
        h.assertEqual(target, 1)
        appliedName, appliedOpts = name, opts
        return true
    end

    local allowed = registeredHookCallback({ itemName = 'weed_joint', inventoryId = 'player:1', inventoryType = 'player' }, 1)

    h.assertTrue(allowed, 'the hook must never deny an item use -- it is cosmetic/status-only')
    h.assertEqual(appliedName, 'weed_joint')
    h.assertEqual(appliedOpts.duration, 1000)
    h.assertEqual(Core.metadata.getMetaData(1, 'hunger'), 55)
    h.assertEqual(Core.metadata.getMetaData(1, 'thirst'), 45)
    h.assertEqual(Core.metadata.getMetaData(1, 'stress'), 40)
end)

h.test('using an item with no effect table is a harmless no-op', function()
    local statusApplyCalled = false
    handle.Kora.status.apply = function() statusApplyCalled = true; return true end

    local hunger = Core.metadata.getMetaData(1, 'hunger')
    local allowed = registeredHookCallback({ itemName = 'water_bottle', inventoryId = 'player:1', inventoryType = 'player' }, 1)

    h.assertTrue(allowed)
    h.assertFalse(statusApplyCalled, 'Kora.status.apply should never be called for an item with no effect table')
    h.assertEqual(Core.metadata.getMetaData(1, 'hunger'), hunger, 'hunger should be unchanged')
end)

h.test('an unknown item name is a harmless no-op, never an error', function()
    local ok = pcall(registeredHookCallback, { itemName = 'not_a_real_item', inventoryId = 'player:1', inventoryType = 'player' }, 1)
    h.assertTrue(ok)
end)

h.report('consumables')
