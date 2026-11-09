local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('shared/items.lua'); dofile('shared/jobs.lua'); dofile('shared/gangs.lua')
dofile('shared/vehicles.lua'); dofile('shared/weapons.lua'); dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua'); dofile('modules/registry/server.lua')
dofile('modules/player/shared.lua')
dofile('modules/replication/server.lua'); dofile('modules/persistence/server.lua')
dofile('modules/player/server.lua'); dofile('modules/money/server.lua')
dofile('modules/jobs/server.lua'); dofile('modules/metadata/server.lua')
dofile('modules/inventory/shared.lua'); dofile('modules/inventory/server.lua')
dofile('modules/inventory/gateway.lua')
dofile('modules/multichar/server.lua'); dofile('modules/permissions/server.lua')
dofile('modules/commands/server.lua'); dofile('modules/logging/server.lua')
dofile('compat/shared/coreobject.lua')
dofile('compat/server/qb-core.lua')
dofile('compat/server/qb-core-events.lua')
dofile('shared/locale.lua')

function SetPlayerRoutingBucket() end

local licenses = { [1] = 'license:one', [2] = 'license:two' }
Core.identity.getIdentifiers = function(src) return { license = licenses[src], discord = 'discord:123' } end
local F = QBCore.Functions

local function newData(cid, license)
    return CoreInternal.player.freshData(cid, license, 1, { firstname = 'Ann', lastname = 'Lee' })
end

assert(Core.player.login(1, 'PB1', newData('PB1', 'license:one')))

local function clientCount(name, target)
    local n = 0
    for _, e in ipairs(handle.clientEvents) do if e.name == name and e.target == target then n = n + 1 end end
    return n
end

h.test('identifier lookups accept prefixed and bare forms', function()
    h.assertEqual(F.GetSource('license:one'), 1)
    h.assertEqual(F.GetSource('one'), 1)
    h.assertEqual(F.GetSource('license:nobody'), 0)
    h.assertEqual(F.GetPlayer('one').PlayerData.citizenid, 'PB1')
    h.assertEqual(F.GetPlayerByLicense('one').PlayerData.citizenid, 'PB1')
    h.assertTrue(F.IsLicenseInUse('one'))
    h.assertTrue(F.IsLicenseInUse('license:one'))
    h.assertTrue(not F.IsLicenseInUse('two'))
    h.assertEqual(F.GetIdentifier(1, 'license'), 'license:one', 'GetIdentifier return form is unchanged')
end)

h.test('offline license lookup queries both identifier forms', function()
    local seen
    local oldSingle, oldLoad = Kora.sql.single, Core.persistence._load
    Kora.sql.single = function(_, params) seen = params; return { citizenid = 'OFFB' } end
    Core.persistence._load = function() return newData('OFFB', 'license:gone') end
    h.assertEqual(F.GetOfflinePlayerByLicense('gone').PlayerData.citizenid, 'OFFB')
    h.assertEqual(seen[1], 'license:gone')
    h.assertEqual(seen[2], 'gone')
    h.assertEqual(F.GetOfflinePlayerByLicense('license:gone').PlayerData.citizenid, 'OFFB')
    h.assertEqual(seen[2], 'gone')
    Kora.sql.single, Core.persistence._load = oldSingle, oldLoad
end)

h.test('IsPlayerBanned: NULL expire is permanent, past expiry clears, both forms queried', function()
    local oldSingle, oldQuery = Kora.sql.single, Kora.sql.query
    local params, deleted
    Kora.sql.query = function(sql, p) deleted = p[1] end
    Kora.sql.single = function(_, p) params = p; return { id = 5, reason = 'cheating', expire = nil } end
    local banned, msg = F.IsPlayerBanned(1)
    h.assertTrue(banned)
    h.assertTrue(msg:find('permanent', 1, true) ~= nil and msg:find('cheating', 1, true) ~= nil)
    h.assertEqual(params[1], 'license:one'); h.assertEqual(params[2], 'one')
    Kora.sql.single = function() return { id = 6, reason = 'x', expire = os.time() + 3600 } end
    h.assertTrue(F.IsPlayerBanned(1))
    Kora.sql.single = function() return { id = 7, reason = 'x', expire = os.time() - 5 } end
    h.assertEqual(F.IsPlayerBanned(1), false)
    h.assertEqual(deleted, 7)
    Kora.sql.single = function() return nil end
    h.assertEqual(F.IsPlayerBanned(1), false)
    Kora.sql.single, Kora.sql.query = oldSingle, oldQuery
end)

h.test('GetDatabaseInfo handles url and key=value connection strings', function()
    local convar = ''
    local old = _G.GetConvar
    _G.GetConvar = function(name, d) if name == 'mysql_connection_string' then return convar end return d end
    h.assertEqual(F.GetDatabaseInfo().exists, false)
    convar = 'mysql://u:p@localhost/mydb?charset=utf8'
    h.assertEqual(F.GetDatabaseInfo().database, 'mydb')
    convar = 'server=localhost;database=otherdb;userid=u;password=p'
    local info = F.GetDatabaseInfo()
    h.assertTrue(info.exists); h.assertEqual(info.database, 'otherdb')
    convar = 'server=localhost;userid=u'
    h.assertEqual(F.GetDatabaseInfo().exists, false)
    _G.GetConvar = old
end)

h.test('drop fires the legacy events before eviction, then qbcore:server:playerDropped', function()
    assert(Core.player.login(2, 'PB2', newData('PB2', 'license:two')))
    local order, sawPlayer = {}, {}
    AddEventHandler('QBCore:Server:PlayerDropped', function(src)
        order[#order + 1] = 'legacy'; sawPlayer.dropped = F.GetPlayer(src) ~= nil
    end)
    AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
        if src == 2 then sawPlayer.unload = F.GetPlayer(src) ~= nil end
    end)
    AddEventHandler('qbcore:server:playerDropped', function(src)
        order[#order + 1] = 'kora'; sawPlayer.after = F.GetPlayer(src) == nil
    end)
    Core.player.dropPlayer(2, 'bye')
    h.assertEqual(order[1], 'legacy'); h.assertEqual(order[2], 'kora')
    h.assertTrue(sawPlayer.dropped and sawPlayer.unload, 'GetPlayer works inside legacy handlers')
    h.assertTrue(sawPlayer.after, 'player is gone by the kora event')
end)

h.test('AddPermission refreshes the command list', function()
    local refreshed
    local old = QBCore.Commands.Refresh
    QBCore.Commands.Refresh = function(src) refreshed = src end
    Core.identity.primary = function() return 'license:one' end
    h.assertTrue(F.AddPermission(1, 'admin'))
    h.assertEqual(refreshed, 1)
    QBCore.Commands.Refresh = old
end)

h.test('AddMoney/RemoveMoney accept zero, reject negative, lower-case the type', function()
    local P = F.GetPlayer(1)
    local before = P.Functions.GetMoney('cash')
    h.assertTrue(P.Functions.AddMoney('cash', 0, 'free'))
    h.assertTrue(P.Functions.RemoveMoney('cash', 0, 'free'))
    h.assertEqual(P.Functions.GetMoney('cash'), before)
    h.assertTrue(not P.Functions.AddMoney('cash', -5))
    h.assertTrue(not P.Functions.RemoveMoney('cash', -5))
    h.assertTrue(not P.Functions.AddMoney('nonsense', 0))
    h.assertTrue(P.Functions.AddMoney('CASH', 10, 'upper'))
    h.assertEqual(P.Functions.GetMoney('cash'), before + 10)
    h.assertTrue(P.Functions.RemoveMoney('Cash', 10, 'upper'))
    h.assertEqual(P.Functions.GetMoney('cash'), before)
end)

h.test('Shared.Round returns an integer without decimals', function()
    h.assertEqual(math.type(QBCore.Shared.Round(5.4)), 'integer')
    h.assertEqual(QBCore.Shared.Round(5.5), 6)
    h.assertEqual(QBCore.Shared.Round(5.456, 2), 5.46)
end)

h.test('callback tables exist and GetCoreObject filters return them', function()
    h.assertEqual(type(QBCore.ServerCallbacks), 'table')
    h.assertEqual(type(QBCore.ClientCallbacks), 'table')
    local getCoreObject
    TriggerEvent('__cfx_export_qb-core_GetCoreObject', function(fn) getCoreObject = fn end)
    h.assertTrue(type(getCoreObject) == 'function')
    local filtered = getCoreObject({ 'ServerCallbacks', 'ClientCallbacks' })
    h.assertEqual(filtered.ServerCallbacks, QBCore.ServerCallbacks)
    h.assertEqual(filtered.ClientCallbacks, QBCore.ClientCallbacks)
end)

h.test('SetPlayerBucket sets the instance state bag', function()
    h.assertTrue(F.SetPlayerBucket(1, 7))
    h.assertEqual(Player(1).state.instance, 7)
end)

h.test('setJobDuty fires OnJobUpdate and OnPlayerUpdated', function()
    h.assertTrue(F.GetPlayer(1).Functions.SetJob('police', 0))
    local events = {}
    AddEventHandler('QBCore:Server:OnJobUpdate', function(src) events[#events + 1] = 'job' end)
    AddEventHandler('QBCore:Server:OnPlayerUpdated', function(src, key) events[#events + 1] = key end)
    h.assertTrue(Core.jobs.setJobDuty(1, true))
    h.assertEqual(events[1], 'job'); h.assertEqual(events[2], 'job')
end)

h.test('fallback hasItem accepts the map form', function()
    Core.player.setPath(1, { 'items' }, {
        [1] = { name = 'bread', amount = 3, slot = 1 },
        [2] = { name = 'water', amount = 1, slot = 2 },
    })
    h.assertTrue(Core.inventory.hasItem(1, 'bread', 3))
    h.assertTrue(Core.inventory.hasItem(1, { 'bread', 'water' }))
    h.assertTrue(Core.inventory.hasItem(1, { bread = 2, water = 1 }))
    h.assertTrue(not Core.inventory.hasItem(1, { bread = 4, water = 1 }))
    h.assertTrue(not Core.inventory.hasItem(1, { bread = 1, meat = 1 }))
    h.assertTrue(Core.inventory.hasItem(1, { bread = 99 }, 2), 'an explicit amount overrides the map values')
end)

h.test('Locale API: extend/clear/replace/locale/has/delete/phrases/fallback', function()
    local l = Locale:new({ phrases = { a = { b = 'AB %{x}' }, c = 'C' } })
    h.assertEqual(l.warnOnMissing, true)
    h.assertEqual(l.phrases['a.b'], 'AB %{x}')
    h.assertEqual(l:t('a.b', { x = 1 }), 'AB 1')
    l:extend({ d = { e = 'DE' } })
    h.assertTrue(l:has('d.e')); h.assertEqual(l:t('d.e'), 'DE')
    l:delete('c'); h.assertTrue(not l:has('c'))
    l:delete({ d = { e = true } }); h.assertTrue(not l:has('d.e'))
    l:replace({ z = 'Z' })
    h.assertTrue(l:has('z') and not l:has('a.b'))
    h.assertEqual(l:locale(), nil); h.assertEqual(l:locale('fr'), 'fr')
    l:clear(); h.assertEqual(next(l.phrases), nil)
    local quiet = Locale:new({ warnOnMissing = false, phrases = { k = 'v' } })
    h.assertEqual(quiet.warnOnMissing, false)
    local withFallback = Locale:new({ warnOnMissing = false, fallbackLang = { phrases = { only = 'fb' } }, phrases = { k = 'v' } })
    h.assertEqual(withFallback:t('only'), 'fb')
    h.assertEqual(withFallback:t('k'), 'v')
    h.assertEqual(withFallback:t('missing'), 'missing')
end)

h.test('hud stress events validate, clamp, rate-limit and update the HUD', function()
    local cfg = Config.compat.stress
    F.GetPlayer(1).Functions.SetJob('unemployed', 0)
    cfg.cooldownMs = 0
    local function stress() return Core.metadata.getMetaData(1, 'stress') or 0 end
    local base = stress()
    handle.fireEvent('hud:server:GainStress', 1, 'x')
    handle.fireEvent('hud:server:GainStress', 1, -5)
    handle.fireEvent('hud:server:GainStress', 1, 0/0)
    handle.fireEvent('hud:server:GainStress', 1, 1000)
    h.assertEqual(stress(), base, 'bad amounts are ignored')
    handle.fireEvent('hud:server:GainStress', 1, 10)
    h.assertEqual(stress(), base + 10)
    h.assertEqual(handle.lastClient('hud:client:UpdateStress').args[1], base + 10)
    handle.fireEvent('hud:server:RelieveStress', 1, 100)
    h.assertEqual(stress(), 0, 'clamped at 0')
    handle.fireEvent('hud:server:GainStress', 1, 100); handle.fireEvent('hud:server:GainStress', 1, 100)
    h.assertEqual(stress(), 100, 'clamped at 100')
    handle.fireEvent('hud:server:RelieveStress', 1, 100)
    cfg.cooldownMs = 1000000
    handle.fireEvent('hud:server:GainStress', 1, 5)
    handle.fireEvent('hud:server:GainStress', 1, 5)
    h.assertTrue(stress() <= 5, 'second call inside the cooldown is dropped')
    cfg.cooldownMs = 0
    cfg.disabled = true
    local before = stress()
    handle.fireEvent('hud:server:GainStress', 1, 5)
    h.assertEqual(stress(), before)
    cfg.disabled = false
    F.GetPlayer(1).Functions.SetJob('ambulance', 0)
    handle.fireEvent('hud:server:GainStress', 1, 5)
    h.assertEqual(stress(), before, 'whitelisted job never gains stress')
    handle.fireEvent('hud:server:GainStress', 99, 5)
end)

h.test('qb-log:server:CreateLog forwards to Kora logging and is not a net event', function()
    local seen
    local old = Core.logging.logEvent
    Core.logging.logEvent = function(category, src, data) seen = { category = category, data = data } end
    TriggerEvent('qb-log:server:CreateLog', 'joinleave', 'Title', 'red', 'hello', true)
    h.assertEqual(seen.category, 'joinleave')
    h.assertEqual(seen.data.message, 'hello')
    h.assertEqual(seen.data.tagEveryone, true)
    seen = nil
    TriggerEvent('qb-log:server:CreateLog', nil, 'Title')
    h.assertEqual(seen, nil)
    Core.logging.logEvent = old
    h.assertEqual(#handle.eventHandlers['qb-log:server:CreateLog'], 1, 'registered through AddEventHandler')
end)

h.report('qb_parity_core_b')
