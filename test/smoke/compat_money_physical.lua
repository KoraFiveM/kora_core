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
dofile('modules/jobs/server.lua'); dofile('modules/metadata/server.lua')
dofile('modules/inventory/shared.lua'); dofile('modules/inventory/server.lua')
dofile('modules/inventory/gateway.lua')
dofile('modules/multichar/server.lua'); dofile('modules/permissions/server.lua')
dofile('modules/commands/server.lua'); dofile('modules/logging/server.lua')
dofile('compat/shared/coreobject.lua')
dofile('compat/server/qb-core.lua')
dofile('compat/server/qb-core-events.lua')

local invoker
GetInvokingResource = function() return invoker end
handle.resourceStates.kora_inventory = 'started'

local physical, reasons = {}, {}
exports.kora_inventory = {
    physicalCashCanImport = function() return true end,
    physicalCashImport = function(_, src, _, amount) physical[src] = (physical[src] or 0) + amount; return true end,
    physicalCashGet = function(_, src) return physical[src] or 0 end,
    physicalCashAdd = function(_, src, _, amount, reason) physical[src] = (physical[src] or 0) + amount; reasons[#reasons + 1] = reason; return true end,
    physicalCashRemove = function(_, src, _, amount, reason)
        if (physical[src] or 0) < amount then return false, 'insufficient funds' end
        physical[src] = physical[src] - amount; reasons[#reasons + 1] = reason
        return true
    end,
    physicalCashSet = function(_, src, _, amount, reason) physical[src] = amount; reasons[#reasons + 1] = reason; return true end,
}

local data = CoreInternal.player.freshData('MP1', 'license:mp1', 1, { firstname = 'A', lastname = 'B' })
assert(Core.player.login(1, 'MP1', data))
invoker = 'kora_inventory'
assert(Core.money.registerPhysicalCash('cash'))
invoker = nil
local p = QBCore.Functions.GetPlayer(1)
local start = Core.money.getMoney(1, 'cash')

h.test('SetPlayerData money translates a cash increase into an item add', function()
    local bank = p.PlayerData.money.bank
    h.assertTrue(p.Functions.SetPlayerData('money', { cash = p.PlayerData.money.cash + 100, bank = bank, crypto = 0 }))
    h.assertEqual(Core.money.getMoney(1, 'cash'), start + 100)
    h.assertEqual(Core.player.getPlayerData(1, { 'money', 'cash' }), 0, 'ledger stays zero')
    h.assertEqual(reasons[#reasons], 'qb-compat-setplayerdata')
end)

h.test('SetPlayerData money translates a cash decrease and changes bank together', function()
    local bank = p.PlayerData.money.bank
    h.assertTrue(p.Functions.SetPlayerData('money', { cash = p.PlayerData.money.cash - 40, bank = bank + 7, crypto = 0 }))
    h.assertEqual(Core.money.getMoney(1, 'cash'), start + 60)
    h.assertEqual(Core.money.getMoney(1, 'bank'), bank + 7)
end)

h.test('writing the table back unchanged does not touch cash', function()
    local before = Core.money.getMoney(1, 'cash')
    h.assertTrue(p.Functions.SetPlayerData('money', Core.util.deepClone(p.PlayerData.money)))
    h.assertEqual(Core.money.getMoney(1, 'cash'), before)
end)

h.test('overdraw refuses the whole write, including non-cash accounts', function()
    local cash, bank = Core.money.getMoney(1, 'cash'), Core.money.getMoney(1, 'bank')
    h.assertFalse(p.Functions.SetPlayerData('money', { cash = -1, bank = bank + 999, crypto = 0 }))
    h.assertEqual(Core.money.getMoney(1, 'cash'), cash)
    h.assertEqual(Core.money.getMoney(1, 'bank'), bank)
end)

h.test('invalid cash values are refused', function()
    local cash = Core.money.getMoney(1, 'cash')
    h.assertFalse(p.Functions.SetPlayerData('money', { cash = 'lots' }))
    h.assertFalse(p.Functions.SetPlayerData('money', { cash = 0 / 0 }))
    h.assertFalse(p.Functions.SetPlayerData('money', { cash = math.huge }))
    h.assertEqual(Core.money.getMoney(1, 'cash'), cash)
end)

h.test('UpdateClient money edit applies once and re-baselines the view', function()
    local before = Core.money.getMoney(1, 'cash')
    p.PlayerData.money.cash = p.PlayerData.money.cash + 25
    h.assertTrue(p.Functions.UpdateClient('money'))
    h.assertEqual(Core.money.getMoney(1, 'cash'), before + 25)
    h.assertTrue(p.Functions.UpdateClient('money'))
    h.assertEqual(Core.money.getMoney(1, 'cash'), before + 25, 'second reconcile must not re-apply')
end)

h.test('Functions.SetMoney cash sets the item-backed balance', function()
    h.assertTrue(p.Functions.SetMoney('cash', 500, 'unit'))
    h.assertEqual(Core.money.getMoney(1, 'cash'), 500)
    h.assertEqual(Core.player.getPlayerData(1, { 'money', 'cash' }), 0)
    h.assertFalse(p.Functions.SetMoney('cash', -1))
    h.assertEqual(Core.money.getMoney(1, 'cash'), 500)
    h.assertTrue(p.Functions.SetMoney('bank', 321))
    h.assertEqual(Core.money.getMoney(1, 'bank'), 321)
end)

local function deltaValue(path1, path2)
    local ev = handle.lastClient('kora_core:rep:delta')
    if not ev then return nil end
    for _, op in ipairs(ev.args[2]) do
        if op.p[1] == path1 and (path2 == nil and #op.p == 1 or op.p[2] == path2) then return op.v end
    end
end

h.test('mirror: PlayerData.money.cash reads the real item balance after an inventory cash change', function()
    physical[1] = 777
    handle.fireEvent('kora_core:server:inventoryChanged', 1, 1, { 'items', 1 }, {})
    h.assertEqual(QBCore.Functions.GetPlayer(1).PlayerData.money.cash, 777)
    h.assertEqual(p.Functions.GetPlayerData().money.cash, 777)
    h.assertEqual(Core.player.getPlayerData(1, { 'money', 'cash' }), 0, 'ledger stays zero')
end)

h.test('mirror: Core.money changes update the view and the client delta', function()
    handle.drainTimeouts()
    h.assertTrue(Core.money.addMoney(1, 'cash', 23, 'unit'))
    h.assertEqual(p.PlayerData.money.cash, 800)
    handle.drainTimeouts()
    h.assertEqual(deltaValue('money', 'cash'), 800, 'client mirror gets the real balance')
end)

h.test('mirror: client snapshot carries the real balance', function()
    local before = Core.player.getPlayerData(1, { 'money', 'cash' })
    Core.replication._sendSnapshot(CoreInternal.player.handle(1))
    local ev = handle.lastClient('kora_core:rep:snapshot')
    h.assertEqual(ev.args[2].money.cash, 800)
    h.assertEqual(Core.player.getPlayerData(1, { 'money', 'cash' }), before, 'snapshot must not alter the ledger')
end)

h.test('mirror: a ledger money write cannot clobber the mirrored client value', function()
    handle.drainTimeouts()
    h.assertTrue(p.Functions.SetPlayerData('money', { cash = 800, bank = 50, crypto = 0 }))
    handle.drainTimeouts()
    local whole = deltaValue('money')
    h.assertEqual(deltaValue('money', 'cash') or (whole and whole.cash), 800)
    h.assertEqual(p.PlayerData.money.cash, 800)
    h.assertEqual(p.PlayerData.money.bank, 50)
end)

h.test('write-back of {cash = x} applies the delta against the real balance', function()
    physical[1] = 500
    handle.fireEvent('kora_core:server:inventoryChanged', 1, 1, { 'items', 1 }, {})
    local read = p.Functions.GetMoney('cash')
    h.assertEqual(read, 500)
    h.assertTrue(p.Functions.SetPlayerData('money', { cash = read - 100, bank = 50, crypto = 0 }))
    h.assertEqual(Core.money.getMoney(1, 'cash'), 400, 'not 900')
    h.assertEqual(p.PlayerData.money.cash, 400)
    h.assertTrue(p.Functions.SetPlayerData('money', { cash = 450 }))
    h.assertEqual(Core.money.getMoney(1, 'cash'), 450)
end)

h.test('write-back delta is against the mirrored value the script saw, not the live balance (race)', function()
    physical[1] = 500
    handle.fireEvent('kora_core:server:inventoryChanged', 1, 1, { 'items', 1 }, {})
    local seen = p.Functions.GetPlayerData().money.cash
    h.assertEqual(seen, 500)
    physical[1] = 650
    h.assertTrue(p.Functions.SetPlayerData('money', { cash = seen + 10 }))
    h.assertEqual(Core.money.getMoney(1, 'cash'), 660, 'intended +10 applies on top of live 650')
    physical[1] = 5
    h.assertFalse(p.Functions.SetPlayerData('money', { cash = 660 - 100 }))
    h.assertEqual(Core.money.getMoney(1, 'cash'), 5)
    handle.fireEvent('kora_core:server:inventoryChanged', 1, 1, { 'items', 1 }, {})
end)

h.test('mirror: unregistering the provider hands the view back to the ledger', function()
    invoker = 'kora_inventory'
    assert(Core.money.unregisterPhysicalCash('cash'))
    invoker = nil
    h.assertEqual(p.PlayerData.money.cash, 0)
end)

h.report('compat_money_physical')
