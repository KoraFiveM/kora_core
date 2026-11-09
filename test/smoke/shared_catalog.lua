local h = dofile('test/harness.lua')
dofile('test/mocks.lua').install()
function joaat(name)
    local hash = 0
    for i = 1, #name do
        hash = (hash + name:lower():byte(i)) & 0xffffffff
        hash = (hash + (hash << 10)) & 0xffffffff
        hash = hash ~ (hash >> 6)
    end
    hash = (hash + (hash << 3)) & 0xffffffff
    hash = hash ~ (hash >> 11)
    return (hash + (hash << 15)) & 0xffffffff
end

dofile('config.lua')
for _, name in ipairs({ 'items', 'weapons', 'vehicles', 'jobs', 'gangs', 'locations' }) do dofile('shared/' .. name .. '.lua') end
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua')
dofile('modules/registry/server.lua')
dofile('compat/shared/coreobject.lua')
local expected = dofile('test/fixtures/qbcore_catalog.lua')
local items, weapons = QBCore.Shared.Items, QBCore.Shared.Weapons

h.test('all pinned inventory names resolve to canonical native records', function()
    h.assertEqual(#expected.items, 323)
    for _, name in ipairs(expected.items) do
        local canonical = Core.registry.getShared('items', name) or Core.registry.getShared('weapons', name)
        h.assertTrue(canonical ~= nil, name .. ' missing')
        h.assertEqual(items[name], canonical, name .. ' is not canonical')
    end
    h.assertEqual(items.markedbills.weight, 1000)
    h.assertEqual(items.weed_brick.label, 'Weed Brick')
    h.assertTrue(items.coke_brick ~= nil and items.weed_whitewidow_seed ~= nil)
end)

h.test('native configured values and ammunition mappings keep precedence', function()
    local pistol = Core.registry.getShared('weapons', 'weapon_pistol')
    h.assertEqual(pistol.damageModifier, 0.8)
    h.assertEqual(pistol.useable, true)
    h.assertEqual(items.weapon_pistol, pistol)
    h.assertEqual(items.weapon_pistol.ammoItem, 'pistol_ammo')
    h.assertEqual(weapons[453432689].damageModifier, 0.8)
    h.assertEqual(weapons[453432689].useable, true)
    h.assertEqual(items.pistol_ammo.rounds, Core.registry.getShared('items', 'pistol_ammo').rounds)
end)

h.test('legacy Weapons uses actual numeric hashes and supplies every pinned damage cause', function()
    h.assertEqual(joaat('weapon_pistol'), 453432689)
    h.assertEqual(weapons[453432689].name, 'weapon_pistol')
    h.assertEqual(weapons.weapon_pistol, nil)
    for key in pairs(weapons) do h.assertEqual(type(key), 'number') end
    h.assertEqual(#expected.damage, 126)
    for _, name in ipairs(expected.damage) do
        local record = weapons[joaat(name)]
        h.assertTrue(record ~= nil, name .. ' missing damage record')
        h.assertTrue(type(record.damagereason) == 'string' and #record.damagereason > 0, name .. ' missing damage reason')
    end
    h.assertEqual(weapons[joaat('weapon_bleeding')].damagereason, 'Bled out')
end)

h.test('newer native weapons have a usable generic medical log reason', function()
    for _, record in ipairs(Core.registry.allShared('weapons')) do
        h.assertTrue(type(weapons[joaat(record.name)].damagereason) == 'string', record.name .. ' missing reason')
    end
    h.assertEqual(weapons[joaat('weapon_battlerifle')].damagereason, 'Died')
    h.assertEqual(weapons[joaat('weapon_battlerifle')].label, items.weapon_battlerifle.label)
end)

h.test('environmental causes cannot become grantable inventory definitions', function()
    for _, name in ipairs(QBCoreSeed.legacyDamageCauses) do
        h.assertEqual(items[name], nil, name .. ' leaked into Items')
        h.assertEqual(Core.registry.getShared('weapons', name), nil)
        h.assertEqual(Core.registry.getShared('items', name), nil)
        h.assertTrue(weapons[joaat(name)] ~= nil)
    end
end)

h.test('weapon add update removal refresh both captured views', function()
    local name = 'weapon_compat_fixture'
    local first = { name = name, type = 'weapon', label = 'First', damagereason = 'Fixture' }
    h.assertTrue(Core.registry.registerShared('weapons', name, first))
    h.assertEqual(items[name], first)
    h.assertEqual(weapons[joaat(name)].label, 'First')
    local second = { name = name, type = 'weapon', label = 'Second', damagereason = 'Changed' }
    h.assertTrue(Core.registry.registerShared('weapons', name, second))
    h.assertEqual(items[name], second)
    h.assertEqual(weapons[joaat(name)].damagereason, 'Changed')
    h.assertTrue(Core.registry.unregisterShared('weapons', name))
    h.assertEqual(items[name], nil)
    h.assertEqual(weapons[joaat(name)], nil)
    h.assertEqual(QBCore.Shared.Items, items)
    h.assertEqual(QBCore.Shared.Weapons, weapons)
end)

h.test('explicit item override wins and removing it reveals the current weapon', function()
    local name = 'weapon_pistol'
    local native = Core.registry.getShared('weapons', name)
    local override = { name = name, label = 'Item override', type = 'weapon' }
    h.assertTrue(Core.registry.registerShared('items', name, override))
    h.assertEqual(items[name], override)
    local replacement = Core.util.deepClone(native)
    replacement.label, replacement.damagereason = 'Native replacement', 'Custom reason'
    h.assertTrue(Core.registry.registerShared('weapons', name, replacement))
    h.assertEqual(items[name], override)
    h.assertEqual(weapons[453432689].label, 'Native replacement')
    h.assertEqual(weapons[453432689].damagereason, 'Custom reason')
    h.assertTrue(Core.registry.unregisterShared('items', name))
    h.assertEqual(items[name], replacement)
    h.assertTrue(Core.registry.unregisterShared('weapons', name))
    h.assertEqual(weapons[453432689].name, name, 'static damage metadata is independent of inventory stock')
    h.assertEqual(weapons[453432689].damageModifier, nil, 'removed native overrides must disappear')
    h.assertEqual(weapons[453432689].damagereason, QBCoreSeed.legacyWeaponMetadata[name].damagereason)
    h.assertEqual(items[name], nil)
    h.assertTrue(Core.registry.registerShared('weapons', name, native))
end)

h.test('editing a damage view cannot mutate seed metadata or native definitions', function()
    weapons[joaat('weapon_bleeding')].damagereason = 'Changed locally'
    weapons[453432689].label = 'Changed locally'
    h.assertEqual(QBCoreSeed.legacyWeaponMetadata.weapon_bleeding.damagereason, 'Bled out')
    h.assertTrue(Core.registry.getShared('weapons', 'weapon_pistol').label ~= 'Changed locally')
    TriggerEvent('qbcore:registry:synced')
    h.assertEqual(weapons[joaat('weapon_bleeding')].damagereason, 'Bled out')
    h.assertEqual(weapons[453432689].label, Core.registry.getShared('weapons', 'weapon_pistol').label)
end)
h.report('shared_catalog')
