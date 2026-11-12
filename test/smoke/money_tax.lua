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

local bank = { accounts = {}, deposits = {}, createCalls = 0, rejectDeposits = false }
exports['qb-banking'] = {
    GetAccount = function(_, name) return bank.accounts[name] end,
    CreateJobAccount = function(_, name, balance)
        bank.createCalls = bank.createCalls + 1
        bank.accounts[name] = { account_name = name, account_balance = balance or 0, account_type = 'job' }
        return 1
    end,
    AddMoney = function(_, name, amount, reason)
        if bank.rejectDeposits then return false end
        local account = bank.accounts[name]
        if not account then return false end
        account.account_balance = account.account_balance + amount
        bank.deposits[#bank.deposits + 1] = { name = name, amount = amount, reason = reason }
        return 1
    end,
}
handle.resourceStates['qb-banking'] = 'started'

local function govBalance() return (bank.accounts.government or {}).account_balance or 0 end

local pendingThreads = {}
_G.CreateThread = function(fn) pendingThreads[#pendingThreads + 1] = fn end
local function settle()
    local queued = pendingThreads
    pendingThreads = {}
    for _, fn in ipairs(queued) do fn() end
end

local data = CoreInternal.player.freshData('CID1', 'license:abc', 1, { firstname = 'A', lastname = 'B' })
assert(Core.player.login(1, 'CID1', data))
local data2 = CoreInternal.player.freshData('CID2', 'license:def', 1, { firstname = 'C', lastname = 'D' })
assert(Core.player.login(2, 'CID2', data2))

h.test('tax is off by default -- nothing is withheld and nothing is banked', function()
    Core.money.setMoney(1, 'bank', 1000)
    h.assertEqual(Core.money.getTaxRate('bank', 'add'), 0)
    h.assertTrue(Core.money.addMoney(1, 'bank', 100, 'test'))
    settle()
    h.assertEqual(Core.money.getMoney(1, 'bank'), 1100, 'full amount reaches the player')
    h.assertEqual(#bank.deposits, 0, 'no deposit attempted')
end)

Config.money.tax.enabled = true

h.test('getTaxRate / calculateTax reflect config and floor the tax', function()
    h.assertEqual(Core.money.getTaxRate('bank', 'add'), 0.05)
    h.assertEqual(Core.money.getTaxRate('crypto', 'add'), 0, 'crypto is not in tax.accounts')
    h.assertEqual(Core.money.getTaxRate('bank', 'set'), 0, 'set is never a taxable action')
    h.assertEqual(Core.money.calculateTax(100, 'bank', 'add'), 5)
    h.assertEqual(Core.money.calculateTax(19, 'bank', 'add'), 0, '19 * 0.05 floors to 0')
    h.assertEqual(Core.money.calculateTax(100, 'crypto', 'add'), 0)
    h.assertEqual(Core.money.getTaxAccount(), 'government')
end)

h.test('getTransactionTax follows actual provider availability without changing configured estimates', function()
    h.assertEqual(Core.money.getTransactionTax(100, 'bank', 'add'), 5)
    h.assertEqual(Core.money.getTransactionTax(19, 'bank', 'add'), 0)
    h.assertEqual(Core.money.getTransactionTax(100, 'crypto', 'add'), 0)
    handle.resourceStates['qb-banking'] = 'stopped'
    h.assertEqual(Core.money.getTransactionTax(100, 'bank', 'add'), 0)
    h.assertEqual(Core.money.calculateTax(100, 'bank', 'add'), 5)
    handle.resourceStates['qb-banking'] = 'started'
    h.assertEqual(Core.money.getTransactionTax(100, 'bank', 'add'), 5)
end)

h.test('addMoney withholds the tax and banks it', function()
    Core.money.setMoney(1, 'bank', 0)
    h.assertTrue(Core.money.addMoney(1, 'bank', 100, 'paycheck'))
    h.assertEqual(Core.money.getMoney(1, 'bank'), 95, 'player receives amount - tax')
    settle()
    h.assertEqual(govBalance(), 5)
    h.assertEqual(bank.deposits[#bank.deposits].reason, 'paycheck')
end)

h.test('the government account is created once, on first collection', function()
    h.assertEqual(bank.createCalls, 1)
    Core.money.addMoney(1, 'bank', 100, 'paycheck'); settle()
    h.assertEqual(bank.createCalls, 1, 'existing account is not re-created')
end)

h.test('the money-change event reports the net the player actually received', function()
    Core.money.setMoney(1, 'bank', 0)
    Core.money.addMoney(1, 'bank', 200, 'test'); settle()
    local evt = handle.lastClient('QBCore:Client:OnMoneyChange')
    h.assertEqual(evt.args[1], 'bank')
    h.assertEqual(evt.args[2], 190, 'event carries the net, not the gross')
end)

h.test('ignoreTax exempts a single call', function()
    Core.money.setMoney(1, 'bank', 0)
    local before = govBalance()
    h.assertTrue(Core.money.addMoney(1, 'bank', 100, 'tax free', true))
    settle()
    h.assertEqual(Core.money.getMoney(1, 'bank'), 100, 'full amount reaches the player')
    h.assertEqual(govBalance(), before, 'nothing banked')
end)

h.test('removeMoney costs the player the full amount and banks the slice', function()
    Core.money.setMoney(1, 'bank', 1000)
    local before = govBalance()
    h.assertTrue(Core.money.removeMoney(1, 'bank', 100, 'shop'))
    h.assertEqual(Core.money.getMoney(1, 'bank'), 900, 'player pays exactly what was asked')
    settle()
    h.assertEqual(govBalance(), before + 5)
end)

h.test('removeMoney with ignoreTax banks nothing', function()
    Core.money.setMoney(1, 'bank', 1000)
    local before = govBalance()
    h.assertTrue(Core.money.removeMoney(1, 'bank', 100, 'shop', true))
    settle()
    h.assertEqual(Core.money.getMoney(1, 'bank'), 900)
    h.assertEqual(govBalance(), before)
end)

h.test('setMoney is never taxed', function()
    local before = govBalance()
    h.assertTrue(Core.money.setMoney(1, 'bank', 500))
    settle()
    h.assertEqual(Core.money.getMoney(1, 'bank'), 500)
    h.assertEqual(govBalance(), before)
end)

h.test('a non-taxable account passes through untouched', function()
    Core.money.setMoney(1, 'crypto', 0)
    local before = govBalance()
    h.assertTrue(Core.money.addMoney(1, 'crypto', 100, 'test'))
    settle()
    h.assertEqual(Core.money.getMoney(1, 'crypto'), 100)
    h.assertEqual(govBalance(), before)
end)

h.test('an untaxed action passes through untouched', function()
    Config.money.tax.actions.remove = false
    Core.money.setMoney(1, 'bank', 1000)
    local before = govBalance()
    h.assertTrue(Core.money.removeMoney(1, 'bank', 100, 'shop'))
    settle()
    h.assertEqual(Core.money.getMoney(1, 'bank'), 900)
    h.assertEqual(govBalance(), before, 'remove is excluded, so nothing is banked')
    Config.money.tax.actions.remove = true
end)

h.test('transferMoney: sender pays gross, recipient receives net, government takes the slice', function()
    Core.money.setMoney(1, 'bank', 1000)
    Core.money.setMoney(2, 'bank', 0)
    local before = govBalance()
    h.assertTrue(Core.money.transferMoney(1, 2, 'bank', 200, 'transfer'))
    h.assertEqual(Core.money.getMoney(1, 'bank'), 800, 'sender pays the gross')
    h.assertEqual(Core.money.getMoney(2, 'bank'), 190, 'recipient receives the net')
    settle()
    h.assertEqual(govBalance(), before + 10)
end)

h.test('transferMoney with ignoreTax moves the full amount', function()
    Core.money.setMoney(1, 'bank', 1000)
    Core.money.setMoney(2, 'bank', 0)
    local before = govBalance()
    h.assertTrue(Core.money.transferMoney(1, 2, 'bank', 200, 'transfer', true))
    settle()
    h.assertEqual(Core.money.getMoney(1, 'bank'), 800)
    h.assertEqual(Core.money.getMoney(2, 'bank'), 200)
    h.assertEqual(govBalance(), before)
end)

h.test('a banking outage fails OPEN -- the transaction is untaxed, not blocked', function()
    handle.resourceStates['qb-banking'] = 'stopped'
    Core.money.setMoney(1, 'bank', 0)
    local before = govBalance()
    h.assertTrue(Core.money.addMoney(1, 'bank', 100, 'paycheck'))
    settle()
    h.assertEqual(Core.money.getMoney(1, 'bank'), 100, 'player keeps the whole amount')
    h.assertEqual(govBalance(), before, 'nothing banked')
    handle.resourceStates['qb-banking'] = 'started'
end)

h.test('a rejected deposit refunds the withheld tax to the player', function()
    Core.money.setMoney(1, 'bank', 0)
    bank.rejectDeposits = true
    local before = govBalance()
    h.assertTrue(Core.money.addMoney(1, 'bank', 100, 'paycheck'))
    h.assertEqual(Core.money.getMoney(1, 'bank'), 95, 'net is applied before the deposit is attempted')
    settle()
    h.assertEqual(govBalance(), before, 'the deposit did not land')
    h.assertEqual(Core.money.getMoney(1, 'bank'), 100, 'the withheld tax is refunded, so no money is lost')
    bank.rejectDeposits = false
end)

h.test('a rejected transfer deposit refunds the sender', function()
    Core.money.setMoney(1, 'bank', 1000)
    Core.money.setMoney(2, 'bank', 0)
    bank.rejectDeposits = true
    h.assertTrue(Core.money.transferMoney(1, 2, 'bank', 200, 'transfer'))
    settle()
    h.assertEqual(Core.money.getMoney(1, 'bank'), 810, 'sender is made whole for the unbanked tax')
    h.assertEqual(Core.money.getMoney(2, 'bank'), 190, 'recipient keeps the net they were paid')
    bank.rejectDeposits = false
end)

h.test('collectTax can be called directly for an off-path levy', function()
    local before = govBalance()
    h.assertTrue(Core.money.collectTax(250, 'fine'))
    h.assertEqual(govBalance(), before + 250)
    h.assertEqual(bank.deposits[#bank.deposits].reason, 'fine')
end)

h.test('collectTax rejects a non-positive amount and a stopped provider', function()
    h.assertFalse(Core.money.collectTax(0, 'nope'))
    handle.resourceStates['qb-banking'] = 'stopped'
    local ok, err = Core.money.collectTax(10, 'nope')
    h.assertFalse(ok); h.assertTrue(err ~= nil)
    handle.resourceStates['qb-banking'] = 'started'
end)

h.test('a refund for a deposit that fails after a character switch goes to the taxed character', function()
    Core.money.setMoney(1, 'bank', 0)
    bank.rejectDeposits = true
    h.assertTrue(Core.money.addMoney(1, 'bank', 100, 'paycheck'))
    Core.player.dropPlayer(1)
    local data3 = CoreInternal.player.freshData('CID3', 'license:abc', 2, { firstname = 'E', lastname = 'F' })
    assert(Core.player.login(1, 'CID3', data3))
    Core.money.setMoney(1, 'bank', 0)
    local offline = {}
    handle.Kora.sql.update = function(sql, params) offline[#offline + 1] = params; return 1 end
    settle()
    h.assertEqual(Core.money.getMoney(1, 'bank'), 0, 'the new character on the same source is not credited')
    h.assertEqual(#offline, 1, 'the offline character is credited instead')
    h.assertEqual(offline[1][3], 5)
    h.assertEqual(offline[1][4], 'CID1')
    handle.Kora.sql.update = nil
    bank.rejectDeposits = false
end)

h.test('NaN and infinite amounts never reach a balance', function()
    Core.money.setMoney(1, 'bank', 100)
    for _, bad in ipairs({ 0 / 0, math.huge, -math.huge }) do
        h.assertFalse(Core.money.addMoney(1, 'bank', bad, 'x'))
        h.assertFalse(Core.money.removeMoney(1, 'bank', bad, 'x'))
        h.assertFalse(Core.money.setMoney(1, 'bank', bad, 'x'))
        h.assertFalse(Core.money.transferMoney(1, 2, 'bank', bad, 'x'))
        h.assertFalse(Core.money.collectTax(bad, 'x'))
        h.assertEqual(Core.money.calculateTax(bad, 'bank', 'add'), 0)
    end
    settle()
    h.assertEqual(Core.money.getMoney(1, 'bank'), 100)
end)

h.report('money_tax')
