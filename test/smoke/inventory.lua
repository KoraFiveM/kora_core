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

h.test('explicit occupied slots preserve different items and unique instances', function()
    player.PlayerData.items = {}
    Core.inventory.addItem(1, 'phone', 1, 1, { serial = 'original' })
    local existing = player.PlayerData.items[1]
    local different = Core.inventory.addItem(1, 'water_bottle', 1, 1)
    local unique = Core.inventory.addItem(1, 'phone', 1, 1, { serial = 'replacement' })
    h.assertFalse(different, 'a grant cannot overwrite another item')
    h.assertFalse(unique, 'unique instances cannot replace or merge into an occupied slot')
    h.assertEqual(player.PlayerData.items[1], existing)
    h.assertEqual(existing.info.serial, 'original')
end)

h.test('explicit slots require whole numbers within the configured range', function()
    for _, slot in ipairs({ 0, -1, Config.inventory.slots + 1, 1.5, '1', true }) do
        player.PlayerData.items = {}
        local ok, err = Core.inventory.addItem(1, 'water_bottle', 1, slot)
        h.assertFalse(ok, 'invalid slot accepted: ' .. tostring(slot))
        h.assertEqual(err, 'invalid slot')
        h.assertEqual(next(player.PlayerData.items), nil, 'invalid slots must not add items')
    end
end)

h.test('compatible explicit stacks and automatic slot arguments retain their behavior', function()
    player.PlayerData.items = {}
    h.assertTrue(Core.inventory.addItem(1, 'water_bottle', 2, 3))
    h.assertTrue(Core.inventory.addItem(1, 'water_bottle', 3, 3))
    h.assertEqual(player.PlayerData.items[3].amount, 5)
    h.assertTrue(Core.inventory.addItem(1, 'bread', 1, false))
    h.assertEqual(player.PlayerData.items[1].name, 'bread')
    h.assertTrue(Core.inventory.addItem(1, 'phone', 1))
    h.assertEqual(player.PlayerData.items[2].name, 'phone')

    local previousMatch = Config.inventory.matchInfoOnStack
    Config.inventory.matchInfoOnStack = true
    player.PlayerData.items = {}
    Core.inventory.addItem(1, 'water_bottle', 1, 1, { batch = 'A' })
    local incompatible = Core.inventory.addItem(1, 'water_bottle', 1, 1, { batch = 'B' })
    local compatible = Core.inventory.addItem(1, 'water_bottle', 1, 1, { batch = 'A' })
    Config.inventory.matchInfoOnStack = previousMatch
    h.assertFalse(incompatible, 'the configured metadata rule also applies to explicit stacks')
    h.assertTrue(compatible)
    h.assertEqual(player.PlayerData.items[1].amount, 2)
    h.assertEqual(player.PlayerData.items[1].info.batch, 'A')
end)

h.test('bulk unique grants retain automatic placement even with a requested occupied slot', function()
    player.PlayerData.items = {}
    Core.inventory.addItem(1, 'water_bottle', 1, 1)
    h.assertTrue(Core.inventory.addItem(1, 'phone', 2, 1))
    h.assertEqual(player.PlayerData.items[1].name, 'water_bottle')
    h.assertEqual(player.PlayerData.items[2].name, 'phone')
    h.assertEqual(player.PlayerData.items[3].name, 'phone')
end)

h.test('weight rejection returns (false, err) and mutates nothing', function()
    player.PlayerData.items = {}
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

h.test('createUseable registers against the owning resource without erroring', function()
    local fired = 0
    local ok, err = pcall(Core.inventory.createUseable, 'lockpick', function() fired = fired + 1 end)
    h.assertTrue(ok, 'createUseable did not error: ' .. tostring(err))

    local callable = setmetatable({}, { __call = function(_, ...) fired = fired + 1 end })
    local ok2, err2 = pcall(Core.inventory.createUseable, 'radio', callable)
    h.assertTrue(ok2, 'createUseable accepts a cross-resource funcref: ' .. tostring(err2))
end)

h.test('move rejects invalid source and destination slots without mutation', function()
    local slots = table.pack(nil, false, true, '1', 0, -1, Config.inventory.slots + 1, 1.5, math.huge, -math.huge, 0 / 0)
    for index = 1, slots.n do
        for _, source in ipairs({ true, false }) do
            player.PlayerData.items = {}
            Core.inventory.addItem(1, 'water_bottle', 5, 1)
            player._dirty = {}
            local before = json.encode(player.PlayerData.items)
            local fromSlot, toSlot = 1, slots[index]
            if source then fromSlot, toSlot = slots[index], 2 end
            local ok, err = Core.inventory.moveItem(1, fromSlot, toSlot, 1)
            h.assertFalse(ok)
            h.assertEqual(err, 'invalid slot')
            h.assertEqual(json.encode(player.PlayerData.items), before)
            h.assertEqual(next(player._dirty), nil, 'rejected move never reaches the mutation funnel')
        end
    end
    player.PlayerData.items[Config.inventory.slots + 1] = player.PlayerData.items[1]
    h.assertFalse(Core.inventory.moveItem(1, Config.inventory.slots + 1, 2, 1), 'existing invalid source is also rejected')
end)

h.test('move rejects nonpositive and nonfinite quantities without mutation', function()
    for _, amount in ipairs({ -1, 0, 0.5, -0.5, '-1', '0', math.huge, -math.huge, 0 / 0, '1e309' }) do
        player.PlayerData.items = {}
        Core.inventory.addItem(1, 'water_bottle', 5, 1)
        player._dirty = {}
        local before = json.encode(player.PlayerData.items)
        local ok, err = Core.inventory.moveItem(1, 1, 2, amount)
        h.assertFalse(ok)
        h.assertTrue(type(err) == 'string')
        h.assertEqual(json.encode(player.PlayerData.items), before)
        h.assertEqual(next(player._dirty), nil, 'rejected move never reaches the mutation funnel')
    end
end)

h.test('move retains default amounts, coercion, flooring, clamping and valid destinations', function()
    for _, case in ipairs({
        { amount = nil, moved = 5 }, { amount = false, moved = 5 }, { amount = 'all', moved = 5 },
        { amount = '2', moved = 2 }, { amount = 2.9, moved = 2 }, { amount = 99, moved = 5 },
    }) do
        player.PlayerData.items = {}
        Core.inventory.addItem(1, 'water_bottle', 5, 1, { batch = 'A' })
        h.assertTrue(Core.inventory.moveItem(1, 1, Config.inventory.slots, case.amount))
        local dest = player.PlayerData.items[Config.inventory.slots]
        h.assertEqual(dest.amount, case.moved)
        h.assertEqual(dest.slot, Config.inventory.slots)
        h.assertEqual(dest.info.batch, 'A')
        h.assertEqual(Core.inventory.getItemCount(1, 'water_bottle'), 5)
    end
    player.PlayerData.items = {}
    Core.inventory.addItem(1, 'water_bottle', 5, 1)
    Core.inventory.addItem(1, 'water_bottle', 2, 2)
    h.assertTrue(Core.inventory.moveItem(1, 1, 2, 2))
    h.assertEqual(player.PlayerData.items[1].amount, 3)
    h.assertEqual(player.PlayerData.items[2].amount, 4)
    Core.inventory.addItem(1, 'bread', 1, 3)
    local before = json.encode(player.PlayerData.items)
    h.assertFalse(Core.inventory.moveItem(1, 1, 3, 1))
    h.assertEqual(json.encode(player.PlayerData.items), before, 'different destination item is preserved')
    local ok, err = Core.inventory.moveItem(1, 2, 4, 1)
    h.assertTrue(ok)
    h.assertEqual(err, nil)
    h.assertFalse(Core.inventory.moveItem(1, 5, 6, 1), 'empty source stays rejected')
end)

h.test('moving onto the same slot succeeds without changing items or dirty state', function()
    for _, amount in ipairs({ 'all', 2, 5, 99 }) do
        player.PlayerData.items = {}
        Core.inventory.addItem(1, 'water_bottle', 5, 1, { batch = 'same-slot' })
        Core.inventory.addItem(1, 'bread', 1, 2)
        player._dirty = {}
        local record = player.PlayerData.items[1]
        local before = json.encode(player.PlayerData.items)
        local ok, err = Core.inventory.moveItem(1, 1, 1, amount)
        h.assertTrue(ok)
        h.assertEqual(err, nil, 'existing success return is retained')
        h.assertEqual(json.encode(player.PlayerData.items), before, 'full and partial moves conserve the stack')
        h.assertEqual(player.PlayerData.items[1], record)
        h.assertEqual(next(player._dirty), nil, 'same-slot move never reaches the mutation funnel')
    end
    h.assertTrue(Core.inventory.moveItem(1, 1, 1), 'omitted quantity still succeeds')
    h.assertEqual(player.PlayerData.items[1].amount, 5)
    h.assertFalse(Core.inventory.moveItem(1, 1, 1, -1), 'same-slot move still validates quantity')
    h.assertFalse(Core.inventory.moveItem(1, 3, 3), 'same-slot move still requires an item')
end)

h.test('NaN and infinite amounts are refused by the fallback engine', function()
    Core.inventory.setItems(1, {})
    for _, bad in ipairs({ 0 / 0, math.huge }) do
        h.assertFalse(Core.inventory.addItem(1, 'water_bottle', bad))
        h.assertFalse(Core.inventory.removeItem(1, 'water_bottle', bad))
    end
    h.assertEqual(next(Core.player.getPlayerData(1, { 'items' }) or {}), nil)
end)

h.report('inventory')
