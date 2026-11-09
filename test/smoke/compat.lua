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
        'GetCoords', 'GetPlayerByLicense', 'GetPlayerByAccount', 'GetPlayerByCharInfo',
        'GetPlayersByJob', 'GetPlayersOnDuty', 'GetDutyCount',
        'GetClosestPlayer', 'GetClosestVehicle', 'GetClosestPed', 'GetClosestObject',
        'GetBucketObjects', 'SetPlayerBucket', 'SetEntityBucket', 'GetPlayersInBucket', 'GetEntitiesInBucket',
        'SpawnVehicle', 'CreateAutomobile', 'CreateVehicle', 'TriggerClientCallback',
        'RemovePermission', 'ToggleOptin', 'IsWhitelisted', 'IsPlayerBanned', 'IsLicenseInUse',
        'GetDatabaseInfo', 'GetCoreVersion', 'ExploitBan', 'SetMethod', 'SetField',
        'CreatePhoneNumber', 'CreateAccountNumber', 'AddPlayerMethod', 'AddPlayerField',
        'GetOfflinePlayerByLicense',
        'AddItem', 'UpdateItem', 'AddItems', 'RemoveItem',
        'AddJob', 'AddJobs', 'UpdateJob', 'RemoveJob',
        'AddGang', 'AddGangs', 'UpdateGang', 'RemoveGang',
    }, 'QBCore.Functions')
end)

h.test('QBCore.Config exposes the complete current qb-core shape', function()
    h.assertTrue(QBCore.Config.DefaultSpawn ~= nil)
    h.assertTrue(type(QBCore.Config.Money.DontAllowMinus) == 'table')
    h.assertTrue(QBCore.Config.Money.MinusLimit ~= nil)
    h.assertTrue(QBCore.Config.Player.PlayerDefaults ~= nil)
    h.assertTrue(type(QBCore.Config.Player.PlayerDefaults.charinfo.phone) == 'function')
    h.assertTrue(type(QBCore.Config.Player.PlayerDefaults.metadata.fingerprint) == 'function')
    h.assertTrue(QBCore.Config.Server.CheckDuplicateLicense == true)
    h.assertTrue(QBCore.Config.Commands.OOCColor[1] == 255)
    h.assertTrue(QBCore.Config.Notify.VariantDefinitions.success ~= nil)
    h.assertTrue(QBCore.Shared.ForceJobDefaultDutyAtLogin == true)
end)

h.test('QBCore.Player.* surface is complete', function()
    assertCallableFields(QBCore.Player, {
        'Login', 'Logout', 'Save', 'SaveOffline', 'CreatePlayer', 'DeleteCharacter',
        'CheckPlayerData', 'ForceUpdatePlayerData',
        'ForceDeleteCharacter', 'GetOfflinePlayer', 'GetPlayerByLicense', 'GetOfflinePlayerByLicense',
        'CreateCitizenId', 'CreateFingerId', 'CreateWalletId', 'CreateSerialNumber',
    }, 'QBCore.Player')
end)

h.test('QBCore.Commands.List is a table (not a function), matching real qb-core', function()
    h.assertTrue(type(QBCore.Commands.List) == 'table', 'Commands.List must be an indexable/iterable table')
end)

h.test('QBCore.Shared data tables are RAW keys (survive the export boundary)', function()
    for _, k in ipairs({ 'Items', 'Vehicles', 'Jobs', 'Gangs', 'Weapons' }) do
        h.assertTrue(rawget(QBCore.Shared, k) ~= nil,
            ('Shared.%s must be a raw key after server compat load, not a lazy __index view'):format(k))
    end
end)

h.test('QBCore.Shared.* helpers and data tables resolve', function()
    assertCallableFields(QBCore.Shared, { 'Round', 'Trim', 'SplitStr', 'RandomStr', 'RandomInt' }, 'QBCore.Shared')
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
    h.assertTrue(QBCore.Shared.ChangeVehicleExtra == nil, 'ChangeVehicleExtra must not exist server-side')
    h.assertTrue(QBCore.Shared.SetDefaultVehicleExtras == nil, 'SetDefaultVehicleExtras must not exist server-side')
end)

h.test('QBCore.Shared.Locations is a live legacy view over the getter-backed registry', function()
    local viaShared = QBCore.Shared.Locations
    h.assertTrue(viaShared ~= nil, 'Shared.Locations must resolve')
    local viaRegistry = Core.registry.allShared('locations')
    h.assertTrue(#viaRegistry > 0, 'the locations registry must have seed records to compare against')
    local seedKey = viaRegistry[1].key
    h.assertTrue(viaShared[seedKey] ~= nil, 'Shared.Locations must contain the same record allShared returns')
    h.assertEqual(viaShared[seedKey], Core.registry.getShared('locations', seedKey),
        'Shared.Locations must contain the record returned by the registry getter')
    Core.registry.registerShared('locations', 'runtime_location', { key = 'runtime_location', label = 'Runtime' })
    h.assertTrue(viaShared.runtime_location ~= nil,
        'an already-captured legacy view must refresh when a record is registered at runtime')
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
    local before = QBCore.Shared.VehicleHashes
    h.assertTrue(before[GetHashKey('newcar')] == nil, 'newcar must not be registered yet')
    local ok = Core.registry.registerShared('vehicles', 'newcar', { model = 'newcar', name = 'New Car', brand = 'Test', price = 1 })
    h.assertTrue(ok, 'registerShared must succeed')
    local after = QBCore.Shared.VehicleHashes
    h.assertTrue(after == before, 'VehicleHashes must stay the SAME cached table reference')
    h.assertTrue(after[GetHashKey('newcar')] ~= nil, 'VehicleHashes must include a vehicle registered AFTER the first read')
    h.assertEqual(after[GetHashKey('newcar')].name, 'New Car')
end)

h.test('GetSharedItems/Vehicles/Jobs/Gangs/Weapons exports exist and return the right data', function()
    local exportHandlers = {}
    for _, name in ipairs({ 'GetSharedItems', 'GetSharedVehicles', 'GetSharedJobs', 'GetSharedGangs', 'GetSharedWeapons' }) do
        TriggerEvent(('__cfx_export_qb-core_%s'):format(name), function(fn) exportHandlers[name] = fn end)
    end
    h.assertTrue(type(exportHandlers.GetSharedItems) == 'function', 'GetSharedItems export must be registered')
    h.assertTrue(exportHandlers.GetSharedItems().water_bottle ~= nil, 'GetSharedItems must return the Items namespace')
    h.assertTrue(exportHandlers.GetSharedVehicles().sultan ~= nil, 'GetSharedVehicles must return the Vehicles namespace')
    h.assertTrue(exportHandlers.GetSharedWeapons() ~= nil, 'GetSharedWeapons must return the Weapons namespace')

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
    local exportHandlers = {}
    TriggerEvent('__cfx_export_qb-core_GetShared', function(fn) exportHandlers.GetShared = fn end)
    h.assertTrue(type(exportHandlers.GetShared) == 'function', 'GetShared export must be registered')

    local lower = exportHandlers.GetShared('items')
    h.assertTrue(lower ~= nil, "GetShared('items') must resolve the same as GetShared('Items')")
    h.assertTrue(lower.water_bottle ~= nil, 'the lowercase call must return the real Items namespace, not an empty table')

    h.assertEqual(exportHandlers.GetShared('Items'), lower, 'PascalCase must still resolve to the exact same table')
    h.assertTrue(exportHandlers.GetShared('items', 'water_bottle') ~= nil, 'the two-arg (namespace, item) form must also honour the casing fallback')

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
        'Notify', 'HasItem', 'AddRep', 'RemoveRep', 'GetRep', 'AddMethod', 'AddField', 'UpdateClient',
    }, 'Player.Functions')
    h.assertEqual(Player.PlayerData.citizenid, 'CID1', 'PlayerData wired through')
end)

h.test('every Player.Functions.* method is also directly callable on Player itself, matching real qb-core', function()
    local data = CoreInternal.player.freshData('CID-mirror', 'license:mirror', 2, { firstname = 'M', lastname = 'Irror' })
    Core.player.login(2, 'CID-mirror', data)
    local Player = QBCore.Functions.GetPlayer(2)

    assertCallableFields(Player, {
        'SetJob', 'SetGang', 'SetJobDuty', 'SetJobData', 'SetGangData',
        'AddMoney', 'RemoveMoney', 'SetMoney', 'GetMoney',
        'AddItem', 'RemoveItem', 'GetItemByName', 'GetItemsByName', 'GetItemBySlot',
        'ClearInventory', 'SetInventory', 'SetCreditCard',
        'SetMetaData', 'GetMetaData', 'SetCharInfo', 'SetPlayerData', 'UpdatePlayerData',
        'Save', 'Logout', 'GetName',
        'Notify', 'HasItem', 'AddRep', 'RemoveRep', 'GetRep', 'AddMethod', 'AddField', 'UpdateClient',
    }, 'Player (direct, no .Functions.)')

    local before = Player.GetMoney('cash')
    Player.AddMoney('cash', 250, 'mirror-test')
    h.assertEqual(Player.GetMoney('cash'), before + 250, 'a direct dot-call must route through the same funnel as Player.Functions.AddMoney')

    Player.SetMetaData('bloodtype', 'AB-')
    h.assertEqual(Player.GetMetaData('bloodtype'), 'AB-', 'a direct dot-call SetMetaData must actually persist')
end)

h.test('a Player.Functions call routes through the funnel (AddMoney changes balance)', function()
    local Player = QBCore.Functions.GetPlayer(1)
    local before = Player.Functions.GetMoney('cash')
    Player.Functions.AddMoney('cash', 500, 'test')
    h.assertEqual(Player.Functions.GetMoney('cash'), before + 500)
end)

h.test('AddPlayerMethod/AddPlayerField extend selected live player objects', function()
    local player = QBCore.Functions.GetPlayer(1)
    local custom = function() return 'custom-result' end
    h.assertTrue(QBCore.Functions.AddPlayerMethod(1, 'CustomMethod', custom))
    h.assertEqual(player.Functions.CustomMethod(), 'custom-result')
    h.assertEqual(player.CustomMethod(), 'custom-result')
    h.assertTrue(QBCore.Functions.AddPlayerField(1, 'CustomField', 42))
    h.assertEqual(player.CustomField, 42)
end)

h.test('logout clears both legacy caches even when a later unload listener reads the character', function()
    local function login(cid)
        local data = CoreInternal.player.freshData(cid, 'license:cache-test', 1, { firstname = 'Cache', lastname = 'Test' })
        h.assertTrue(Core.player.login(6, cid, data))
    end
    login('CID-cache-old')
    local old = QBCore.Functions.GetPlayer(6)
    h.assertEqual(QBCore.Functions.GetPlayerByCitizenId('CID-cache-old'), old)

    local readDuringUnload, listening = false, true
    AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
        if not listening or src ~= 6 or not CoreInternal.player.handle(src) then return end
        readDuringUnload = true
        h.assertEqual(QBCore.Functions.GetPlayer(src).PlayerData.citizenid, 'CID-cache-old', 'unload retains character reads')
        h.assertEqual(QBCore.Functions.GetPlayerByCitizenId('CID-cache-old').PlayerData.citizenid, 'CID-cache-old')
    end)

    h.assertTrue(Core.player.logout(6))
    listening = false
    h.assertTrue(readDuringUnload, 'the listener reads after compat cache cleanup')
    h.assertEqual(QBCore.Players[6], nil, 'the source cache must stay empty without another getter call')
    h.assertEqual(QBCore.PlayersByCitizenId['CID-cache-old'], nil, 'the citizenid cache must stay empty')
    h.assertEqual(QBCore.Functions.GetPlayer(6), nil)
    h.assertEqual(QBCore.Functions.GetPlayerByCitizenId('CID-cache-old'), nil)
    h.assertEqual(QBCore.Functions.GetQBPlayers()[6], nil)

    login('CID-cache-new')
    local current = QBCore.Functions.GetPlayer(6)
    h.assertTrue(current ~= old, 'a replacement character receives its own wrapper')
    h.assertEqual(current.PlayerData.citizenid, 'CID-cache-new')
    h.assertEqual(QBCore.Functions.GetPlayerByCitizenId('CID-cache-new'), current)
    h.assertEqual(QBCore.Functions.GetPlayerByCitizenId('CID-cache-old'), nil)
    h.assertEqual(QBCore.PlayersByCitizenId['CID-cache-old'], nil)

    Core.player.dropPlayer(6, 'cache test')
    h.assertEqual(QBCore.Players[6], nil, 'drop clears the source cache')
    h.assertEqual(QBCore.PlayersByCitizenId['CID-cache-new'], nil, 'drop clears the citizenid cache')
    h.assertEqual(QBCore.Functions.GetPlayer(6), nil)
    h.assertEqual(QBCore.Functions.GetPlayerByCitizenId('CID-cache-new'), nil)
end)

h.test('legacy getters reject stale cache entries using the authoritative player handle', function()
    local data = CoreInternal.player.freshData('CID-stale-old', 'license:stale-test', 1, { firstname = 'Stale', lastname = 'Old' })
    h.assertTrue(Core.player.login(7, 'CID-stale-old', data))
    local old = QBCore.Functions.GetPlayer(7)
    h.assertTrue(Core.player.logout(7))

    QBCore.Players[7] = old
    QBCore.PlayersByCitizenId['CID-stale-old'] = old
    h.assertEqual(QBCore.Functions.GetPlayer(7), nil, 'a cached wrapper is not an online character')
    h.assertEqual(QBCore.Players[7], nil)
    QBCore.PlayersByCitizenId['CID-stale-old'] = old
    h.assertEqual(QBCore.Functions.GetPlayerByCitizenId('CID-stale-old'), nil)
    h.assertEqual(QBCore.PlayersByCitizenId['CID-stale-old'], nil)
    h.assertEqual(QBCore.Functions.GetPlayerByCitizenId(nil), nil, 'nil citizenid preserves the legacy nil result')

    data = CoreInternal.player.freshData('CID-stale-new', 'license:stale-test', 2, { firstname = 'Stale', lastname = 'New' })
    h.assertTrue(Core.player.login(7, 'CID-stale-new', data))
    QBCore.Players[7] = old
    QBCore.PlayersByCitizenId['CID-stale-old'] = old
    h.assertEqual(QBCore.Functions.GetPlayer(7).PlayerData.citizenid, 'CID-stale-new', 'source lookup refreshes a previous identity')
    h.assertEqual(QBCore.Functions.GetPlayerByCitizenId('CID-stale-old'), nil)
    h.assertEqual(QBCore.Functions.GetPlayerByCitizenId('CID-stale-new').PlayerData.citizenid, 'CID-stale-new')
    Core.player.dropPlayer(7, 'cache test')
end)

h.test('CreatePlayer(PlayerData, true) returns a full offline Player interface', function()
    local internal = CoreInternal.player.freshData('CID-offline', 'license:offline', 3,
        { firstname = 'Off', lastname = 'Line' })
    local legacy = Core.compat.toLegacyPlayerData(internal)
    local player = QBCore.Player.CreatePlayer(legacy, true)
    h.assertTrue(player.Offline)
    h.assertEqual(player.Functions.GetName(), 'Off Line')
    h.assertEqual(player.PlayerData.job.grade.level, 0)
    h.assertTrue(type(player.Functions.SetMetaData) == 'function')
    h.assertTrue(type(player.Save) == 'function')
    player.Functions.SetMetaData('callsign', 'OFF')
    h.assertEqual(player.Functions.GetMetaData('callsign'), 'OFF')
    player.PlayerData.metadata = nil
    player.Functions.AddRep('crafting', 2)
    h.assertEqual(player.Functions.GetRep('crafting'), 2, 'offline reputation must initialize missing metadata')
    local callable = setmetatable({}, { __call = function() return 'offline-custom' end })
    h.assertTrue(player.Functions.AddMethod('OfflineCustom', callable))
    h.assertEqual(player.OfflineCustom(), 'offline-custom')
end)

h.test('QBCore:Server:OnPlayerUpdated fans out to legacy-shaped OnJobUpdate + OnGangUpdate', function()
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

h.test('QBCore.Functions.GetPermission returns an upstream-shaped permission set', function()
    local none = QBCore.Functions.GetPermission(1)
    h.assertTrue(type(none) == 'table', 'GetPermission must always return a table')
    h.assertFalse(none.admin, 'an ungranted player holds no permissions')

    handle.setAce(1, 'group.admin', true)
    local perms = QBCore.Functions.GetPermission(1)
    h.assertTrue(perms.admin, 'a granted group must be keyed true')
    h.assertFalse(perms.god, 'ungranted groups must be absent, not inherited')
    h.assertEqual(Core.permissions.getPermission(1), 'admin', 'the native API still reports the highest level as a string')
    handle.setAce(1, 'group.admin', nil)
end)

h.test('QBCore.Functions.HasPermission accepts a permission array', function()
    handle.setAce(1, 'group.god', true)
    h.assertTrue(QBCore.Functions.HasPermission(1, { 'admin', 'god' }), 'any match in the array passes')
    h.assertFalse(QBCore.Functions.HasPermission(1, { 'admin', 'mod' }), 'no match fails')
    h.assertTrue(QBCore.Functions.HasPermission(1, 'god'), 'the string form still works')
    handle.setAce(1, 'group.god', nil)
end)

h.test('legacy server vehicle spawns use one bounded lifecycle and fail closed', function()
    local inVehicle, deleted = 0, {}
    _G.CreateVehicle = function() return 401 end
    _G.DoesEntityExist = function(entity) return entity == 401 end
    _G.NetworkGetEntityOwner = function() return 1 end
    _G.GetVehiclePedIsIn = function() return inVehicle end
    _G.TaskWarpPedIntoVehicle = function(_, vehicle) inVehicle = vehicle end
    _G.DeleteEntity = function(entity) deleted[#deleted + 1] = entity end

    local vehicle = QBCore.Functions.SpawnVehicle(1, 123, { x = 1, y = 2, z = 3, w = 90 }, true)
    h.assertEqual(vehicle, 401)
    h.assertEqual(inVehicle, 401, 'warp should settle through the shared bounded helper')
    h.assertEqual(#deleted, 0)

    _G.CreateVehicle = function() return 402 end
    _G.DoesEntityExist = function(entity) return entity == 402 end
    _G.NetworkGetEntityOwner = function() return 99 end
    local failed = QBCore.Functions.SpawnVehicle(1, 123, { x = 1, y = 2, z = 3 }, false)
    h.assertFalse(failed, 'an entity that never acquires the expected owner must not escape')
    h.assertEqual(deleted[#deleted], 402, 'a failed network spawn should be rolled back')
end)

h.test('legacy server setter shares existence and warp validation', function()
    local inVehicle = 0
    _G.CreateVehicleServerSetter = function() return 403 end
    _G.DoesEntityExist = function(entity) return entity == 403 end
    _G.GetVehiclePedIsIn = function() return inVehicle end
    _G.TaskWarpPedIntoVehicle = function(_, vehicle) inVehicle = vehicle end
    _G.DeleteEntity = function() error('successful setter spawn must not be deleted') end

    local vehicle = QBCore.Functions.CreateVehicle(1, 123, 'automobile', { x = 1, y = 2, z = 3 }, true)
    h.assertEqual(vehicle, 403)
    h.assertEqual(inVehicle, 403)
end)

h.test('player bucket setters notify after the native and legacy map update', function()
    local buckets, notifications = {}, {}
    local previousIdentifiers = Core.identity.getIdentifiers
    Core.identity.getIdentifiers = function(src) return { license = 'license:' .. src } end
    local previousPlayerSetter = SetPlayerRoutingBucket
    local previousGetter = GetPlayerRoutingBucket
    local previousEntitySetter = SetEntityRoutingBucket
    SetPlayerRoutingBucket = function(src, bucket) buckets[src] = bucket end
    GetPlayerRoutingBucket = function(src) return buckets[src] end
    SetEntityRoutingBucket = function() end
    AddEventHandler('qbvoice:server:bucketChanged', function(src)
        local license = QBCore.Functions.GetIdentifier(src, 'license')
        notifications[#notifications + 1] = {
            src = src, native = GetPlayerRoutingBucket(src), map = QBCore.Player_Buckets[license].bucket,
        }
    end)
    h.assertEqual(QBCore.Functions.SetPlayerBucket(1, 12), true)
    h.assertEqual(#notifications, 1)
    h.assertEqual(notifications[1].src, 1)
    h.assertEqual(notifications[1].native, 12)
    h.assertEqual(notifications[1].map, 12)
    h.assertEqual(QBCore.Functions.SetPlayerBucket(1, 0), true)
    h.assertEqual(#notifications, 2)
    h.assertEqual(notifications[2].native, 0)
    h.assertEqual(notifications[2].map, 0)
    h.assertEqual(QBCore.Functions.SetPlayerBucket(nil, 12), false)
    h.assertEqual(QBCore.Functions.SetPlayerBucket(1, nil), false)
    h.assertEqual(QBCore.Functions.SetEntityBucket(500, 12), true)
    h.assertEqual(#notifications, 2, 'rejected and entity setters do not notify')
    SetPlayerRoutingBucket = function() error('controlled native failure') end
    h.assertThrows(function() QBCore.Functions.SetPlayerBucket(1, 12) end)
    h.assertEqual(#notifications, 2, 'failed native does not notify')
    SetPlayerRoutingBucket, GetPlayerRoutingBucket, SetEntityRoutingBucket = previousPlayerSetter, previousGetter, previousEntitySetter
    Core.identity.getIdentifiers = previousIdentifiers
end)

h.report('compat')
