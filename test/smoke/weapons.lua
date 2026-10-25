-- Weapon/ammunition seed smoke test. This deliberately exercises the data
-- through Core.registry, the same path qbinventory uses at runtime, rather
-- than only inspecting the two source tables.

local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua')
mocks.install()

dofile('config.lua')
dofile('shared/items.lua')
dofile('shared/vehicles.lua')
dofile('shared/jobs.lua')
dofile('shared/gangs.lua')
dofile('shared/weapons.lua')
dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua')
dofile('modules/registry/server.lua')

h.test('weapon seed records are canonical, unique inventory definitions', function()
    local seen = {}
    h.assertTrue(#QBCoreSeed.weapons >= 100, 'catalogue unexpectedly incomplete')

    for _, definition in ipairs(QBCoreSeed.weapons) do
        h.assertTrue(type(definition.name) == 'string' and definition.name == definition.name:lower(), 'weapon name must be lowercase')
        h.assertTrue(definition.name:match('^weapon_[%w_]+$') ~= nil, 'weapon must use a native-style name')
        h.assertFalse(seen[definition.name], 'duplicate weapon seed: ' .. definition.name)
        seen[definition.name] = true
        h.assertEqual(definition.type, 'weapon', definition.name .. ' type')
        h.assertTrue(definition.unique, definition.name .. ' must be unique')
        local legacyUtility = {
            weapon_bread = true, weapon_briefcase = true, weapon_briefcase_02 = true,
            weapon_garbagebag = true, weapon_handcuffs = true, weapon_remotesniper = true,
        }
        if legacyUtility[definition.name] then
            h.assertEqual(definition.useable, false, definition.name .. ' pinned utility flag')
        else
            h.assertTrue(definition.useable, definition.name .. ' must be useable')
        end
        h.assertTrue(type(definition.weight) == 'number' and definition.weight >= 0, definition.name .. ' invalid weight')
        h.assertTrue(Core.registry.getShared('weapons', definition.name) == definition, definition.name .. ' missing from registry')
    end
end)

h.test('Ammu-Nation core families and their magazines resolve through registries', function()
    local families = {
        weapon_pistol = 'pistol_ammo',
        weapon_smg = 'smg_ammo',
        weapon_pumpshotgun = 'shotgun_ammo',
        weapon_carbinerifle = 'rifle_ammo',
        weapon_combatmg = 'mg_ammo',
        weapon_sniperrifle = 'snp_ammo',
    }

    for weaponName, ammoName in pairs(families) do
        local definition = Core.registry.getShared('weapons', weaponName)
        local ammo = Core.registry.getShared('items', ammoName)
        h.assertTrue(definition ~= nil, weaponName .. ' missing')
        h.assertEqual(definition.ammoItem, ammoName, weaponName .. ' ammo mapping')
        h.assertTrue(ammo ~= nil, ammoName .. ' missing')
        h.assertEqual(ammo.type, 'item', ammoName .. ' must be an item')
        h.assertFalse(ammo.unique, ammoName .. ' must stack')
        h.assertEqual(ammo.ammoType, definition.ammotype, ammoName .. ' native type mismatch')
    end
end)

h.test('core image URLs use exact reviewed GitHub artwork paths when available', function()
    local base = 'https://raw.githubusercontent.com/aifazi/items-images/main/'
    h.assertEqual(QBCoreSeed.itemImageBaseUrl, base)
    h.assertEqual(QBCoreSeed.imageUrl('weapon_pistol'), base .. 'weapons/pistol/weapon_pistol.png')
    h.assertEqual(QBCoreSeed.imageUrl('pistol_ammo'), base .. 'weapons/ammo/pistol_ammo.png')
    h.assertEqual(QBCoreSeed.imageUrl('cash'), nil, 'missing artwork must fall back rather than guess a URL')
    h.assertEqual(Core.registry.getShared('weapons', 'weapon_pistol').imageUrl, QBCoreSeed.imageUrl('weapon_pistol'))
    h.assertEqual(Core.registry.getShared('items', 'pistol_ammo').imageUrl, QBCoreSeed.imageUrl('pistol_ammo'))
end)

h.test('every mapped specialised ammunition item is valid qbinventory stock', function()
    for ammoType, itemName in pairs(QBCoreSeed.ammoItems) do
        local item = Core.registry.getShared('items', itemName)
        h.assertTrue(item ~= nil, 'mapped ammunition missing: ' .. ammoType)
        h.assertEqual(item.name, itemName)
        h.assertEqual(item.ammoType, ammoType)
        h.assertEqual(item.type, 'item')
        h.assertFalse(item.unique)
        h.assertTrue(type(item.rounds) == 'number' and item.rounds > 0)
    end
end)

h.test('representative vanilla weapons cover every supported family', function()
    for _, name in ipairs({
        'weapon_knife', 'weapon_pistol_mk2', 'weapon_tacticalsmg',
        'weapon_combatshotgun', 'weapon_battlerifle', 'weapon_combatmg_mk2',
        'weapon_heavysniper_mk2', 'weapon_railgunxm3', 'weapon_stickybomb',
        'weapon_fertilizercan',
    }) do
        h.assertTrue(Core.registry.getShared('weapons', name) ~= nil, name .. ' missing')
    end
end)

h.report('weapons')
