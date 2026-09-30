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

h.test('a bulk unique grant with too few slots rejects without adding anything', function()
    local previousSlots = Config.inventory.slots
    Config.inventory.slots = 2
    player.PlayerData.items = {}
    h.assertTrue(Core.inventory.addItem(1, 'water_bottle', 1))
    local existing = player.PlayerData.items[1]
    local can = Core.inventory.canCarry(1, 'phone', 2)
    local canString = Core.inventory.canCarry(1, 'phone', '2')
    local ok, err = Core.inventory.addItem(1, 'phone', 2)
    Config.inventory.slots = previousSlots
    h.assertFalse(can, 'capacity must account for every unique item')
    h.assertFalse(canString, 'numeric string amounts retain their existing coercion')
    h.assertFalse(ok)
    h.assertEqual(err, 'no free slot')
    h.assertEqual(player.PlayerData.items[2], nil, 'a failed bulk grant must not leave a partial grant')
    h.assertEqual(player.PlayerData.items[1], existing, 'existing items are preserved')
end)

h.test('an exact-fit unique grant succeeds while full inventories can still stack', function()
    local previousSlots = Config.inventory.slots
    Config.inventory.slots = 3
    player.PlayerData.items = {}
    Core.inventory.addItem(1, 'water_bottle', 1)
    local can = Core.inventory.canCarry(1, 'phone', 2)
    local ok = Core.inventory.addItem(1, 'phone', 2)
    local canStack = Core.inventory.canCarry(1, 'water_bottle', 2)
    local canUnique = Core.inventory.canCarry(1, 'phone', 1)
    Config.inventory.slots = previousSlots
    h.assertTrue(can)
    h.assertTrue(ok)
    h.assertEqual(player.PlayerData.items[2].name, 'phone')
    h.assertEqual(player.PlayerData.items[2].amount, 1)
    h.assertEqual(player.PlayerData.items[3].name, 'phone')
    h.assertEqual(player.PlayerData.items[3].amount, 1)
    h.assertTrue(canStack, 'stackable items do not need an additional slot')
    h.assertFalse(canUnique, 'a full inventory cannot accept another unique item')
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

-- The legacy (qbinventory-absent) useable path. This registers against the
-- resource registry, and the registry's contract is track(resource, id) --
-- calling it with the id missing indexed the registry with a nil key and threw
-- "table index is nil". Only reachable when qbinventory is stopped and
-- Config.inventory.allowLegacyFallback is on, so no boot log ever showed it.
h.test('createUseable registers against the owning resource without erroring', function()
    local fired = 0
    local ok, err = pcall(Core.inventory.createUseable, 'lockpick', function() fired = fired + 1 end)
    h.assertTrue(ok, 'createUseable did not error: ' .. tostring(err))

    -- A cross-resource handler arrives as a __call table, not a function.
    local callable = setmetatable({}, { __call = function(_, ...) fired = fired + 1 end })
    local ok2, err2 = pcall(Core.inventory.createUseable, 'radio', callable)
    h.assertTrue(ok2, 'createUseable accepts a cross-resource funcref: ' .. tostring(err2))
end)

h.report('inventory')
