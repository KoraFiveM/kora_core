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

local calls = {}
_G.exports = {
    kora_inventory = setmetatable({}, {
        __index = function(_, name)
            return function(_self, ...)
                calls[#calls + 1] = { name = name, args = { ... } }
                if name == 'addItem' then return true end
                if name == 'getItemCount' then return 42 end
                return true
            end
        end,
    }),
}

dofile('modules/inventory/gateway.lua')
dofile('compat/shared/coreobject.lua')
dofile('compat/server/qb-core.lua')

local data = CoreInternal.player.freshData('CID1', 'license:abc', 1, { firstname = 'A', lastname = 'B' })
Core.player.login(1, 'CID1', data)

h.test('delegates a public operation to a started kora_inventory without mutating kora_core directly', function()
    handle.resourceStates.kora_inventory = 'started'
    local ok = Core.inventory.addItem(1, 'water_bottle', 2, 7, { source = 'test' })
    h.assertTrue(ok)
    h.assertEqual(calls[#calls].name, 'addItem')
    h.assertEqual(calls[#calls].args[1], 1)
    h.assertEqual(calls[#calls].args[2], 'water_bottle')
    h.assertTrue(next(CoreInternal.player.handle(1).PlayerData.items) == nil, 'provider owns the operation')
end)

h.test('delegates read operations through the same provider boundary', function()
    handle.resourceStates.kora_inventory = 'started'
    h.assertEqual(Core.inventory.getItemCount(1, 'water_bottle'), 42)
    h.assertEqual(calls[#calls].name, 'getItemCount')
end)

h.test('legacy QBCore Player.Functions inventory calls use the same gateway', function()
    handle.resourceStates.kora_inventory = 'started'
    local Player = QBCore.Functions.GetPlayer(1)
    h.assertTrue(Player.Functions.AddItem('water_bottle', 1))
    h.assertEqual(calls[#calls].name, 'addItem')
    h.assertEqual(calls[#calls].args[1], 1)
end)

h.test('uses the documented legacy fallback only while the provider is absent', function()
    handle.resourceStates.kora_inventory = 'missing'
    Config.inventory.allowLegacyFallback = true
    local ok = Core.inventory.addItem(1, 'water_bottle', 1)
    h.assertTrue(ok)
    h.assertEqual(Core.inventory.getItemCount(1, 'water_bottle'), 1)
end)

h.test('returns a clear error instead of silently splitting authority when fallback is disabled', function()
    handle.resourceStates.kora_inventory = 'missing'
    Config.inventory.allowLegacyFallback = false
    local value, err = Core.inventory.addItem(1, 'water_bottle', 1)
    h.assertTrue(value == nil)
    h.assertTrue(type(err) == 'string' and err:find('kora_inventory is not started', 1, true) ~= nil)
end)

h.test('does not fall back when a started provider is incomplete', function()
    handle.resourceStates.kora_inventory = 'started'
    _G.exports.kora_inventory = {}
    local value, err = Core.inventory.addItem(1, 'water_bottle', 1)
    h.assertTrue(value == nil)
    h.assertTrue(type(err) == 'string' and err:find("missing required kora_core gateway export 'addItem'", 1, true) ~= nil)
end)

h.test('move delegates original arguments and provider returns before fallback validation', function()
    handle.resourceStates.kora_inventory = 'started'
    local arguments
    _G.exports.kora_inventory = { moveItem = function(_, ...)
        arguments = table.pack(...)
        return false, 'provider rejected', 'provider detail'
    end }
    local before = json.encode(CoreInternal.player.handle(1).PlayerData.items)
    local results = table.pack(Core.inventory.moveItem(1, '1', false, -1))
    h.assertEqual(arguments.n, 4)
    h.assertEqual(arguments[1], 1)
    h.assertEqual(arguments[2], '1')
    h.assertEqual(arguments[3], false)
    h.assertEqual(arguments[4], -1)
    h.assertEqual(results.n, 3)
    h.assertEqual(results[1], false)
    h.assertEqual(results[2], 'provider rejected')
    h.assertEqual(results[3], 'provider detail')
    Core.inventory.moveItem(1, 1, 2)
    h.assertEqual(arguments.n, 3, 'omitted amount stays omitted at the provider')
    h.assertEqual(json.encode(CoreInternal.player.handle(1).PlayerData.items), before)
end)

h.report('inventory_gateway')
