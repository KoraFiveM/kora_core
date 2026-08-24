-- Compat shape test -- asserts every documented legacy field of the QBCore
-- object exists and is callable, and that the per-player Player.Functions.*
-- table is complete. This is what keeps compat honest: an internal rename that
-- drops a legacy method fails HERE at CI, not in someone's production server.

local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua')
local handle = mocks.install()

dofile('config.lua')
dofile('shared/items.lua'); dofile('shared/jobs.lua'); dofile('shared/gangs.lua')
dofile('shared/vehicles.lua'); dofile('shared/weapons.lua'); dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua'); dofile('modules/registry/server.lua')
dofile('modules/player/shared.lua')
dofile('modules/replication/server.lua')
dofile('modules/persistence/server.lua')
dofile('modules/player/server.lua')
dofile('modules/money/server.lua')
dofile('modules/jobs/server.lua')
dofile('modules/metadata/server.lua')
dofile('modules/inventory/shared.lua'); dofile('modules/inventory/server.lua')
dofile('modules/inventory/gateway.lua')
dofile('modules/multichar/server.lua')
dofile('modules/permissions/server.lua')
dofile('modules/commands/server.lua')
dofile('modules/logging/server.lua')
dofile('compat/shared/coreobject.lua')
dofile('compat/server/qb-core.lua')
dofile('compat/server/qb-core-events.lua')

local function assertCallableFields(tbl, names, label)
    for _, n in ipairs(names) do
        local v = tbl[n]
        h.assertTrue(type(v) == 'function', ('%s.%s must be callable'):format(label, n))
    end
end

h.test('QBCore.Functions.* surface is complete', function()
    assertCallableFields(QBCore.Functions, {
        'GetPlayer', 'GetPlayerByCitizenId', 'GetPlayerByPhone', 'GetPlayers', 'GetQBPlayers',
        'GetOfflinePlayerByCitizenId', 'GetIdentifier', 'GetSource', 'CreateCallback', 'TriggerCallback',
        'CreateUseableItem', 'CanUseItem', 'UseItem', 'HasPermission', 'GetPermission', 'AddPermission',
        'IsOptin', 'Kick', 'Notify', 'HasItem', 'ExecuteSql', 'PaycheckInterval',
        -- full-parity additions (real qb-core server/functions.lua + exports.lua)
        'GetCoords', 'GetPlayerByLicense', 'GetPlayerByAccount', 'GetPlayerByCharInfo',
        'GetPlayersByJob', 'GetPlayersOnDuty', 'GetDutyCount',
        'GetClosestPlayer', 'GetClosestVehicle', 'GetClosestPed', 'GetClosestObject',
        'GetBucketObjects', 'SetPlayerBucket', 'SetEntityBucket', 'GetPlayersInBucket', 'GetEntitiesInBucket',
        'SpawnVehicle', 'CreateAutomobile', 'CreateVehicle', 'TriggerClientCallback',
        'RemovePermission', 'ToggleOptin', 'IsWhitelisted', 'IsPlayerBanned', 'IsLicenseInUse',
        'GetDatabaseInfo', 'GetCoreVersion', 'ExploitBan', 'SetMethod', 'SetField',
        'AddItem', 'UpdateItem', 'AddItems', 'RemoveItem',
        'AddJob', 'AddJobs', 'UpdateJob', 'RemoveJob',
        'AddGang', 'AddGangs', 'UpdateGang', 'RemoveGang',
    }, 'QBCore.Functions')
end)

h.test('QBCore.Player.* surface is complete', function()
    assertCallableFields(QBCore.Player, {
        'Login', 'Logout', 'Save', 'SaveOffline', 'CreatePlayer', 'DeleteCharacter',
        'CheckPlayerData', 'ForceUpdatePlayerData',
        -- full-parity additions
        'ForceDeleteCharacter', 'GetOfflinePlayer', 'GetPlayerByLicense', 'GetOfflinePlayerByLicense',
        'CreateCitizenId', 'CreateFingerId', 'CreateWalletId', 'CreateSerialNumber',
    }, 'QBCore.Player')
end)

h.test('QBCore.Commands.List is a table (not a function), matching real qb-core', function()
    h.assertTrue(type(QBCore.Commands.List) == 'table', 'Commands.List must be an indexable/iterable table')
end)

h.test('QBCore.Shared data tables are RAW keys (survive the export boundary)', function()
    -- A consumer's GetCoreObject() result crosses the export boundary as a
    -- msgpack copy: the metatable (and its lazy __index) does not survive, so
    -- any key still lazy at that point is simply ABSENT in the consumer's copy
    -- of Shared -- exactly how qb-banking's `pairs(QBCore.Shared.Jobs)` ended
    -- up iterating nil. compat/server/qb-core.lua force-materialises them at
    -- load; this pins that so a refactor can't silently reintroduce lazy-only
    -- exposure. rawget bypasses __index, so it only sees genuinely-set keys.
    -- ORDER MATTERS: this must run before any other test in this file reads a
    -- QBCore.Shared.<Data> key -- such a read would fire the lazy __index and
    -- rawset the key itself, masking a missing eager load.
    for _, k in ipairs({ 'Items', 'Vehicles', 'Jobs', 'Gangs', 'Weapons' }) do
        h.assertTrue(rawget(QBCore.Shared, k) ~= nil,
            ('Shared.%s must be a raw key after server compat load, not a lazy __index view'):format(k))
    end
end)

h.test('QBCore.Shared.* helpers and data tables resolve', function()
    assertCallableFields(QBCore.Shared, { 'Round', 'Trim', 'SplitStr', 'RandomStr', 'RandomInt' }, 'QBCore.Shared')
    -- Data tables resolve lazily via the metatable to the materialised registries.
    h.assertTrue(QBCore.Shared.Items ~= nil, 'Shared.Items resolves')
    h.assertTrue(QBCore.Shared.Items.water_bottle ~= nil, 'Shared.Items has a seed item')
    h.assertTrue(QBCore.Shared.Jobs ~= nil and QBCore.Shared.Jobs.police ~= nil, 'Shared.Jobs resolves')
    h.assertTrue(QBCore.Shared.Vehicles ~= nil and QBCore.Shared.Gangs ~= nil and QBCore.Shared.Weapons ~= nil)
end)

h.test('QBCore.Shared.Jobs grades use legacy zero-based string keys', function()
    local police = QBCore.Shared.Jobs.police
    h.assertTrue(police.grades['0'] ~= nil and police.grades['0'].name == 'Cadet',
        "grades['0'] must be the first grade (legacy zero-based stringified keys)")
    h.assertTrue(police.grades[1] == nil, 'the internal one-based array shape must not leak')
end)

h.test('QBCore.Commands.Add and QBCore.Debug exist', function()
    h.assertTrue(type(QBCore.Commands.Add) == 'function')
    h.assertTrue(type(QBCore.Debug) == 'function')
end)

h.test('QBCore.Shared.FirstToUpper capitalizes the first letter', function()
    h.assertEqual(QBCore.Shared.FirstToUpper('hello'), 'Hello')
    h.assertEqual(QBCore.Shared.FirstToUpper('Already'), 'Already')
end)

h.test('QBCore.Shared.IsFunction accepts a real function AND a callable table (this codebase\'s isCallable convention)', function()
    h.assertTrue(QBCore.Shared.IsFunction(function() end), 'a plain function must be callable')
    h.assertTrue(not QBCore.Shared.IsFunction('nope'), 'a string is not callable')
    h.assertTrue(not QBCore.Shared.IsFunction(nil), 'nil is not callable')
    h.assertTrue(QBCore.Shared.IsFunction({ __cfx_functionReference = 'abc' }),
        'a CFX export-boundary funcref table must be callable (matches upstream)')
    h.assertTrue(QBCore.Shared.IsFunction(setmetatable({}, { __call = function() end })),
        'a __call-metatable table must be callable (this codebase\'s isCallable convention)')
end)

h.test('QBCore.Shared.StarterItems is the documented shape', function()
    h.assertEqual(QBCore.Shared.StarterItems.phone.item, 'phone')
    h.assertEqual(QBCore.Shared.StarterItems.id_card.item, 'id_card')
    h.assertEqual(QBCore.Shared.StarterItems.driver_license.item, 'driver_license')
    for _, k in ipairs({ 'phone', 'id_card', 'driver_license' }) do
        h.assertEqual(QBCore.Shared.StarterItems[k].amount, 1)
    end
end)

h.test('QBCore.Shared.MaleNoGloves/FemaleNoGloves are number-keyed sets (index -> true)', function()
    h.assertTrue(QBCore.Shared.MaleNoGloves[0] == true, 'MaleNoGloves[0] must be present (matches upstream)')
    h.assertTrue(QBCore.Shared.MaleNoGloves[132] == true, 'MaleNoGloves must include the last upstream index (132)')
    h.assertTrue(QBCore.Shared.FemaleNoGloves[0] == true, 'FemaleNoGloves[0] must be present')
    h.assertTrue(QBCore.Shared.FemaleNoGloves[165] == true, 'FemaleNoGloves must include the last upstream index (165)')
end)

h.test('QBCore.Shared.ChangeVehicleExtra/SetDefaultVehicleExtras are NOT defined server-side', function()
    -- These touch client-only natives; coreobject.lua guards them with
    -- `if not IsDuplicityVersion() then`. This test runs under the server mock
    -- (IsDuplicityVersion() == true), so they must be absent here.
    h.assertTrue(QBCore.Shared.ChangeVehicleExtra == nil, 'ChangeVehicleExtra must not exist server-side')
    h.assertTrue(QBCore.Shared.SetDefaultVehicleExtras == nil, 'SetDefaultVehicleExtras must not exist server-side')
end)

h.test('QBCore.Shared.Locations resolves to the same materialised registry allShared sees', function()
    local viaShared = QBCore.Shared.Locations
    h.assertTrue(viaShared ~= nil, 'Shared.Locations must resolve')
    local viaRegistry = Core.registry.allShared('locations')
    h.assertTrue(#viaRegistry > 0, 'the locations registry must have seed records to compare against')
    local seedKey = viaRegistry[1].key
    h.assertTrue(viaShared[seedKey] ~= nil, 'Shared.Locations must contain the same record allShared returns')
    h.assertEqual(viaShared[seedKey], CoreInternal.registry.registries.locations.materialised[seedKey],
        'Shared.Locations must be the SAME table reference as the registry\'s materialised view, not a copy')
end)

h.test('QBCore.Shared.VehicleHashes resolves a seeded vehicle by GetHashKey(model)', function()
    local sultan = QBCore.Shared.Vehicles.sultan
    h.assertTrue(sultan ~= nil, 'seed vehicle "sultan" must exist')
    local byHash = QBCore.Shared.VehicleHashes[GetHashKey('sultan')]
    h.assertTrue(byHash ~= nil, 'VehicleHashes must resolve the hash of a seeded model')
    h.assertEqual(byHash.model, 'sultan')
    h.assertEqual(byHash.name, sultan.name)
end)

h.test('QBCore.Shared.VehicleHashes REFRESHES when the vehicle registry changes (not a one-shot build)', function()
    -- Read it once first so the cached view is built and rawset onto Shared.
    local before = QBCore.Shared.VehicleHashes
    h.assertTrue(before[GetHashKey('newcar')] == nil, 'newcar must not be registered yet')
    local ok = Core.registry.registerShared('vehicles', 'newcar', { model = 'newcar', name = 'New Car', brand = 'Test', price = 1 })
    h.assertTrue(ok, 'registerShared must succeed')
    -- Same cached table reference (rawset caches it), but now must contain the
    -- newly-registered vehicle keyed by its hash -- proving the onSharedChange
    -- refresh wiring fired, not just the initial build.
    local after = QBCore.Shared.VehicleHashes
    h.assertTrue(after == before, 'VehicleHashes must stay the SAME cached table reference')
    h.assertTrue(after[GetHashKey('newcar')] ~= nil, 'VehicleHashes must include a vehicle registered AFTER the first read')
    h.assertEqual(after[GetHashKey('newcar')].name, 'New Car')
end)

h.test('GetSharedItems/Vehicles/Jobs/Gangs/Weapons exports exist and return the right data', function()
    local exportHandlers = {}
    -- Capture provideExport's registered functions the same way the export
    -- boundary would: fire the __cfx_export_* event and record what setCB got.
    for _, name in ipairs({ 'GetSharedItems', 'GetSharedVehicles', 'GetSharedJobs', 'GetSharedGangs', 'GetSharedWeapons' }) do
        TriggerEvent(('__cfx_export_qb-core_%s'):format(name), function(fn) exportHandlers[name] = fn end)
    end
    h.assertTrue(type(exportHandlers.GetSharedItems) == 'function', 'GetSharedItems export must be registered')
    h.assertTrue(exportHandlers.GetSharedItems().water_bottle ~= nil, 'GetSharedItems must return the Items namespace')
    h.assertTrue(exportHandlers.GetSharedVehicles().sultan ~= nil, 'GetSharedVehicles must return the Vehicles namespace')
    h.assertTrue(exportHandlers.GetSharedWeapons() ~= nil, 'GetSharedWeapons must return the Weapons namespace')

    -- Jobs/Gangs must be the LEGACY zero-based grade view, same as
    -- QBCore.Shared.Jobs/Gangs -- not the raw internal one-based registry.
    local jobs = exportHandlers.GetSharedJobs()
    h.assertTrue(jobs.police ~= nil, 'GetSharedJobs must include the police job')
    h.assertTrue(jobs.police.grades['0'] ~= nil and jobs.police.grades['0'].name == 'Cadet',
        "GetSharedJobs must return grades keyed by stringified ZERO-based level, matching QBCore.Shared.Jobs")
    h.assertTrue(jobs.police.grades[1] == nil, 'the internal one-based array shape must not leak through the export')

    local gangs = exportHandlers.GetSharedGangs()
    h.assertTrue(gangs.ballas ~= nil, 'GetSharedGangs must include a seed gang')
    h.assertTrue(gangs.ballas.grades['0'] ~= nil, 'GetSharedGangs grades must also be zero-based')
end)

h.test('GetShared accepts lowercase namespace casing (real-world legacy scripts vary)', function()
    -- qb-recyclejob's own client.lua AND server.lua both call
    -- exports['qb-core']:GetShared('items') -- lowercase, not the PascalCase
    -- QBCore.Shared uses internally. A plain QBCore.Shared[namespace] lookup
    -- silently returns nil for this, and since GetShared's callers almost
    -- always cache the result in a file-scope local at resource start, the
    -- nil doesn't surface until something LATER in the file indexes it --
    -- "attempt to index a nil value (upvalue 'sharedItems')" deep in
    -- qb-recyclejob/server.lua, with no hint the real problem was casing.
    local exportHandlers = {}
    TriggerEvent('__cfx_export_qb-core_GetShared', function(fn) exportHandlers.GetShared = fn end)
    h.assertTrue(type(exportHandlers.GetShared) == 'function', 'GetShared export must be registered')

    local lower = exportHandlers.GetShared('items')
    h.assertTrue(lower ~= nil, "GetShared('items') must resolve the same as GetShared('Items')")
    h.assertTrue(lower.water_bottle ~= nil, 'the lowercase call must return the real Items namespace, not an empty table')

    -- The canonical PascalCase form (and the `item` second-arg form) must
    -- keep working unchanged.
    h.assertEqual(exportHandlers.GetShared('Items'), lower, 'PascalCase must still resolve to the exact same table')
    h.assertTrue(exportHandlers.GetShared('items', 'water_bottle') ~= nil, 'the two-arg (namespace, item) form must also honour the casing fallback')

    -- An unknown namespace (correct casing or not) must still return nil,
    -- not error -- the fallback must not turn "no such namespace" into a
    -- crash or a false positive.
    h.assertTrue(exportHandlers.GetShared('not_a_real_namespace') == nil, 'an unrecognised namespace must still return nil')
end)

h.test('per-player Player.Functions.* is complete after login', function()
    local data = CoreInternal.player.freshData('CID1', 'license:abc', 1, { firstname = 'A', lastname = 'B' })
    Core.player.login(1, 'CID1', data)
    local Player = QBCore.Functions.GetPlayer(1)
    h.assertTrue(Player ~= nil, 'GetPlayer returned a QBPlayer')
    assertCallableFields(Player.Functions, {
        'SetJob', 'SetGang', 'SetJobDuty', 'SetJobData', 'SetGangData',
        'AddMoney', 'RemoveMoney', 'SetMoney', 'GetMoney',
        'AddItem', 'RemoveItem', 'GetItemByName', 'GetItemsByName', 'GetItemBySlot',
        'ClearInventory', 'SetInventory', 'SetCreditCard',
        'SetMetaData', 'GetMetaData', 'SetCharInfo', 'SetPlayerData', 'UpdatePlayerData',
        'GetPlayerData', 'Save', 'Logout', 'GetName',
        -- modern-era additions (real qb-core varargMethods/noargMethods)
        'Notify', 'HasItem', 'AddRep', 'RemoveRep', 'GetRep', 'AddMethod', 'AddField', 'UpdateClient',
    }, 'Player.Functions')
    h.assertEqual(Player.PlayerData.citizenid, 'CID1', 'PlayerData wired through')
end)

h.test('a Player.Functions call routes through the funnel (AddMoney changes balance)', function()
    local Player = QBCore.Functions.GetPlayer(1)
    local before = Player.Functions.GetMoney('cash')
    Player.Functions.AddMoney('cash', 500, 'test')
    h.assertEqual(Player.Functions.GetMoney('cash'), before + 500)
end)

h.test('QBCore:Server:OnPlayerUpdated fans out to legacy-shaped OnJobUpdate + OnGangUpdate', function()
    -- police has 5 seed grades (shared/jobs.lua): internal grade 3 = Sergeant
    -- = legacy level 2. Same for the gang seed used below.
    Core.jobs.setJob(1, 'police', 3)
    Core.jobs.setGang(1, 'ballas', 1)

    local jobCaptured, gangCaptured
    AddEventHandler('QBCore:Server:OnJobUpdate', function(src, job) jobCaptured = job end)
    AddEventHandler('QBCore:Server:OnGangUpdate', function(src, gang) gangCaptured = gang end)

    TriggerEvent('QBCore:Server:OnPlayerUpdated', 1, 'all')

    h.assertTrue(jobCaptured ~= nil, 'OnJobUpdate must fire')
    h.assertEqual(jobCaptured.grade.level, 2, 'the fanned-out job payload must be legacy-shaped (zero-based grade.level)')
    h.assertTrue(gangCaptured ~= nil, 'OnGangUpdate must fire')
    h.assertEqual(gangCaptured.grade.level, 0, 'the fanned-out gang payload must be legacy-shaped (zero-based grade.level)')
end)

h.test('QBCore:Server:OnPlayerUpdated with an unrelated key is a no-op', function()
    local fired = false
    AddEventHandler('QBCore:Server:OnJobUpdate', function() fired = true end)
    TriggerEvent('QBCore:Server:OnPlayerUpdated', 1, 'somethingElse')
    h.assertFalse(fired, 'only key == nil/"all" should fan out')
end)

h.report('compat')
