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

h.test('QBCore.Shared.* helpers and data tables resolve', function()
    assertCallableFields(QBCore.Shared, { 'Round', 'Trim', 'SplitStr', 'RandomStr', 'RandomInt' }, 'QBCore.Shared')
    -- Data tables resolve lazily via the metatable to the materialised registries.
    h.assertTrue(QBCore.Shared.Items ~= nil, 'Shared.Items resolves')
    h.assertTrue(QBCore.Shared.Items.water_bottle ~= nil, 'Shared.Items has a seed item')
    h.assertTrue(QBCore.Shared.Jobs ~= nil and QBCore.Shared.Jobs.police ~= nil, 'Shared.Jobs resolves')
    h.assertTrue(QBCore.Shared.Vehicles ~= nil and QBCore.Shared.Gangs ~= nil and QBCore.Shared.Weapons ~= nil)
end)

h.test('QBCore.Commands.Add and QBCore.Debug exist', function()
    h.assertTrue(type(QBCore.Commands.Add) == 'function')
    h.assertTrue(type(QBCore.Debug) == 'function')
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

h.report('compat')
