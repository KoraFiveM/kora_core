-- Core.money smoke test -- add/remove/set with floors and validation.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('shared/items.lua'); dofile('shared/jobs.lua'); dofile('shared/gangs.lua')
dofile('shared/vehicles.lua'); dofile('shared/weapons.lua'); dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua'); dofile('modules/registry/server.lua')
dofile('modules/player/shared.lua')
dofile('modules/replication/server.lua'); dofile('modules/persistence/server.lua')
dofile('modules/player/server.lua'); dofile('modules/money/server.lua')

local data = CoreInternal.player.freshData('CID1', 'license:abc', 1, { firstname='A', lastname='B' })
Core.player.login(1, 'CID1', data)

h.test('addMoney increases balance', function()
    local before = Core.money.getMoney(1, 'cash')
    h.assertTrue(Core.money.addMoney(1, 'cash', 250))
    h.assertEqual(Core.money.getMoney(1, 'cash'), before + 250)
end)
h.test('removeMoney rejects when insufficient (cash floor 0)', function()
    Core.money.setMoney(1, 'cash', 100)
    local ok, err = Core.money.removeMoney(1, 'cash', 500)
    h.assertFalse(ok); h.assertTrue(err ~= nil)
    h.assertEqual(Core.money.getMoney(1, 'cash'), 100, 'balance unchanged on rejection')
end)
h.test('bank may go negative to the minus limit', function()
    Core.money.setMoney(1, 'bank', 0)
    local ok = Core.money.removeMoney(1, 'bank', 100)
    h.assertTrue(ok, 'bank allows negative')
    h.assertEqual(Core.money.getMoney(1, 'bank'), -100)
end)
h.test('invalid account rejected', function()
    local ok, err = Core.money.addMoney(1, 'doubloons', 5)
    h.assertFalse(ok); h.assertTrue(err ~= nil)
end)
h.test('negative amount rejected', function()
    local ok = Core.money.addMoney(1, 'cash', -5)
    h.assertFalse(ok)
end)
h.test('addMoney fires hud:client:OnMoneyChange(account, amount, isRemove=false)', function()
    Core.money.addMoney(1, 'cash', 50, 'test')
    local evt = handle.lastClient('hud:client:OnMoneyChange')
    h.assertTrue(evt ~= nil, 'hud:client:OnMoneyChange should have fired')
    h.assertEqual(evt.args[1], 'cash')
    h.assertEqual(evt.args[2], 50)
    h.assertEqual(evt.args[3], false, 'isRemove should be false on an add')
end)
h.test('removeMoney fires hud:client:OnMoneyChange(account, amount, isRemove=true)', function()
    Core.money.setMoney(1, 'cash', 100)
    Core.money.removeMoney(1, 'cash', 40, 'test')
    local evt = handle.lastClient('hud:client:OnMoneyChange')
    h.assertTrue(evt ~= nil, 'hud:client:OnMoneyChange should have fired')
    h.assertEqual(evt.args[1], 'cash')
    h.assertEqual(evt.args[2], 40)
    h.assertEqual(evt.args[3], true, 'isRemove should be true on a remove')
end)
h.test('qb-phone:client:RemoveBankMoney fires only on a bank removal', function()
    Core.money.setMoney(1, 'bank', 500)

    local function countSince(before)
        local n = 0
        for i = before + 1, #handle.clientEvents do
            if handle.clientEvents[i].name == 'qb-phone:client:RemoveBankMoney' then n = n + 1 end
        end
        return n
    end

    local before = #handle.clientEvents
    Core.money.removeMoney(1, 'cash', 10, 'test')
    h.assertEqual(countSince(before), 0, 'cash removal must not fire it')

    before = #handle.clientEvents
    Core.money.addMoney(1, 'bank', 10, 'test')
    h.assertEqual(countSince(before), 0, 'bank addition must not fire it')

    before = #handle.clientEvents
    Core.money.removeMoney(1, 'bank', 25, 'test')
    h.assertEqual(countSince(before), 1, 'bank removal should fire qb-phone:client:RemoveBankMoney exactly once')
    local evt = handle.lastClient('qb-phone:client:RemoveBankMoney')
    h.assertTrue(evt ~= nil, 'bank removal should fire qb-phone:client:RemoveBankMoney')
    h.assertEqual(evt.target, 1)
    h.assertEqual(evt.args[1], 25)
end)
-- F#171: NaN and +/-inf fail or pass every `<= 0` / floor comparison, so they
-- must be rejected explicitly before they can become a balance.
local NON_FINITE = { { 'NaN', 0 / 0 }, { '+inf', math.huge }, { '-inf', -math.huge }, { "'1e999' string", '1e999' } }

h.test('addMoney/removeMoney/setMoney reject NaN and infinity without touching the balance', function()
    for _, case in ipairs(NON_FINITE) do
        for _, account in ipairs({ 'cash', 'bank' }) do
            Core.money.setMoney(1, account, 100)
            local ok, err = Core.money.addMoney(1, account, case[2])
            h.assertFalse(ok, 'addMoney accepted ' .. case[1]); h.assertTrue(err ~= nil)
            ok = Core.money.removeMoney(1, account, case[2])
            h.assertFalse(ok, 'removeMoney accepted ' .. case[1])
            ok = Core.money.setMoney(1, account, case[2])
            h.assertFalse(ok, 'setMoney accepted ' .. case[1])
            h.assertEqual(Core.money.getMoney(1, account), 100, account .. ' balance changed by ' .. case[1])
        end
    end
end)

h.test('transferMoney rejects NaN and infinity without moving money', function()
    local other = CoreInternal.player.freshData('CID2', 'license:def', 2, { firstname = 'C', lastname = 'D' })
    Core.player.login(2, 'CID2', other)
    Core.money.setMoney(1, 'bank', 100)
    Core.money.setMoney(2, 'bank', 100)
    for _, case in ipairs(NON_FINITE) do
        local ok = Core.money.transferMoney(1, 2, 'bank', case[2])
        h.assertFalse(ok, 'transferMoney accepted ' .. case[1])
        h.assertEqual(Core.money.getMoney(1, 'bank'), 100, 'sender changed by ' .. case[1])
        h.assertEqual(Core.money.getMoney(2, 'bank'), 100, 'recipient changed by ' .. case[1])
    end
    h.assertTrue(Core.money.transferMoney(1, 2, 'bank', 40), 'a finite transfer still works')
    h.assertEqual(Core.money.getMoney(2, 'bank'), 140)
end)

h.report('money')
