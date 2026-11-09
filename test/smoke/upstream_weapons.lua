local h = dofile('test/harness.lua')
dofile('test/mocks.lua').install()

dofile('config.lua')
for _, f in ipairs({ 'shared/items.lua', 'shared/jobs.lua', 'shared/gangs.lua', 'shared/upstream/items.lua',
    'shared/upstream/jobs.lua', 'shared/upstream/gangs.lua', 'shared/upstream/merge.lua', 'shared/weapons.lua' }) do
    dofile(f)
end
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua')
dofile('modules/registry/server.lua')

h.test('no native weapon is shadowed by an upstream items record', function()
    for _, record in ipairs(Core.registry.allShared('weapons')) do
        h.assertEqual(Core.registry.getShared('items', record.name), nil, record.name .. ' shadowed in items')
    end
    h.assertEqual(QBCoreSeed.upstreamWeapons, nil, 'staging table must be cleared')
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

h.test('upstream fills only empty native fields and keeps upstream-only weapons', function()
    local pistol = Core.registry.getShared('weapons', 'weapon_pistol')
    h.assertEqual(pistol.label, 'Pistol')
    h.assertEqual(pistol.weight, 1100)
    h.assertEqual(type(pistol.description), 'string')
    h.assertTrue(Core.registry.getShared('weapons', 'weapon_bread') ~= nil)
    h.assertTrue(Core.registry.getShared('items', 'water_bottle') ~= nil, 'ordinary upstream items still merge')
end)
h.report('upstream_weapons')
