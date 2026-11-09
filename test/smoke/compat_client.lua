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
    _G.GetEntityModel = function(_) return GetHashKey('mp_m_freemode_01') end
    _G.GetPedDrawableVariation = function(_, _) return 0 end
    h.assertTrue(QBCore.Functions.IsWearingGloves() == false,
        'a male ped with drawable 0 (a MaleNoGloves index) must report NOT wearing gloves')

    _G.GetPedDrawableVariation = function(_, _) return 999 end
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

h.test('client callbacks table exists and fallback HasItem accepts the map form', function()
    h.assertEqual(type(QBCore.ClientCallbacks), 'table')
    h.assertEqual(type(QBCore.ServerCallbacks), 'table')
    local old = Core.replication.getData
    Core.replication.getData = function() return { { name = 'bread', amount = 3 }, { name = 'water', amount = 1 } } end
    h.assertTrue(QBCore.Functions.HasItem({ bread = 2, water = 1 }))
    h.assertTrue(not QBCore.Functions.HasItem({ bread = 4 }))
    h.assertTrue(QBCore.Functions.HasItem({ 'bread', 'water' }))
    h.assertTrue(QBCore.Functions.HasItem({ bread = 9 }, 3))
    Core.replication.getData = old
end)

h.test('Progressbar forwards raw legacy actions and the original owner to the shared adapter', function()
    local captured, owner, complete
    local invoking = GetInvokingResource
    GetInvokingResource = function() return 'legacy_repair' end
    exports.progressbar = { Progress = function(_, action, finish, caller)
        captured, owner, complete = action, caller, finish
    end }
    local controls = { disableMovement = true, disableCarMovement = true, disableMouse = true, disableCombat = true }
    local animation = { task = 'WORLD_HUMAN_WELDING' }
    local prop = { model = 'prop_one', bone = 60309, coords = { x = 1, y = 2, z = 3 } }
    local propTwo = { model = 'prop_two', bone = 28422, rotation = { x = 4, y = 5, z = 6 } }
    local finished, cancelled = 0, 0
    local results = table.pack(QBCore.Functions.Progressbar('repair', 'Repairing', 1500, false, true,
        controls, animation, prop, propTwo,
        function() finished = finished + 1 end, function() cancelled = cancelled + 1 end))
    h.assertEqual(results.n, 0)
    h.assertEqual(owner, 'legacy_repair', 'capture attribution before entering the provider export')
    h.assertEqual(captured.controlDisables, controls)
    h.assertEqual(captured.animation, animation)
    h.assertEqual(captured.prop, prop)
    h.assertEqual(captured.propTwo, propTwo)
    h.assertEqual(captured.name, 'repair')
    h.assertEqual(captured.props, nil, 'normalization belongs only to the adapter')
    complete(false)
    h.assertEqual(finished, 1)
    h.assertEqual(cancelled, 0)
    QBCore.Functions.Progressbar('cancel', 'Working', 500, false, true, nil, nil, nil, propTwo,
        function() finished = finished + 1 end, function() cancelled = cancelled + 1 end)
    h.assertEqual(captured.prop, nil)
    h.assertEqual(captured.propTwo, propTwo)
    complete(true)
    h.assertEqual(finished, 1)
    h.assertEqual(cancelled, 1)
    GetInvokingResource = invoking
end)

h.test('Progressbar preserves flags and async completion through object and direct export entry points', function()
    local exportedProgress
    TriggerEvent('__cfx_export_qb-core_Progressbar', function(fn) exportedProgress = fn end)
    h.assertEqual(exportedProgress, QBCore.Functions.Progressbar)
    local captured
    exports.progressbar = { Progress = function(_, action, finish)
        CreateThread(function() captured = action; finish(false) end)
    end }
    for _, progressbar in ipairs({ QBCore.Functions.Progressbar, exportedProgress }) do
        for _, setting in ipairs({ true, false, 'nil' }) do
            local allowed = setting
            if setting == 'nil' then allowed = nil end
            local finished = 0
            captured = nil
            local returns = table.pack(progressbar('legacy', 'Working', 100, allowed, false,
                nil, nil, nil, nil, function() finished = finished + 1 end))
            h.assertEqual(returns.n, 0, 'legacy call still returns no values')
            h.assertEqual(captured, nil, 'progress still completes asynchronously')
            handle.step()
            h.assertEqual(captured.useWhileDead, allowed)
            h.assertEqual(captured.canCancel, false)
            h.assertEqual(finished, 1, 'success still invokes the finish callback once')
        end
    end
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
    Kora.loops.controlled = function() return false, 'Loop timed out.' end

    local vehicle = QBCore.Functions.SpawnVehicle(123, nil, { x = 1, y = 2, z = 3, w = 0 }, false, false)
    h.assertFalse(vehicle)
    h.assertEqual(requested, 1)
    h.assertEqual(released, 1, 'a failed stream request should release its model')
    h.assertEqual(created, 0, 'CreateVehicle must not run with an unloaded model')
end)

h.test('client SpawnVehicle returns the server-spawned networked vehicle (stock isnetworked semantics)', function()
    local asked, warps, cbVeh = nil, {}, nil
    _G.IsModelInCdimage = function() return true end
    _G.vec3 = function(x, y, z) return { x = x, y = y, z = z } end
    _G.NetworkDoesNetworkIdExist = function() return true end
    _G.NetworkGetEntityFromNetworkId = function(netId) return netId + 1 end
    _G.DoesEntityExist = function() return true end
    _G.TaskWarpPedIntoVehicle = function(_, veh) warps[#warps + 1] = veh end
    _G.SetVehicleHasBeenOwnedByPlayer = function() end
    _G.SetVehicleNeedsToBeHotwired = function() end
    _G.SetVehRadioStation = function() end
    _G.SetVehicleFuelLevel = function() end
    _G.CreateVehicle = function() error('a networked request must not create a client entity') end
    Kora.loops.controlled = function(fn) return fn() end
    QBCore.Functions.TriggerCallback = function(name, ...) asked = { name = name, args = { ... } }; return 4000 end

    local result
    coroutine.wrap(function()
        result = QBCore.Functions.SpawnVehicle(123, function(veh) cbVeh = veh end, { x = 1, y = 2, z = 3, w = 90 }, nil, true)
    end)()
    h.assertEqual(asked.name, 'QBCore:Server:SpawnVehicle')
    h.assertEqual(asked.args[1], 123)
    h.assertEqual(asked.args[2].w, 90)
    h.assertEqual(asked.args[3], true)
    h.assertEqual(result, 4001)
    h.assertEqual(cbVeh, 4001)
    h.assertEqual(warps[1], 4001)
end)

h.test('client SpawnVehicle falls back to a local vehicle when the server refuses', function()
    local created = {}
    _G.HasModelLoaded = function() return true end
    _G.SetModelAsNoLongerNeeded = function() end
    _G.CreateVehicle = function(_, _, _, _, _, networked) created[#created + 1] = networked; return 600 end
    QBCore.Functions.TriggerCallback = function() return nil end
    Kora.loops.controlled = function(fn) return fn() end
    local result
    coroutine.wrap(function() result = QBCore.Functions.SpawnVehicle(123, nil, { x = 1, y = 2, z = 3, w = 0 }, true, false) end)()
    h.assertEqual(result, 600)
    h.assertEqual(created[1], false)
end)

h.test('isnetworked == false and callbacks off never ask the server', function()
    local asked = 0
    QBCore.Functions.TriggerCallback = function() asked = asked + 1 end
    coroutine.wrap(function() QBCore.Functions.SpawnVehicle(123, nil, { x = 1, y = 2, z = 3, w = 0 }, false, false) end)()
    Config.compat.vehicleSpawnCallbacks = 'off'
    coroutine.wrap(function() QBCore.Functions.SpawnVehicle(123, nil, { x = 1, y = 2, z = 3, w = 0 }, true, false) end)()
    Config.compat.vehicleSpawnCallbacks = 'limited'
    h.assertEqual(asked, 0)
end)

h.report('compat_client')
