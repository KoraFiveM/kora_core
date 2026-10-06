-- Client-realm compat shape test -- mirrors test/smoke/compat.lua (server) but
-- for compat/client/qb-core.lua: QBCore.Config population (previously only
-- built server-side, leaving it an empty `{}` client-side), the client-only
-- vehicle-extra Shared helpers (guarded on IsDuplicityVersion() == false), the
-- glove-check data tables, and the GetShared* exports registered client-side.

local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua')
local handle = mocks.install({ client = true })

dofile('config.lua')
dofile('shared/items.lua'); dofile('shared/jobs.lua'); dofile('shared/gangs.lua')
dofile('shared/vehicles.lua'); dofile('shared/weapons.lua'); dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua'); dofile('modules/registry/client.lua')
dofile('modules/player/shared.lua')
dofile('modules/player/client.lua')
dofile('compat/shared/coreobject.lua')
dofile('compat/client/qb-core.lua')

-- The real client only gets registry data via an async 'qbcore:registry:
-- snapshotAll' net event (modules/registry/client.lua); nothing in this test
-- environment ever fires it. Reseed directly, the same shape that net event
-- handler applies, then fire the local 'qbcore:registry:synced' event
-- coreobject.lua's Jobs/Gangs/VehicleHashes views listen for to re-fill.
local RI = CoreInternal.registry
RI.reseed('items', QBCoreSeed.items, 1)
RI.reseed('vehicles', QBCoreSeed.vehicles, 1)
RI.reseed('jobs', QBCoreSeed.jobs, 1)
RI.reseed('gangs', QBCoreSeed.gangs, 1)
RI.reseed('weapons', QBCoreSeed.weapons, 1)
RI.reseed('locations', QBCoreSeed.locations, 1)
TriggerEvent('qbcore:registry:synced')

h.test('IsDuplicityVersion() is false under the client mock', function()
    h.assertTrue(IsDuplicityVersion() == false, 'the client realm mock must report IsDuplicityVersion() == false')
end)

h.test('QBCore.Config is populated client-side (previously an empty {} table)', function()
    h.assertTrue(QBCore.Config.Money ~= nil, 'Config.Money must be populated')
    h.assertEqual(QBCore.Config.Money.MoneyTypes, Config.money.default)
    h.assertEqual(QBCore.Config.Money.PayCheckTimeOut, 10)

    h.assertTrue(QBCore.Config.Player ~= nil, 'Config.Player must be populated')
    h.assertEqual(QBCore.Config.Player.MaxWeight, Config.inventory.maxWeight)
    h.assertEqual(QBCore.Config.Player.MaxInvSlots, Config.inventory.slots)

    h.assertEqual(QBCore.Config.MaxPlayers, 48, 'MaxPlayers matches current qb-core default')

    h.assertTrue(QBCore.Config.Server ~= nil, 'Config.Server must be populated')
    h.assertEqual(QBCore.Config.Server.WhitelistPermission, 'admin')
    h.assertTrue(QBCore.Config.Server.Whitelist == false)
    h.assertTrue(type(QBCore.Config.Server.Permissions) == 'table' and #QBCore.Config.Server.Permissions > 0)
end)

h.test('QBCore.Config.UpdateInterval/StatusInterval are the documented upstream constants', function()
    h.assertEqual(QBCore.Config.UpdateInterval, 5)
    h.assertEqual(QBCore.Config.StatusInterval, 5000)
end)

h.test('QBCore.Shared.ChangeVehicleExtra/SetDefaultVehicleExtras ARE defined client-side', function()
    h.assertEqual(type(QBCore.Shared.ChangeVehicleExtra), 'function')
    h.assertEqual(type(QBCore.Shared.SetDefaultVehicleExtras), 'function')
end)

h.test('ChangeVehicleExtra toggles a vehicle extra on/off via the mocked natives', function()
    QBCore.Shared.ChangeVehicleExtra(1, 3, true)
    h.assertTrue(IsVehicleExtraTurnedOn(1, 3), 'extra 3 must be turned ON')
    QBCore.Shared.ChangeVehicleExtra(1, 3, false)
    h.assertTrue(not IsVehicleExtraTurnedOn(1, 3), 'extra 3 must be turned OFF')
end)

h.test('SetDefaultVehicleExtras turns everything off then applies the config overrides', function()
    QBCore.Shared.SetDefaultVehicleExtras(2, { [1] = true, [2] = false })
    h.assertTrue(IsVehicleExtraTurnedOn(2, 1), 'extra 1 must be enabled per config')
    h.assertTrue(not IsVehicleExtraTurnedOn(2, 2), 'extra 2 must stay disabled per config')
    h.assertTrue(not IsVehicleExtraTurnedOn(2, 5), 'an extra not mentioned in config must default OFF (the "turn everything off first" pass)')
end)

h.test('QBCore.Shared.MaleNoGloves/FemaleNoGloves activate the existing F.IsWearingGloves check', function()
    -- Before this task these tables were nil, so `(QBCore.Shared.MaleNoGloves or {})[armIndex]`
    -- always no-op'd to `nil` and IsWearingGloves always returned true. Wire the
    -- mocked model/drawable natives so the real branch executes.
    _G.GetEntityModel = function(_) return GetHashKey('mp_m_freemode_01') end
    _G.GetPedDrawableVariation = function(_, _) return 0 end -- index 0 is a known no-glove index (upstream data)
    h.assertTrue(QBCore.Functions.IsWearingGloves() == false,
        'a male ped with drawable 0 (a MaleNoGloves index) must report NOT wearing gloves')

    _G.GetPedDrawableVariation = function(_, _) return 999 end -- not a no-glove index
    h.assertTrue(QBCore.Functions.IsWearingGloves() == true,
        'a drawable index absent from MaleNoGloves must report wearing gloves')
end)

h.test('GetSharedItems/Vehicles/Jobs/Gangs/Weapons exports are registered client-side too', function()
    local exportHandlers = {}
    for _, name in ipairs({ 'GetSharedItems', 'GetSharedVehicles', 'GetSharedJobs', 'GetSharedGangs', 'GetSharedWeapons' }) do
        TriggerEvent(('__cfx_export_qb-core_%s'):format(name), function(fn) exportHandlers[name] = fn end)
    end
    h.assertTrue(type(exportHandlers.GetSharedItems) == 'function', 'GetSharedItems export must be registered client-side')
    h.assertTrue(exportHandlers.GetSharedItems().water_bottle ~= nil, 'GetSharedItems must return the Items namespace')
    h.assertTrue(exportHandlers.GetSharedVehicles().sultan ~= nil, 'GetSharedVehicles must return the Vehicles namespace')
    h.assertTrue(exportHandlers.GetSharedWeapons() ~= nil, 'GetSharedWeapons must return the Weapons namespace')

    local jobs = exportHandlers.GetSharedJobs()
    h.assertTrue(jobs.police ~= nil and jobs.police.grades['0'] ~= nil,
        'GetSharedJobs must return the legacy zero-based grade view, same as QBCore.Shared.Jobs')
    local gangs = exportHandlers.GetSharedGangs()
    h.assertTrue(gangs.ballas ~= nil and gangs.ballas.grades['0'] ~= nil,
        'GetSharedGangs must return the legacy zero-based grade view')
end)

h.test('GetCoreObject filters the client object exactly like the server export', function()
    local getCoreObject
    TriggerEvent('__cfx_export_qb-core_GetCoreObject', function(fn) getCoreObject = fn end)
    h.assertTrue(type(getCoreObject) == 'function', 'GetCoreObject export must be registered client-side')
    local filtered = getCoreObject({ 'Functions', 'Shared' })
    h.assertEqual(filtered.Functions, QBCore.Functions)
    h.assertEqual(filtered.Shared, QBCore.Shared)
    h.assertTrue(filtered.Config == nil, 'unrequested namespaces must not be returned')
end)

h.test('Progressbar forwards legacy prop and propTwo descriptors to qblib', function()
    local captured
    local finished = false
    QB.progressbar.start = function(payload)
        captured = payload
        return true
    end

    QBCore.Functions.Progressbar('repair', 'Repairing', 1500, false, true,
        { disableMovement = true, disableCarMovement = true, disableCombat = true },
        { animDict = 'anim@test', anim = 'loop', flags = 49 },
        {
            model = 'prop_one',
            bone = 60309,
            coords = { x = 1, y = 2, z = 3 },
            rotation = { x = 4, y = 5, z = 6 },
        },
        {
            model = 'prop_two',
            bone = 28422,
            coords = { x = 7, y = 8, z = 9 },
            rotation = { x = 10, y = 11, z = 12 },
        },
        function() finished = true end)

    handle.step()

    h.assertTrue(captured ~= nil, 'the qblib progressbar should be invoked from the compatibility thread')
    h.assertEqual(#captured.props, 2, 'prop and propTwo should become two qblib props')
    h.assertEqual(captured.props[1].model, 'prop_one')
    h.assertEqual(captured.props[1].offset.x, 1, 'legacy coords should map to offset')
    h.assertEqual(captured.props[2].rotation.z, 12, 'legacy rotation should pass through')
    h.assertTrue(captured.props[1].collision, 'legacy props should retain qb-progressbar collision behavior')
    h.assertTrue(captured.props[1].softPinning and captured.props[1].syncRotation,
        'legacy attachment defaults should be explicit')
    h.assertEqual(captured.props[1].rotationOrder, 0)
    h.assertTrue(finished, 'a successful qblib result should still invoke onFinish')

    captured = nil
    QBCore.Functions.Progressbar('second-only', 'Working', 500, false, false, nil, nil, nil,
        { model = 'prop_second_only', bone = 28422 })
    handle.step()
    h.assertEqual(#captured.props, 1, 'propTwo should still forward when prop is nil')
    h.assertEqual(captured.props[1].model, 'prop_second_only')
end)

h.test('Progressbar forwards useWhileDead through object and direct export entry points', function()
    local exportedProgress
    TriggerEvent('__cfx_export_qb-core_Progressbar', function(fn) exportedProgress = fn end)
    h.assertEqual(exportedProgress, QBCore.Functions.Progressbar)
    local captured
    local originalStart = QB.progressbar.start
    QB.progressbar.start = function(payload) captured = payload; return true end
    for _, progressbar in ipairs({ QBCore.Functions.Progressbar, exportedProgress }) do
        for _, setting in ipairs({ true, false, 'nil' }) do
            local allowed = setting
            if setting == 'nil' then allowed = nil end
            local finished = 0
            captured = nil
            local returns = table.pack(progressbar('legacy', 'Working', 100, allowed, false,
                nil, nil, nil, nil, function() finished = finished + 1 end))
            h.assertEqual(returns.n, 0, 'legacy call still returns no values')
            h.assertEqual(captured, nil, 'progress still starts asynchronously')
            handle.step()
            h.assertEqual(captured.useWhileDead, allowed)
            h.assertEqual(captured.canCancel, false)
            h.assertEqual(finished, 1, 'success still invokes the finish callback once')
        end
    end
    QB.progressbar.start = originalStart
end)

h.test('client SpawnVehicle stops cleanly when its model cannot load', function()
    local requested, released, created = 0, 0, 0
    _G.IsModelInCdimage = function() return true end
    _G.IsModelValid = function() return true end
    _G.vec3 = function(x, y, z) return { x = x, y = y, z = z } end
    _G.HasModelLoaded = function() return false end
    _G.RequestModel = function() requested = requested + 1 end
    _G.SetModelAsNoLongerNeeded = function() released = released + 1 end
    _G.CreateVehicle = function() created = created + 1; return 501 end
    QB.loops.controlled = function() return false, 'Loop timed out.' end

    local vehicle = QBCore.Functions.SpawnVehicle(123, nil, { x = 1, y = 2, z = 3, w = 0 }, false, false)
    h.assertFalse(vehicle)
    h.assertEqual(requested, 1)
    h.assertEqual(released, 1, 'a failed stream request should release its model')
    h.assertEqual(created, 0, 'CreateVehicle must not run with an unloaded model')
end)

h.report('compat_client')
