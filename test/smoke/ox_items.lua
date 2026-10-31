-- tools/ox_items generator against a tiny fixture registry.
local h = dofile('test/harness.lua')
local gen = dofile('tools/ox_items/generate.lua')
local fx = 'test/fixtures/ox_items'

local result = gen.build({ root = fx, oxDir = fx .. '/ox', scanDirs = { fx .. '/scan' } })
local items = assert(load(result.itemsLua, '=items.lua', 't', {}))()
local report, mapping = result.report, result.mapping

h.test('output loads as Lua with ox item shapes', function()
    h.assertEqual(items.water.label, 'Water')       -- kora registry beats upstream and stock
    h.assertEqual(items.water.weight, 500)
    h.assertEqual(items.water.stack, nil)
    h.assertEqual(items.phone.stack, false)          -- unique
    h.assertEqual(items.phone.close, false)          -- shouldClose = false
    h.assertEqual(items.phone.description, nil)      -- empty description omitted
    h.assertEqual(items.phone.client.image, 'smartphone.png')
    h.assertEqual(items.water.client, nil)           -- default image omitted
    h.assertEqual(items.sandwich.label, 'Sandwich')  -- filled from upstream via merge.lua
end)

h.test('weapons, ammo and cash are not emitted but are mapped', function()
    h.assertEqual(items.weapon_pistol, nil)
    h.assertEqual(items.pistol_ammo, nil)
    h.assertEqual(items.cash, nil)
    h.assertEqual(mapping.weapons.weapon_pistol, 'WEAPON_PISTOL')
    h.assertEqual(mapping.ammo.pistol_ammo, 'ammo-9')
    h.assertEqual(mapping.aliases.cash, 'money')
    h.assertEqual(report.unmappedWeapons[1], 'weapon_madeup')
end)

h.test('reserved ox money items are kept with stock semantics', function()
    h.assertEqual(items.money.label, 'Money')
    h.assertEqual(items.black_money.label, 'Dirty Money')
    local names = {}
    for _, c in ipairs(report.collisions) do names[c.name] = c.policy end
    h.assertEqual(names.water, 'kora wins')
    h.assertEqual(names.money, 'ox-semantics (reserved)')
end)

h.test('missing-item scan is heuristic, ignores comments and variables', function()
    h.assertTrue(report.scan.heuristic)
    local missing = {}
    for _, m in ipairs(report.scan.missing) do missing[m.name] = m end
    h.assertTrue(missing.ghost_item ~= nil)
    h.assertTrue(missing.burger ~= nil and missing.burger.stockItem == true)
    h.assertEqual(missing.commented_out, nil)
    h.assertEqual(missing.sandwich, nil)
    h.assertEqual(missing.weapon_pistol, nil)
    h.assertEqual(#report.scan.missing, 2)
end)

h.test('CLI writes items.lua, mapping and reports', function()
    local out = os.tmpname() .. '_oxitems'
    local rc = gen.main({ '--root', fx, '--ox-dir', fx .. '/ox', '--no-default-scan', '--scan', fx .. '/scan',
        '--out', out .. '/items.lua', '--strict' })
    h.assertEqual(rc, 2) -- strict + non-empty missing list
    for _, f in ipairs({ 'items.lua', 'mapping.json', 'report.json', 'report.md' }) do
        local fh = io.open(out .. '/' .. f, 'rb')
        h.assertTrue(fh ~= nil, f .. ' not written')
        if fh then fh:close() end
    end
    assert(dofile(out .. '/items.lua').water)
    os.execute("rm -rf '" .. out .. "'")
end)

h.test('real registry defines every item stock ox_inventory names in code', function()
    local real = {}
    for _, rec in ipairs((gen.loadRegistry('.'))) do real[rec.name] = rec end
    for _, name in ipairs(gen.ENGINE_REFERENCED) do h.assertTrue(real[name] ~= nil, name .. ' missing from registry') end
    h.assertEqual(real.identification.unique, true)
    h.assertEqual(real.bandage.label, 'Bandage') -- existing kora records are untouched
end)

h.report("ox_items")
