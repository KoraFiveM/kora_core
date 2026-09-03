-- qbinventory-backed physical-cash coverage using a tiny provider fake. The
-- normal money smoke tests continue to cover the default ledger path.
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

local function read(path)
    local file = assert(io.open(path, 'r'))
    local source = file:read('*a')
    file:close()
    return source
end

local money = read('modules/money/server.lua')
local player = read('modules/player/server.lua')
local invoker
GetInvokingResource = function() return invoker end
handle.resourceStates.qbinventory = 'started'

local physical = {}
exports.qbinventory = {
    physicalCashCanImport = function(_, src, account, amount) return account == 'cash' and amount >= 0 end,
    physicalCashImport = function(_, src, account, amount) physical[src] = (physical[src] or 0) + amount; return true end,
    physicalCashGet = function(_, src, account) return account == 'cash' and (physical[src] or 0) or nil end,
    physicalCashAdd = function(_, src, account, amount) physical[src] = (physical[src] or 0) + amount; return true end,
    physicalCashRemove = function(_, src, account, amount)
        if (physical[src] or 0) < amount then return false, 'insufficient funds' end
        physical[src] = physical[src] - amount
        return true
    end,
    physicalCashSet = function(_, src, account, amount) physical[src] = amount; return true end,
    physicalCashTransfer = function(_, from, to, account, amount)
        if (physical[from] or 0) < amount then return false, 'insufficient funds' end
        physical[from] = physical[from] - amount; physical[to] = (physical[to] or 0) + amount
        return true
    end,
}

local data = CoreInternal.player.freshData('CID1', 'license:abc', 1, { firstname = 'A', lastname = 'B' })
assert(Core.player.login(1, 'CID1', data))

h.test('only configured inventory provider can register physical cash', function()
    h.assertTrue(money:find("caller ~= Config.inventory.provider", 1, true) ~= nil)
    h.assertTrue(money:find("account ~= Config.money.cashType", 1, true) ~= nil)
end)
h.test('existing ledger cash migrates once before physical mode activates', function()
    invoker = 'qbinventory'
    h.assertTrue(Core.money.registerPhysicalCash('cash'))
    h.assertEqual(physical[1], Config.money.default.cash)
    h.assertEqual(Core.player.getPlayerData(1, { 'money', 'cash' }), 0)
    h.assertEqual(Core.money.getMoney(1, 'cash'), Config.money.default.cash)
end)
h.test('money APIs mutate only the physical balance', function()
    h.assertTrue(Core.money.addMoney(1, 'cash', 25, 'test'))
    h.assertEqual(Core.money.getMoney(1, 'cash'), Config.money.default.cash + 25)
    h.assertEqual(Core.player.getPlayerData(1, { 'money', 'cash' }), 0)
    h.assertTrue(Core.money.removeMoney(1, 'cash', 20, 'test'))
    h.assertEqual(Core.money.getMoney(1, 'cash'), Config.money.default.cash + 5)
    h.assertFalse(Core.money.addMoney(1, 'cash', 1.5, 'fractional'))
    h.assertFalse(Core.player.setPath(1, { 'money', 'cash' }, 999999))
    h.assertEqual(Core.money.getMoney(1, 'cash'), Config.money.default.cash + 5)
end)
h.test('newly adopted players migrate before their first usable state', function()
    local second = CoreInternal.player.freshData('CID2', 'license:def', 1, { firstname = 'B', lastname = 'B' })
    assert(Core.player.login(2, 'CID2', second))
    h.assertEqual(Core.player.getPlayerData(2, { 'money', 'cash' }), 0)
    h.assertEqual(Core.money.getMoney(2, 'cash'), Config.money.default.cash)
    h.assertTrue(Core.money.transferMoney(1, 2, 'cash', 5, 'test'))
    h.assertEqual(Core.money.getMoney(1, 'cash'), Config.money.default.cash)
    h.assertEqual(Core.money.getMoney(2, 'cash'), Config.money.default.cash + 5)
end)
h.test('provider loss fails closed', function()
    h.assertTrue(money:find("physical cash provider unavailable", 1, true) ~= nil)
end)
h.test('cash migration is preflighted and writes ledger only after import', function()
    h.assertTrue(money:find("physicalCashCanImport", 1, true) ~= nil)
    h.assertTrue(money:find("physicalCashImport", 1, true) ~= nil)
    h.assertTrue(money:find("PI._setPhysicalCashLedger", 1, true) ~= nil)
    h.assertTrue(player:find("_physicalCashToken == physicalCashWriteToken", 1, true) ~= nil)
end)
h.test('direct PlayerData cash writes are denied while physical', function()
    h.assertTrue(player:find("physical cash account is inventory-owned", 1, true) ~= nil)
end)
h.test('money APIs delegate add remove set and transfer', function()
    for _, name in ipairs({ 'physicalCashAdd', 'physicalCashRemove', 'physicalCashSet', 'physicalCashTransfer' }) do
        h.assertTrue(money:find(name, 1, true) ~= nil)
    end
end)

-- --- transaction tax over the physical-cash path ---
-- Same carve-out rules as the ledger path, but every leg goes through the
-- provider, so the tax leg and the net leg are separate provider calls.
local bank = { accounts = {}, ok = true }
exports['qb-banking'] = {
    GetAccount = function(_, name) return bank.accounts[name] end,
    CreateJobAccount = function(_, name, balance)
        bank.accounts[name] = { account_balance = balance or 0 }
        return 1
    end,
    AddMoney = function(_, name, amount)
        if not bank.ok or not bank.accounts[name] then return false end
        bank.accounts[name].account_balance = bank.accounts[name].account_balance + amount
        return 1
    end,
}
handle.resourceStates['qb-banking'] = 'started'
Config.money.tax.enabled = true
Config.money.tax.accounts.cash = true

-- Capture only the threads created from here on: handle.step() would also
-- resume persistence's flush loop, which never terminates under a Wait() that
-- does not yield (see modules/paycheck/server.lua's note).
local pendingThreads = {}
_G.CreateThread = function(fn) pendingThreads[#pendingThreads + 1] = fn end
local function settle()
    local queued = pendingThreads
    pendingThreads = {}
    for _, fn in ipairs(queued) do fn() end
end
local function govBalance() return (bank.accounts.government or {}).account_balance or 0 end

h.test('physical addMoney credits the net and banks the tax', function()
    physical[1] = 0
    h.assertTrue(Core.money.addMoney(1, 'cash', 100, 'paycheck'))
    h.assertEqual(Core.money.getMoney(1, 'cash'), 95, 'item stack holds amount - tax')
    settle()
    h.assertEqual(govBalance(), 5)
end)
h.test('physical removeMoney takes the full amount from the stack', function()
    physical[1] = 1000
    local before = govBalance()
    h.assertTrue(Core.money.removeMoney(1, 'cash', 100, 'shop'))
    h.assertEqual(Core.money.getMoney(1, 'cash'), 900)
    settle()
    h.assertEqual(govBalance(), before + 5)
end)
h.test('physical transferMoney costs the sender the gross and pays the net', function()
    physical[1] = 1000; physical[2] = 0
    local before = govBalance()
    h.assertTrue(Core.money.transferMoney(1, 2, 'cash', 200, 'transfer'))
    h.assertEqual(Core.money.getMoney(1, 'cash'), 800, 'sender pays the gross')
    h.assertEqual(Core.money.getMoney(2, 'cash'), 190, 'recipient receives the net')
    settle()
    h.assertEqual(govBalance(), before + 10)
end)
h.test('a physical transfer that fails mid-way returns the tax leg to the sender', function()
    -- 200 is affordable but the provider refuses the 190 move: the 10 already
    -- taken for tax must come back, leaving the sender exactly where they were.
    physical[1] = 200; physical[2] = 0
    local realTransfer = exports.qbinventory.physicalCashTransfer
    exports.qbinventory.physicalCashTransfer = function() return false, 'provider said no' end
    local ok, err = Core.money.transferMoney(1, 2, 'cash', 200, 'transfer')
    exports.qbinventory.physicalCashTransfer = realTransfer
    h.assertFalse(ok); h.assertEqual(err, 'provider said no')
    h.assertEqual(physical[1], 200, 'sender is fully restored')
    h.assertEqual(physical[2], 0)
end)
h.test('physical ignoreTax moves the whole amount', function()
    physical[1] = 1000; physical[2] = 0
    local before = govBalance()
    h.assertTrue(Core.money.transferMoney(1, 2, 'cash', 200, 'transfer', true))
    settle()
    h.assertEqual(physical[1], 800); h.assertEqual(physical[2], 200)
    h.assertEqual(govBalance(), before)
end)

h.report('physical_cash')
