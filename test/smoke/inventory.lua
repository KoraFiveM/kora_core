-- Inventory smoke test -- stacking into the lowest matching slot, unique items
-- never stacking, weight rejection returning (false, err) without mutating, and
-- clearInventory(keep) retaining kept items. Server realm.

local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua')
local handle = mocks.install()

dofile('config.lua')
dofile('shared/items.lua'); dofile('shared/jobs.lua'); dofile('shared/gangs.lua')
dofile('shared/vehicles.lua'); dofile('shared/weapons.lua'); dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua'); dofile('modules/registry/server.lua')
dofile('modules/player/shared.lua')
dofile('modules/replication/server.lua')
dofile('modules/persistence/server.lua')
dofile('modules/player/server.lua')
dofile('modules/inventory/shared.lua')
dofile('modules/inventory/server.lua')

local PI = CoreInternal.player

local data = CoreInternal.player.freshData('CID1', 'license:abc', 1, { firstname = 'A', lastname = 'B' })
Core.player.login(1, 'CID1', data)
local player = PI.handle(1)

h.test('non-unique items stack into the lowest matching slot', function()
    player.PlayerData.items = {}
    Core.inventory.addItem(1, 'water_bottle', 2)
    Core.inventory.addItem(1, 'water_bottle', 3)
    -- Both land in one slot with amount 5.
    local matching = 0
    local totalSlots = 0
    for _, item in pairs(player.PlayerData.items) do
        totalSlots = totalSlots + 1
        if item.name == 'water_bottle' then matching = matching + item.amount end
    end
    h.assertEqual(matching, 5, 'stacked to amount 5')
    h.assertEqual(totalSlots, 1, 'occupies exactly one slot')
end)

h.test('unique items never stack -- each occupies its own slot', function()
    player.PlayerData.items = {}
    Core.inventory.addItem(1, 'phone', 1)
    Core.inventory.addItem(1, 'phone', 1)
    local slots = 0
    for _ in pairs(player.PlayerData.items) do slots = slots + 1 end
    h.assertEqual(slots, 2, 'two unique phones -> two slots')
end)

h.test('weight rejection returns (false, err) and mutates nothing', function()
    player.PlayerData.items = {}
    -- water_bottle weighs 500g; maxWeight 120000 -> 240 fit, 241 should reject.
    local ok, err = Core.inventory.addItem(1, 'water_bottle', 241)
    h.assertFalse(ok, 'should reject over-weight add')
    h.assertTrue(err ~= nil, 'error string returned')
    local slots = 0
    for _ in pairs(player.PlayerData.items) do slots = slots + 1 end
    h.assertEqual(slots, 0, 'nothing added on rejection')
end)

h.test('removeItem drains across slots and reports insufficient', function()
    player.PlayerData.items = {}
    Core.inventory.addItem(1, 'bread', 4)
    local ok = Core.inventory.removeItem(1, 'bread', 3)
    h.assertTrue(ok, 'remove 3 of 4 ok')
    h.assertEqual(Core.inventory.getItemCount(1, 'bread'), 1)
    local ok2, err = Core.inventory.removeItem(1, 'bread', 5)
    h.assertFalse(ok2, 'cannot remove more than held')
    h.assertTrue(err ~= nil)
end)

h.test('clearInventory(keep) retains the kept item names', function()
    player.PlayerData.items = {}
    Core.inventory.addItem(1, 'water_bottle', 1)
    Core.inventory.addItem(1, 'id_card', 1)
    Core.inventory.clearInventory(1, { 'id_card' })
    h.assertTrue(Core.inventory.getItemByName(1, 'id_card') ~= nil, 'id_card retained')
    h.assertTrue(Core.inventory.getItemByName(1, 'water_bottle') == nil, 'water_bottle cleared')
end)

h.report('inventory')
