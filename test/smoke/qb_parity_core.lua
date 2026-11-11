-- qb-core parity items: offline GetPlayerByLicense, Commands.Add/List shape,
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

local loadedPayloads = {}
AddEventHandler('QBCore:Server:PlayerLoaded', function(player) loadedPayloads[#loadedPayloads + 1] = player end)

dofile('compat/server/qb-core.lua')
dofile('compat/server/qb-core-events.lua')

local licenses = { [1] = 'license:one', [2] = 'license:two' }
Core.identity.getIdentifiers = function(src) return { license = licenses[src] } end
local F = QBCore.Functions

local function newData(cid, license)
    local data = CoreInternal.player.freshData(cid, license, 1, { firstname = 'Ann', lastname = 'Lee' })
    data.metadata.bloodtype, data.metadata.fingerprint, data.metadata.walletid = nil, nil, nil
    return data
end

assert(Core.player.login(1, 'PAR1', newData('PAR1', 'license:one')))

local function clientCount(name, target)
    local n = 0
    for _, e in ipairs(handle.clientEvents) do if e.name == name and e.target == target then n = n + 1 end end
    return n
end

h.test('QBCore:Server:PlayerLoaded carries the stock Player wrapper', function()
    local payload = loadedPayloads[1]
    h.assertTrue(payload.Functions ~= nil and payload.PlayerData ~= nil, 'wrapper needs .Functions and .PlayerData')
    h.assertEqual(payload.PlayerData.citizenid, 'PAR1')
    h.assertEqual(payload, F.GetPlayer(1), 'the payload is the same object QBCore.Players holds')
    h.assertEqual(payload.PlayerData.job.grade.level, 0, 'legacy zero-based grade')
end)

h.test('QBCore:Client:OnPlayerLoaded fires at login by default; the server event is then a no-op', function()
    h.assertEqual(clientCount('QBCore:Client:OnPlayerLoaded', 1), 1)
    handle.fireEvent('QBCore:Server:OnPlayerLoaded', 1)
    h.assertEqual(clientCount('QBCore:Client:OnPlayerLoaded', 1), 1)
end)

h.test('deferClientPlayerLoaded moves the client event to QBCore:Server:OnPlayerLoaded, once per login', function()
    Config.compat.deferClientPlayerLoaded = true
    assert(Core.player.login(2, 'PAR2', newData('PAR2', 'license:two')))
    h.assertEqual(clientCount('QBCore:Client:OnPlayerLoaded', 2), 0)
    handle.fireEvent('QBCore:Server:OnPlayerLoaded', 9)
    h.assertEqual(clientCount('QBCore:Client:OnPlayerLoaded', 9), 0, 'unknown sources are ignored')
    handle.fireEvent('QBCore:Server:OnPlayerLoaded', 2)
    handle.fireEvent('QBCore:Server:OnPlayerLoaded', 2)
    h.assertEqual(clientCount('QBCore:Client:OnPlayerLoaded', 2), 1)
    Config.compat.deferClientPlayerLoaded = false
end)

h.test('GetPlayerByLicense falls back to the offline lookup like stock', function()
    local queries = {}
    local oldSingle, oldLoad = Kora.sql.single, Core.persistence._load
    Kora.sql.single = function(sql, params)
        queries[#queries + 1] = params[1]
        return params[1] == 'license:gone' and { citizenid = 'OFF1' } or nil
    end
    Core.persistence._load = function(cid)
        if cid ~= 'OFF1' then return nil end
        return newData('OFF1', 'license:gone')
    end
    local online = F.GetPlayerByLicense('license:one')
    h.assertEqual(online.PlayerData.citizenid, 'PAR1')
    h.assertEqual(#queries, 0, 'an online match never touches the database')
    local offline = F.GetPlayerByLicense('license:gone')
    h.assertEqual(offline.Offline, true)
    h.assertEqual(offline.PlayerData.citizenid, 'OFF1')
    h.assertTrue(offline.Functions.GetName() == 'Ann Lee')
    h.assertEqual(F.GetPlayerByLicense('license:none'), nil)
    h.assertEqual(F.GetPlayerByLicense(nil), nil)
    h.assertEqual(QBCore.Player.GetPlayerByLicense('license:gone').PlayerData.citizenid, 'OFF1')
    h.assertEqual(F.GetOfflinePlayerByLicense('license:gone').PlayerData.citizenid, 'OFF1')
    Kora.sql.single, Core.persistence._load = oldSingle, oldLoad
end)

h.test('GetName uses the character name, not the account name', function()
    Core.player.setPath(1, { 'name' }, 'Steam Account Name')
    h.assertEqual(F.GetPlayer(1).Functions.GetName(), 'Ann Lee')
end)

h.test('Commands.Add keeps the stock List shape and lower-cases names', function()
    local cb = function() end
    QBCore.Commands.Add('MyCmd', 'help', { { name = 'id', help = 'target' } }, true, cb, 'Admin', 'mod')
    local entry = QBCore.Commands.List.mycmd
    h.assertTrue(entry ~= nil, 'key is lower-cased')
    h.assertEqual(entry.name, 'mycmd')
    h.assertEqual(entry.arguments[1].name, 'id')
    h.assertEqual(entry.callback, cb)
    h.assertEqual(entry.argsrequired, true)
    h.assertEqual(type(entry.permission), 'table')
    h.assertEqual(entry.permission[1], 'admin'); h.assertEqual(entry.permission[2], 'mod')
    local aces = {}
    for _, c in ipairs(handle.executeCommandCalls) do aces[c] = true end
    h.assertTrue(aces['add_ace kora_core.admin command.MyCmd allow'])
    h.assertTrue(aces['add_ace kora_core.mod command.MyCmd allow'])
    QBCore.Commands.Add('plain', 'h', {}, false, cb)
    h.assertEqual(QBCore.Commands.List.plain.permission, 'user')
    h.assertTrue(QBCore.Commands.IgnoreList.god and QBCore.Commands.IgnoreList.user)
end)

h.test('QBCore:CallCommand tells the caller about missing access and missing arguments', function()
    local ran = 0
    QBCore.Commands.Add('needsargs', 'h', { { name = 'a' }, { name = 'b' } }, true, function() ran = ran + 1 end, 'user')
    local function lastNotify() return handle.lastClient('QBCore:Notify') end
    handle.fireEvent('QBCore:CallCommand', 1, 'needsargs', { 'x', 'y' })
    h.assertEqual(ran, 0)
    h.assertEqual(lastNotify().args[1], 'No access to this command')
    handle.setAce(1, 'command.needsargs', true)
    handle.fireEvent('QBCore:CallCommand', 1, 'needsargs', { 'x' })
    h.assertEqual(ran, 0)
    h.assertEqual(lastNotify().args[1], 'All arguments must be filled out!')
    handle.fireEvent('QBCore:CallCommand', 1, 'needsargs', { 'x', 'y' })
    h.assertEqual(ran, 1)
end)

h.test('root optin defaults to true and ToggleOptin flips it for admins only', function()
    local p = F.GetPlayer(1)
    h.assertEqual(p.PlayerData.optin, true)
    F.ToggleOptin(1)
    h.assertEqual(F.GetPlayer(1).PlayerData.optin, true, 'non-admins cannot toggle')
    handle.setAce(1, 'group.admin', true)
    handle.setAce(1, 'kora_core.admin', true)
    F.ToggleOptin(1)
    h.assertEqual(F.GetPlayer(1).PlayerData.optin, false)
    h.assertFalse(F.IsOptin(1))
    h.assertFalse(Core.permissions.isOptin(1), 'the native check honours the opt-out')
    F.ToggleOptin(1)
    h.assertEqual(F.GetPlayer(1).PlayerData.optin, true)
    h.assertTrue(F.IsOptin(1))
    h.assertEqual(Core.metadata.getMetaData(1, 'optin'), nil, 'no metadata.optin is written any more')
end)

h.test('position exposes w next to h, and legacy writes store h', function()
    local position = F.GetPlayer(1).PlayerData.position
    h.assertEqual(position.w, position.h)
    local internal = Core.compat.fromLegacyPlayerData({ position = { x = 1, y = 2, z = 3, w = 90.0 } })
    h.assertEqual(internal.position.h, 90.0)
    h.assertEqual(internal.position.w, nil)
end)

h.test('bloodtype/fingerprint/walletid are derived per citizen: stable, well-formed, not persisted', function()
    local md = F.GetPlayer(1).PlayerData.metadata
    local again = F.GetPlayer(1).Functions.GetPlayerData().metadata
    h.assertEqual(md.fingerprint, again.fingerprint)
    h.assertEqual(md.walletid, again.walletid)
    h.assertTrue(md.fingerprint:match('^%a%a%d%d%d%a%d%d%a%a%a%d%d%d%d$') ~= nil, md.fingerprint)
    h.assertTrue(md.walletid:match('^QB%-%d%d%d%d%d%d%d%d$') ~= nil, md.walletid)
    local known = {}
    for _, t in ipairs(QBCore.Config.Player.Bloodtypes) do known[t] = true end
    h.assertTrue(known[md.bloodtype])
    h.assertEqual(Core.player.getPlayerData(1, { 'metadata' }).fingerprint, nil, 'the authoritative metadata is untouched')
    local other = Core.compat.toLegacyPlayerData(newData('PAR2', 'license:two')).metadata
    h.assertEqual(other.fingerprint, Core.compat.toLegacyPlayerData(newData('PAR2', 'license:two')).metadata.fingerprint)
    h.assertTrue(other.fingerprint ~= md.fingerprint)
end)

h.test('charinfo gains a stable stock-format account and keeps stored values', function()
    local ci = F.GetPlayer(1).PlayerData.charinfo
    h.assertTrue(ci.account:match('^US0%dQBCore%d+$') ~= nil, ci.account)
    h.assertEqual(ci.account, F.GetPlayer(1).Functions.GetPlayerData().charinfo.account)
    h.assertEqual(ci.firstname, 'Ann')
    h.assertEqual(ci.nationality, 'USA')
    F.GetPlayer(1).Functions.SetCharInfo('account', 'US01QBCore1')
    h.assertEqual(F.GetPlayer(1).PlayerData.charinfo.account, 'US01QBCore1')
end)

h.test('PlayerData.items is always a table in the compat view', function()
    h.assertEqual(type(F.GetPlayer(1).PlayerData.items), 'table')
end)

h.test('ToggleDuty tells the player and fires the duty events', function()
    h.assertTrue(F.GetPlayer(1).Functions.SetJob('police', 0))
    local before = clientCount('QBCore:Notify', 1)
    handle.fireEvent('QBCore:ToggleDuty', 1)
    h.assertEqual(clientCount('QBCore:Notify', 1), before + 1)
    local text = handle.lastClient('QBCore:Notify').args[1]
    h.assertTrue(text == 'You are now on duty!' or text == 'You are now off duty!', text)
end)

h.test('CanUseItem returns the stock { func, resource } record', function()
    local cb = function() end
    QBCore.Functions.CreateUseableItem('parity_item', cb)
    local record = QBCore.Functions.CanUseItem('parity_item')
    h.assertEqual(record.func, cb)
    h.assertTrue(record.resource ~= nil)
end)

h.report('qb_parity_core')
