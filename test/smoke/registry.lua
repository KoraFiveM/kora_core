local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua')
local handle = mocks.install()

dofile('config.lua')
dofile('shared/items.lua')
dofile('shared/vehicles.lua')
dofile('shared/jobs.lua')
dofile('shared/gangs.lua')
dofile('shared/upstream/items.lua')
dofile('shared/upstream/jobs.lua')
dofile('shared/upstream/gangs.lua')
dofile('shared/upstream/merge.lua')
dofile('shared/weapons.lua')
dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua')
local ownershipRegistry
local serverRegistry = Kora.resources.serverRegistry
Kora.resources.serverRegistry = function(onDispose)
    ownershipRegistry = serverRegistry(onDispose)
    return ownershipRegistry
end
dofile('modules/registry/server.lua')

local RI = CoreInternal.registry

h.test('seeds are ingested and readable via getShared', function()
    h.assertTrue(Core.registry.getShared('items', 'water_bottle') ~= nil, 'seed item missing')
    h.assertTrue(Core.registry.countShared('jobs') >= 3, 'seed jobs missing')
end)

h.test('canonical qb-core items, jobs and gangs supplement local defaults', function()
    local item = assert(Core.registry.getShared('items', 'advancedlockpick'))
    local job = assert(Core.registry.getShared('jobs', 'bus'))
    local gang = assert(Core.registry.getShared('gangs', 'lostmc'))

    h.assertEqual(item.image, 'advancedlockpick.png')
    h.assertEqual(job.grades[1].name, 'Driver')
    h.assertEqual(gang.grades[1].name, 'Recruit')
    h.assertTrue(Core.registry.countShared('items') >= 321, 'full qb-core item set was not merged')
end)

h.test('purpose-built local records win conflicts with qb-core defaults', function()
    local police = assert(Core.registry.getShared('jobs', 'police'))
    local backpack = assert(Core.registry.getShared('items', 'backpack'))

    h.assertFalse(police.defaultDuty, 'local service duty policy must be preserved')
    h.assertEqual(police.grades[1].name, 'Cadet')
    h.assertTrue(backpack.container, 'local container metadata must be preserved')
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
        if event.name == 'kora_core:registry:delta' then seen[event.args[1]] = true end
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
    Core.registry.registerShared('items', 'itemA', { name = 'itemA', label = 'A' })
    Core.registry.registerShared('items', 'itemB', { name = 'itemB', label = 'B' })
    local before = Core.registry.countShared('items')
    Core.registry.unregisterShared('items', 'itemA')
    h.assertEqual(Core.registry.countShared('items'), before - 1)
    h.assertTrue(Core.registry.getShared('items', 'itemA') == nil, 'itemA should be gone')
    local idx = RI.registries.items.index.itemB
    h.assertEqual(RI.registries.items.list[idx].name, 'itemB')
end)

h.test('onChange fires with add/remove and the resource-stop sweep removes records', function()
    _G.GetInvokingResource = function() return 'some-plugin' end
    Core.registry.registerShared('items', 'plugin_item', { name = 'plugin_item', label = 'P' })
    h.assertTrue(Core.registry.getShared('items', 'plugin_item') ~= nil)

    _G.GetInvokingResource = function() return nil end
    ownershipRegistry._dispose('some-plugin')
    h.assertTrue(Core.registry.getShared('items', 'plugin_item') == nil, 'swept record should be gone')
end)

h.test('replacement belongs to the latest owner even when both register the same table', function()
    local record = { name = 'shared_item', label = 'Shared' }
    _G.GetInvokingResource = function() return 'owner-a' end
    h.assertTrue(Core.registry.registerShared('items', record.name, record))
    _G.GetInvokingResource = function() return 'owner-b' end
    h.assertTrue(Core.registry.registerShared('items', record.name, record))
    local before = #handle.clientEvents
    ownershipRegistry._dispose('owner-a')
    h.assertEqual(Core.registry.getShared('items', record.name), record)
    h.assertEqual(#handle.clientEvents, before, 'previous owner emits no removal delta')
    ownershipRegistry._dispose('owner-b')
    h.assertEqual(Core.registry.getShared('items', record.name), nil)
    h.assertEqual(#handle.clientEvents, before + 1, 'current owner emits one removal delta')
    _G.GetInvokingResource = function() return nil end
end)

h.test('public and internal removal clear ownership before a different resource re-registers', function()
    for _, remove in ipairs({ Core.registry.unregisterShared, Core.registry._unregisterInternal }) do
        _G.GetInvokingResource = function() return 'removal-owner-a' end
        h.assertTrue(Core.registry.registerShared('items', 'readded', { name = 'readded' }))
        _G.GetInvokingResource = function() return 'foreign-remover' end
        h.assertTrue(remove('items', 'readded'), 'foreign removal remains allowed')
        h.assertFalse(remove('items', 'readded'), 'missing removal return stays false')
        _G.GetInvokingResource = function() return 'removal-owner-b' end
        local replacement = { name = 'readded', label = 'New' }
        h.assertTrue(Core.registry.registerShared('items', 'readded', replacement))
        ownershipRegistry._dispose('removal-owner-a')
        h.assertEqual(Core.registry.getShared('items', 'readded'), replacement)
        ownershipRegistry._dispose('removal-owner-b')
        h.assertEqual(Core.registry.getShared('items', 'readded'), nil)
    end
    _G.GetInvokingResource = function() return nil end
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

h.test('snapshot requests from one client share one trailing answer', function()
    handle.drainTimeouts()
    local function sent()
        local n = 0
        for _, event in ipairs(handle.clientEvents) do
            if event.name == 'kora_core:registry:snapshotAll' and event.target == 77 then n = n + 1 end
        end
        return n
    end
    for _ = 1, 5 do handle.fireEvent('kora_core:registry:requestSnapshot', 77) end
    h.assertEqual(sent(), 1, 'the first request is answered at once')
    handle.drainTimeouts()
    h.assertEqual(sent(), 2, 'requests inside the window get one trailing answer')
    handle.drainTimeouts()
    h.assertEqual(sent(), 2, 'a quiet window sends nothing more')
    handle.fireEvent('kora_core:registry:requestSnapshot', 77)
    h.assertEqual(sent(), 3, 'a request after the window is answered at once')
    handle.drainTimeouts()
end)

h.report('registry')
