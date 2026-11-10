local h = dofile('test/harness.lua')
dofile('test/mocks.lua').install({ client = true })
dofile('config.lua')
for _, name in ipairs({ 'items', 'weapons', 'vehicles', 'jobs', 'gangs', 'locations' }) do dofile('shared/' .. name .. '.lua') end
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua')
dofile('modules/registry/client.lua')
dofile('compat/shared/coreobject.lua')
local items, weapons = QBCore.Shared.Items, QBCore.Shared.Weapons

h.test('captured Items and Weapons fill when the initial snapshot arrives', function()
    h.assertEqual(items.weapon_pistol, nil)
    h.assertEqual(weapons[joaat('weapon_pistol')].name, 'weapon_pistol')
    h.assertEqual(weapons[joaat('weapon_pistol')].weight, nil, 'before snapshot only static damage metadata exists')
    TriggerEvent('kora_core:registry:snapshotAll', {
        items = { records = KoraCoreSeed.items, epoch = 1 },
        weapons = { records = KoraCoreSeed.weapons, epoch = 1 },
    })
    h.assertEqual(items.weapon_pistol, Core.registry.getShared('weapons', 'weapon_pistol'))
    h.assertTrue(items.markedbills ~= nil)
    h.assertEqual(weapons[joaat('weapon_pistol')].name, 'weapon_pistol')
    h.assertTrue(type(weapons[joaat('weapon_pistol')].damagereason) == 'string')
    h.assertEqual(items, QBCore.Shared.Items)
    h.assertEqual(weapons, QBCore.Shared.Weapons)
end)

h.test('client deltas preserve item precedence and weapon fallback without stale values', function()
    local name = 'weapon_pistol'
    TriggerEvent('kora_core:registry:delta', 'items', 'add', name, { name = name, label = 'Override' })
    h.assertEqual(items[name].label, 'Override')
    TriggerEvent('kora_core:registry:delta', 'weapons', 'update', name, { name = name, label = 'Updated', damagereason = 'Custom' })
    h.assertEqual(items[name].label, 'Override')
    h.assertEqual(weapons[joaat(name)].label, 'Updated')
    h.assertEqual(weapons[joaat(name)].damagereason, 'Custom')
    TriggerEvent('kora_core:registry:delta', 'items', 'remove', name)
    h.assertEqual(items[name].label, 'Updated')
    TriggerEvent('kora_core:registry:delta', 'weapons', 'remove', name)
    h.assertEqual(items[name], nil)
    h.assertEqual(weapons[joaat(name)].name, name)
    h.assertEqual(weapons[joaat(name)].damagereason, KoraCoreSeed.legacyWeaponMetadata[name].damagereason)
end)

h.test('a replacement snapshot removes obsolete records from both captured maps', function()
    TriggerEvent('kora_core:registry:delta', 'weapons', 'add', 'weapon_custom_fixture', { name = 'weapon_custom_fixture', label = 'Custom' })
    h.assertTrue(weapons[joaat('weapon_custom_fixture')] ~= nil)
    TriggerEvent('kora_core:registry:snapshotAll', {
        items = { records = {}, epoch = 2 }, weapons = { records = {}, epoch = 2 },
    })
    h.assertEqual(next(items), nil)
    h.assertEqual(weapons[joaat('weapon_custom_fixture')], nil)
    h.assertEqual(weapons[joaat('weapon_knife')].name, 'weapon_knife')
    h.assertEqual(weapons[joaat('weapon_drowning')].damagereason, 'Died')
end)
h.report('shared_catalog_client')
