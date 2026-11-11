local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua')
mocks.install()
Kora.rewards = {}
dofile('../kora_lib/modules/rewards/shared.lua')

dofile('config.lua')
dofile('shared/items.lua'); dofile('shared/jobs.lua'); dofile('shared/gangs.lua')
dofile('shared/vehicles.lua'); dofile('shared/weapons.lua'); dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua'); dofile('modules/registry/server.lua')
dofile('modules/player/shared.lua')
dofile('modules/replication/server.lua'); dofile('modules/persistence/server.lua')
dofile('modules/player/server.lua'); dofile('modules/money/server.lua')
dofile('modules/inventory/shared.lua'); dofile('modules/inventory/server.lua')
dofile('modules/inventory/gateway.lua')
dofile('modules/transaction/server.lua')

local data = CoreInternal.player.freshData('CID1', 'license:abc', 1, { firstname = 'A', lastname = 'B' })
Core.player.login(1, 'CID1', data)
local player = CoreInternal.player.handle(1)

local function reset()
    player.PlayerData.items = {}
    Core.money.setMoney(1, 'bank', 1000)
end

local function transact(definition, random)
    local originalRandom = math.random
    math.random = random or function() error('unexpected random roll') end
    local ok, result, err = pcall(Core.transaction, 1, definition)
    math.random = originalRandom
    if not ok then error(result, 0) end
    return result, err
end

h.test('missing and empty random pools preserve ordinary transactions without rolling', function()
    for _, definition in ipairs({
        { money = { add = { { account = 'bank', amount = 100 } } }, items = { add = { { item = 'water_bottle', amount = 2 } } } },
        { money = { add = { { account = 'bank', amount = 100 } } }, items = { add = { { item = 'water_bottle', amount = 2 } } }, random = {} },
    }) do
        reset()
        h.assertTrue(transact(definition))
        h.assertEqual(Core.money.getMoney(1, 'bank'), 1100)
        h.assertEqual(Core.inventory.getItemCount(1, 'water_bottle'), 2)
    end
    local ok, err = transact(nil)
    h.assertFalse(ok)
    h.assertEqual(err, 'transaction must be a table')
    h.assertFalse(transact({ items = { add = { { item = 'bread' } } } }), 'ordinary additions still require an amount')
end)

h.test('unspecified chances split 100 equally without changing explicit percentages', function()
    local definition = { random = {
        { item = 'water_bottle' }, { item = 'bread' }, { item = 'cryptostick', chance = 1 },
    } }
    for _, scenario in ipairs({
        { rolls = { 0.5, 0.5, 0.0101 }, water = 1, bread = 1, crypto = 0 },
        { rolls = { 0.5001, 0.4999, 0.01 }, water = 0, bread = 1, crypto = 1 },
    }) do
        reset()
        local calls = 0
        h.assertTrue(transact(definition, function()
            calls = calls + 1
            return assert(scenario.rolls[calls], 'reward pool rolled more than once')
        end))
        h.assertEqual(calls, 3, 'each candidate is rolled once')
        h.assertEqual(Core.inventory.getItemCount(1, 'water_bottle'), scenario.water)
        h.assertEqual(Core.inventory.getItemCount(1, 'bread'), scenario.bread)
        h.assertEqual(Core.inventory.getItemCount(1, 'cryptostick'), scenario.crypto)
    end
end)

h.test('amount ranges, slots and metadata pass through without modifying reusable definitions', function()
    reset()
    local definition = {
        reason = 'test bonus',
        items = { add = { { item = 'bread', amount = 2 } } },
        random = {
            { item = 'water_bottle', chance = 100, amount = { min = 2, max = 4 }, slot = 7, info = { origin = 'taxi' } },
            { item = 'bread', chance = 100 },
        },
    }
    local before = json.encode(definition)
    local calls = 0
    local function random(minimum, maximum)
        calls = calls + 1
        if minimum then
            h.assertEqual(minimum, 2)
            h.assertEqual(maximum, 4)
            return maximum
        end
        return 0.99
    end
    h.assertTrue(transact(definition, random))
    h.assertEqual(calls, 3, 'two percentage rolls and one amount roll')
    h.assertEqual(player.PlayerData.items[7].amount, 4)
    h.assertEqual(player.PlayerData.items[7].info.origin, 'taxi')
    h.assertEqual(Core.inventory.getItemCount(1, 'bread'), 3)
    h.assertEqual(json.encode(definition), before)
    h.assertTrue(transact(definition, random))
    h.assertEqual(Core.inventory.getItemCount(1, 'water_bottle'), 8)
    h.assertEqual(Core.inventory.getItemCount(1, 'bread'), 6)
    h.assertEqual(json.encode(definition), before, 'reuse must not accumulate resolved bonus entries')
end)

h.test('all-miss rolls still complete ordinary payouts and removals without a fallback reward', function()
    reset()
    Core.inventory.addItem(1, 'bread', 1)
    local calls = 0
    h.assertTrue(transact({
        money = { remove = { { account = 'bank', amount = 20 } }, add = { { account = 'bank', amount = 100 } } },
        items = { remove = { { item = 'bread', amount = 1 } }, add = { { item = 'water_bottle', amount = 2 } } },
        random = { { item = 'bread', chance = 20 }, { item = 'cryptostick', chance = 1 } },
    }, function() calls = calls + 1; return 0.99 end))
    h.assertEqual(calls, 2, 'all misses must not trigger another pick')
    h.assertEqual(Core.money.getMoney(1, 'bank'), 1080)
    h.assertEqual(Core.inventory.getItemCount(1, 'bread'), 0)
    h.assertEqual(Core.inventory.getItemCount(1, 'water_bottle'), 2)
    h.assertEqual(Core.inventory.getItemCount(1, 'cryptostick'), 0)
end)

h.test('malformed pools and invalid quantities reject before changing state even if an item would miss', function()
    local invalidPools = {
        false, true, 'items', 1,
        { 'bread' }, { {} }, { { item = false } },
        { { item = 'bread' }, [3] = { item = 'water_bottle' } },
        { bread = { item = 'bread' } },
        { { item = 'bread', chance = 0 } }, { { item = 'bread', chance = 101 } },
        { { item = 'bread', chance = math.huge } },
        { { item = 'bread', amount = 0, chance = 1 } },
        { { item = 'bread', amount = 1.5, chance = 1 } },
        { { item = 'bread', amount = '2', chance = 1 } },
        { { item = 'bread', amount = math.huge, chance = 1 } },
        { { item = 'bread', amount = { min = 0, max = 2 }, chance = 1 } },
        { { item = 'bread', amount = { min = 2, max = 1 }, chance = 1 } },
        { { item = 'bread', amount = { min = 1.5, max = 2 }, chance = 1 } },
        { { item = 'bread', amount = { min = 1 }, chance = 1 } },
    }
    for _, pool in ipairs(invalidPools) do
        reset()
        Core.inventory.addItem(1, 'bread', 1)
        local before = json.encode(player.PlayerData)
        local ok, err = transact({
            money = { remove = { { account = 'bank', amount = 100 } } },
            items = { remove = { { item = 'bread', amount = 1 } }, add = { { item = 'water_bottle', amount = 1 } } },
            random = pool,
        }, function() return 0.99 end)
        h.assertFalse(ok)
        h.assertTrue(type(err) == 'string')
        h.assertEqual(json.encode(player.PlayerData), before)
    end
end)

h.test('ordinary and winning random quantities are combined for capacity validation', function()
    reset()
    local before = json.encode(player.PlayerData)
    local ok, err = transact({
        money = { remove = { { account = 'bank', amount = 100 } } },
        items = { add = { { item = 'water_bottle', amount = 240 } } },
        random = { { item = 'water_bottle', chance = 100 } },
    }, function() return 0 end)
    h.assertFalse(ok)
    h.assertEqual(err, 'over weight')
    h.assertEqual(json.encode(player.PlayerData), before, 'combined over-capacity grants reject before charging')
end)

h.test('losing bonuses do not reserve inventory capacity or block a payout', function()
    reset()
    h.assertTrue(transact({
        money = { add = { { account = 'bank', amount = 250 } } },
        random = { { item = 'phone', amount = Config.inventory.slots + 1, chance = 1 } },
    }, function() return 0.99 end))
    h.assertEqual(Core.money.getMoney(1, 'bank'), 1250)
    h.assertEqual(Core.inventory.getItemCount(1, 'phone'), 0)
end)

h.test('a later grant failure compensates ordinary additions, winning bonuses and removed money', function()
    reset()
    local before = json.encode(player.PlayerData)
    local calls = 0
    local ok, err = transact({
        money = { remove = { { account = 'bank', amount = 100 } }, add = { { account = 'bank', amount = 250 } } },
        items = { add = { { item = 'water_bottle', amount = 1 } } },
        random = {
            { item = 'water_bottle', amount = 238, chance = 100 },
            { item = 'bread', amount = 5, chance = 100 },
        },
    }, function() calls = calls + 1; return 0 end)
    h.assertFalse(ok)
    h.assertEqual(err, 'over weight')
    h.assertEqual(calls, 2, 'rollback must not reroll bonuses')
    h.assertEqual(json.encode(player.PlayerData), before)
end)

h.report('transaction')
