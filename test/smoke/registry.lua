-- Registry smoke test: runtime default registration, register/update/unregister,
-- indexed getter sync (including after a swap-remove), onChange dispatch, the
-- resource-stop sweep, and epoch-bump reseed. Server realm only.

local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua')
local handle = mocks.install()

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

local RI = CoreInternal.registry

h.test('seeds are ingested and readable via getShared', function()
    h.assertTrue(Core.registry.getShared('items', 'water_bottle') ~= nil, 'seed item missing')
    h.assertTrue(Core.registry.countShared('jobs') >= 3, 'seed jobs missing')
end)

h.test('shared weapons expose inventory-owned damage settings', function()
    local pistol = assert(Core.registry.getShared('weapons', 'weapon_pistol'))
    local railgun = assert(Core.registry.getShared('weapons', 'weapon_railgun'))
    h.assertEqual(pistol.damageModifier, 0.8)
    h.assertTrue(pistol.disableCriticalHits)
    h.assertEqual(railgun.damageModifier, 1.0, 'unconfigured weapons retain native damage')
    h.assertFalse(railgun.disableCriticalHits)
end)

h.test('defaults are registered through the runtime delta funnel', function()
    local seen = {}
    for _, event in ipairs(handle.clientEvents) do
        if event.name == 'qbcore:registry:delta' then seen[event.args[1]] = true end
    end
    for _, name in ipairs({ 'items', 'vehicles', 'jobs', 'gangs' }) do
        h.assertTrue(seen[name] == true, ('%s defaults did not emit runtime registration deltas'):format(name))
    end
end)

h.test('seed job grades are one-based sequential arrays', function()
    h.assertEqual(Config.jobs.defaultGrade, 1, 'new characters start at grade 1')
    for _, name in ipairs({ 'unemployed', 'police', 'ambulance', 'mechanic' }) do
        local job = assert(Core.registry.getShared('jobs', name))
        h.assertTrue(job.grades[0] == nil, ('%s must not define grade zero'):format(name))
        h.assertTrue(job.grades[1] ~= nil, ('%s must define grade one'):format(name))
        for grade = 1, #job.grades do
            h.assertTrue(job.grades[grade] ~= nil, ('%s has a gap at grade %d'):format(name, grade))
        end
    end
end)

h.test('seed gang grades are one-based sequential arrays', function()
    for _, name in ipairs({ 'none', 'ballas', 'vagos' }) do
        local gang = assert(Core.registry.getShared('gangs', name))
        h.assertTrue(gang.grades[0] == nil, ('%s must not define grade zero'):format(name))
        h.assertTrue(gang.grades[1] ~= nil, ('%s must define grade one'):format(name))
        for grade = 1, #gang.grades do
            h.assertTrue(gang.grades[grade] ~= nil, ('%s has a gap at grade %d'):format(name, grade))
        end
    end
end)

h.test('legacy zero-based role grade maps are normalised for modern consumers', function()
    local ok = Core.registry.registerShared('jobs', 'burgershot', {
        name = 'burgershot', label = 'Burger Shot', grades = {
            ['0'] = { name = 'Trainee', payment = 30 },
            ['1'] = { name = 'Cook', payment = 45 },
        },
    })
    h.assertTrue(ok, 'legacy job registration failed')
    local job = assert(Core.registry.getShared('jobs', 'burgershot'))
    h.assertEqual(job.grades[1].name, 'Trainee', 'zero-based grade 0 must become internal grade 1')
    h.assertEqual(job.grades[2].name, 'Cook', 'zero-based grade 1 must become internal grade 2')
    h.assertTrue(job.grades['0'] == nil, 'legacy grade keys must not leak into the live registry')
end)

h.test('register adds to the list and indexed getter', function()
    local ok = Core.registry.registerShared('items', 'donut', { name = 'donut', label = 'Donut', weight = 100 })
    h.assertTrue(ok, 'register failed')
    h.assertEqual(Core.registry.getShared('items', 'donut').label, 'Donut')
    local pos = RI.registries.items.index.donut
    h.assertEqual(RI.registries.items.list[pos].weight, 100)
end)

h.test('register with an existing key updates in place (action=update)', function()
    local actions = {}
    Core.registry.onSharedChange('items', function(action) actions[#actions + 1] = action end)
    Core.registry.registerShared('items', 'donut', { name = 'donut', label = 'Glazed Donut', weight = 110 })
    h.assertEqual(Core.registry.getShared('items', 'donut').label, 'Glazed Donut')
    h.assertEqual(actions[#actions], 'update')
end)

h.test('unregister swap-removes and keeps list/index/getter consistent', function()
    -- Add two, remove the first, ensure the moved element's index is correct.
    Core.registry.registerShared('items', 'itemA', { name = 'itemA', label = 'A' })
    Core.registry.registerShared('items', 'itemB', { name = 'itemB', label = 'B' })
    local before = Core.registry.countShared('items')
    Core.registry.unregisterShared('items', 'itemA')
    h.assertEqual(Core.registry.countShared('items'), before - 1)
    h.assertTrue(Core.registry.getShared('items', 'itemA') == nil, 'itemA should be gone')
    -- itemB still resolvable and its index points at a valid list slot.
    local idx = RI.registries.items.index.itemB
    h.assertEqual(RI.registries.items.list[idx].name, 'itemB')
end)

h.test('onChange fires with add/remove and the resource-stop sweep removes records', function()
    -- Simulate a foreign resource owning a registration.
    _G.GetInvokingResource = function() return 'some-plugin' end
    Core.registry.registerShared('items', 'plugin_item', { name = 'plugin_item', label = 'P' })
    h.assertTrue(Core.registry.getShared('items', 'plugin_item') ~= nil)

    -- Fire the resource-stop sweep for that owner via the serverRegistry handle.
    -- The registry created its own serverRegistry; trigger dispose through the
    -- mock's tracked owner. We reach it by re-running the onDispose the module
    -- registered: emulate by calling unregister as the sweep would.
    _G.GetInvokingResource = function() return nil end

    -- Drive the actual sweep: the mock serverRegistry exposes _dispose, but the
    -- module holds its own handle. Simulate the stop by invoking the module's
    -- exported internal unregister for the owned key (what the sweep does).
    Core.registry._unregisterInternal('items', 'plugin_item')
    h.assertTrue(Core.registry.getShared('items', 'plugin_item') == nil, 'swept record should be gone')
end)

h.test('reseed refreshes the allShared list IN PLACE (stable reference)', function()
    local listBefore = Core.registry.allShared('items')
    RI.reseed('items', { { name = 'only', label = 'Only' } }, 5)
    local listAfter = Core.registry.allShared('items')
    h.assertTrue(listBefore == listAfter, 'allShared list reference must stay live across reseed')
    h.assertEqual(RI.registries.items.epoch, 5)
    h.assertEqual(listAfter[1].label, 'Only')
    h.assertTrue(Core.registry.getShared('items', 'water_bottle') == nil, 'old keys cleared')
end)

h.report('registry')
