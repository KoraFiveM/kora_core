local h = dofile('test/harness.lua')
dofile('test/mocks.lua').install()

dofile('config.lua')
for _, f in ipairs({ 'shared/items.lua', 'shared/weapons.lua' }) do
    dofile(f)
end
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua')
dofile('modules/registry/server.lua')

h.test('native seed weapons are separate from items', function()
    for _, record in ipairs(Core.registry.allShared('weapons')) do
        h.assertEqual(Core.registry.getShared('items', record.name), nil, record.name .. ' shadowed in items')
    end
end)

h.test('item-first lookups resolve the native weapon record', function()
    local function itemDef(name)
        return Core.registry.getShared('items', name) or Core.registry.getShared('weapons', name)
    end
    h.assertEqual(itemDef('weapon_grenade').weapontype, 'Throwable')
    h.assertEqual(itemDef('weapon_pistol').weapontype, 'Pistol')
    h.assertEqual(itemDef('weapon_pistol').damageModifier, 0.8)
    h.assertEqual(itemDef('weapon_pistol').ammoItem, 'pistol_ammo')
    h.assertEqual(itemDef('weapon_pistol').useable, true)
end)

h.test('native seeds include the previous stock descriptions and definitions', function()
    local pistol = Core.registry.getShared('weapons', 'weapon_pistol')
    h.assertEqual(pistol.label, 'Pistol')
    h.assertEqual(pistol.weight, 1100)
    h.assertEqual(pistol.description, 'A small firearm designed to be held in one hand')
    h.assertTrue(Core.registry.getShared('weapons', 'weapon_bread') ~= nil)
    h.assertTrue(Core.registry.getShared('items', 'water_bottle') ~= nil, 'water bottle missing from native items')
end)
h.report('upstream_weapons')
