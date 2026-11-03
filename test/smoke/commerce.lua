-- Core.commerce smoke test -- sellItem/buyItem (K3): validated amounts, one
-- transaction per call (item and money legs together), proximity re-check and
-- the 'commerce' log.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua')
local handle = mocks.install()
local logged = {}
handle.Kora.logging = { event = function(category, src, data) logged[#logged + 1] = { category = category, src = src, data = data } end }

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
dofile('modules/logging/server.lua')

Core.player.login(1, 'CID1', CoreInternal.player.freshData('CID1', 'license:abc', 1, { firstname = 'A', lastname = 'B' }))
local player = CoreInternal.player.handle(1)

local function reset(cash, bread)
    player.PlayerData.items = {}
    Core.money.setMoney(1, 'cash', cash or 0)
    Core.money.setMoney(1, 'bank', 0)
    if bread and bread > 0 then Core.inventory.addItem(1, 'bread', bread) end
    for i = #logged, 1, -1 do logged[i] = nil end
end

local function sell(overrides)
    local spec = { item = 'bread', amount = 3, unitPrice = 7.5, reason = 'test sale' }
    for k, v in pairs(overrides or {}) do spec[k] = v end
    return Core.commerce.sellItem(1, spec)
end

local function buy(overrides)
    local spec = { item = 'water_bottle', amount = 2, unitPrice = 10, reason = 'test shop' }
    for k, v in pairs(overrides or {}) do spec[k] = v end
    return Core.commerce.buyItem(1, spec)
end

h.test('sellItem removes the items and pays the floored total in one call', function()
    reset(0, 5)
    local ok, result = sell()
    h.assertTrue(ok)
    h.assertEqual(result.amount, 3); h.assertEqual(result.total, 22, 'math.floor(7.5 * 3)')
    h.assertEqual(Core.money.getMoney(1, 'cash'), 22)
    h.assertEqual(Core.inventory.getItemCount(1, 'bread'), 2)
    h.assertEqual(#logged, 1)
    h.assertEqual(logged[1].category, 'commerce')
    h.assertEqual(logged[1].src, 1)
    h.assertEqual(logged[1].data.item, 'bread'); h.assertEqual(logged[1].data.amount, 3)
    h.assertEqual(logged[1].data.total, 22); h.assertEqual(logged[1].data.reason, 'test sale')
    h.assertEqual(logged[1].data.action, 'sell')
end)

h.test('selling more than the player holds pays nothing and keeps the items', function()
    reset(0, 2)
    local ok, err = sell()
    h.assertFalse(ok); h.assertTrue(type(err) == 'string')
    h.assertEqual(Core.money.getMoney(1, 'cash'), 0)
    h.assertEqual(Core.inventory.getItemCount(1, 'bread'), 2)
    h.assertEqual(#logged, 0, 'a refused sale is not logged as a sale')
end)

h.test('untrusted amounts are validated with toAmount before anything changes', function()
    local cases = {
        { 0 / 0, 'not_finite' }, { math.huge, 'not_finite' }, { 1.5, 'not_integer' }, { '3', 'not_number' },
        { 0, 'below_min' }, { -1, 'below_min' }, { 1001, 'above_max' }, { false, 'not_number' }, { {}, 'not_number' },
    }
    for _, case in ipairs(cases) do
        reset(1000, 5)
        local before = json.encode(player.PlayerData)
        local ok, reason = sell({ amount = case[1] })
        h.assertFalse(ok); h.assertEqual(reason, case[2], 'sell ' .. tostring(case[1]))
        ok, reason = buy({ amount = case[1] })
        h.assertFalse(ok); h.assertEqual(reason, case[2], 'buy ' .. tostring(case[1]))
        h.assertEqual(json.encode(player.PlayerData), before)
    end
    local ok, reason = Core.commerce.sellItem(1, { item = 'bread', unitPrice = 1, reason = 'no amount' })
    h.assertFalse(ok); h.assertEqual(reason, 'not_number', 'a missing amount')
    reset(0, 5)
    ok, reason = sell({ amount = 4, maxAmount = 3 })
    h.assertFalse(ok); h.assertEqual(reason, 'above_max', 'maxAmount caps one call')
end)

h.test('buyItem takes the total and grants the items with cloned metadata', function()
    reset(100)
    local metadata = { quality = 100 }
    local ok, result = buy({ metadata = metadata })
    h.assertTrue(ok)
    h.assertEqual(result.total, 20)
    h.assertEqual(Core.money.getMoney(1, 'cash'), 80)
    h.assertEqual(Core.inventory.getItemCount(1, 'water_bottle'), 2)
    local stack = Core.inventory.getItemByName(1, 'water_bottle')
    h.assertEqual(stack.info.quality, 100)
    h.assertFalse(stack.info == metadata, 'the caller table is not stored by reference')
    h.assertEqual(logged[1].data.action, 'buy')
end)

h.test('a buy the player cannot afford or carry changes nothing', function()
    reset(15)
    local before = json.encode(player.PlayerData)
    local ok, err = buy()
    h.assertFalse(ok); h.assertEqual(err, 'insufficient funds')
    h.assertEqual(json.encode(player.PlayerData), before)

    reset(100000)
    before = json.encode(player.PlayerData)
    ok, err = buy({ amount = 999, unitPrice = 1 })
    h.assertFalse(ok); h.assertEqual(err, 'over weight')
    h.assertEqual(json.encode(player.PlayerData), before, 'no money leaves when the items cannot be carried')
end)

h.test('account defaults to cash, accepts bank, and refuses anything else', function()
    reset(0, 5)
    h.assertTrue(sell({ account = 'bank', amount = 2, unitPrice = 10 }))
    h.assertEqual(Core.money.getMoney(1, 'bank'), 20)
    h.assertEqual(Core.money.getMoney(1, 'cash'), 0)
    local ok, reason = sell({ account = 'crypto' })
    h.assertFalse(ok); h.assertEqual(reason, 'invalid_account')
end)

h.test('a worthless sale still removes the item without a zero money leg', function()
    reset(0, 1)
    local ok, result = sell({ amount = 1, unitPrice = 0.4 })
    h.assertTrue(ok); h.assertEqual(result.total, 0)
    h.assertEqual(Core.inventory.getItemCount(1, 'bread'), 0)
    h.assertEqual(Core.money.getMoney(1, 'cash'), 0)
end)

h.test('at/maxDistance re-check the player position server-side', function()
    local original = _G.GetEntityCoords
    _G.GetEntityCoords = function() return { x = 10.0, y = 0.0, z = 0.0 } end
    reset(0, 5)
    local ok, reason = sell({ at = { x = 0.0, y = 0.0, z = 0.0 } })
    h.assertFalse(ok); h.assertEqual(reason, 'too_far', 'default maxDistance is 5.0')
    h.assertEqual(Core.inventory.getItemCount(1, 'bread'), 5)
    h.assertTrue(sell({ at = { x = 0.0, y = 0.0, z = 0.0 }, maxDistance = 12.0 }))
    h.assertTrue(sell({ amount = 1, at = { x = 8.0, y = 1.0, z = 0.0 } }))
    _G.GetEntityCoords = original
end)

h.test('unknown players are refused and malformed specs are programmer errors', function()
    local ok, reason = Core.commerce.sellItem(42, { item = 'bread', amount = 1, unitPrice = 1, reason = 'x' })
    h.assertFalse(ok); h.assertEqual(reason, 'no_player')
    h.assertFalse(pcall(sell, { reason = false }), 'reason is required')
    h.assertFalse(pcall(sell, { unitPrice = 0 / 0 }), 'unitPrice must be finite')
    h.assertFalse(pcall(sell, { unitPrice = -1 }))
    h.assertFalse(pcall(sell, { item = 7 }))
    h.assertFalse(pcall(Core.commerce.buyItem, 1, nil))
end)

h.test('Core.transaction rejects infinite amounts too', function()
    reset(0)
    local ok = Core.transaction(1, { items = { add = { { item = 'bread', amount = math.huge } } } })
    h.assertFalse(ok)
    ok = Core.transaction(1, { money = { add = { { account = 'cash', amount = math.huge } } } })
    h.assertFalse(ok)
    h.assertEqual(Core.money.getMoney(1, 'cash'), 0)
    h.assertTrue(Core.transaction(1, { items = { add = { { item = 'bread', amount = '2' } } } }), 'numeric strings still work')
end)

h.report('commerce')
