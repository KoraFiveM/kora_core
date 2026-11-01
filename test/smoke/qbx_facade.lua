-- qbx facade ON: the qbx_core / qbx_vehicles export surface, qbx events
-- re-emitted from kora's lifecycle/job paths, the loadInventory + isLoggedIn
-- state bags, group mapping, and SetMoney/SetPlayerData behaviour that stock
-- ox_inventory's qbx bridge depends on.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('shared/items.lua'); dofile('shared/jobs.lua'); dofile('shared/gangs.lua')
dofile('shared/vehicles.lua'); dofile('shared/weapons.lua'); dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua'); dofile('modules/registry/server.lua')
dofile('modules/player/shared.lua')
dofile('modules/replication/server.lua'); dofile('modules/persistence/server.lua')
dofile('modules/player/server.lua')
dofile('modules/money/server.lua')
dofile('modules/jobs/server.lua')
dofile('modules/metadata/server.lua')
dofile('modules/inventory/shared.lua'); dofile('modules/inventory/server.lua')
dofile('modules/permissions/server.lua')
dofile('modules/commands/server.lua')
dofile('compat/shared/coreobject.lua')
dofile('compat/server/qb-core.lua')
dofile('compat/server/qb-core-events.lua')

Config.compat.qbxFacade = true
dofile('compat/server/qbx.lua')

local PI = CoreInternal.player

local function export(identity, name)
    local fn
    TriggerEvent(('__cfx_export_%s_%s'):format(identity, name), function(cb) fn = cb end)
    return fn
end
local GetPlayer = export('qbx_core', 'GetPlayer')
local GetPlayersData = export('qbx_core', 'GetPlayersData')
local CanUseItem = export('qbx_core', 'CanUseItem')
local GetGroups = export('qbx_core', 'GetGroups')
local IsGradeBoss = export('qbx_core', 'IsGradeBoss')
local GetVehicleIdByPlate = export('qbx_vehicles', 'GetVehicleIdByPlate')

local function record(name)
    local log = {}
    AddEventHandler(name, function(...) log[#log + 1] = table.pack(...) end)
    return log
end
local loggedOut = record('qbx_core:server:playerLoggedOut')
local groupUpdates = record('qbx_core:server:onGroupUpdate')

local function clientEventsNamed(name)
    local out = {}
    for _, ev in ipairs(handle.clientEvents) do if ev.name == name then out[#out + 1] = ev end end
    return out
end

local function login(src, cid, charinfo)
    local data = PI.freshData(cid, 'license:' .. cid, 1,
        charinfo or { firstname = 'Ada', lastname = 'Lovelace', gender = 1, birthdate = '1990-01-01' })
    h.assertTrue(Core.player.login(src, cid, data))
    return data
end

h.test('every qbx export identity is published', function()
    for _, fn in ipairs({ GetPlayer, GetPlayersData, CanUseItem, GetGroups, IsGradeBoss, GetVehicleIdByPlate }) do
        h.assertEqual(type(fn), 'function')
    end
end)

h.test('exports return nothing for an unknown player', function()
    h.assertEqual(GetPlayer(99), nil)
    h.assertEqual(GetGroups(99), nil)
    h.assertEqual(#GetPlayersData(), 0)
end)

h.test('loadInventory is NOT set synchronously, then set once the login is complete', function()
    login(1, 'CID1')
    h.assertEqual(handle.playerStates[1].isLoggedIn, true, 'core sets isLoggedIn')
    h.assertEqual(handle.playerStates[1].loadInventory, nil, 'must wait for the deferred ready tick')
    handle.drainTimeouts()
    h.assertEqual(handle.playerStates[1].loadInventory, true)
    local writes = 0
    for _, w in ipairs(handle.stateWrites) do
        if w.key == 'loadInventory' then
            writes = writes + 1
            h.assertTrue(w.replicated, 'loadInventory must be a replicated bag write')
        end
    end
    h.assertEqual(writes, 1)
end)

h.test('setGroups reaches the loading client once with job + gang-less map', function()
    local sent = clientEventsNamed('qbx_core:client:setGroups')
    h.assertEqual(#sent, 1)
    h.assertEqual(sent[1].target, 1)
    h.assertEqual(sent[1].args[1].unemployed, 0)
end)

h.test('GetPlayer is QB-shaped with dot and colon method forms', function()
    local p = GetPlayer(1)
    h.assertEqual(p.PlayerData.citizenid, 'CID1')
    h.assertEqual(p.PlayerData.source, 1)
    h.assertEqual(p.PlayerData.charinfo.firstname, 'Ada')
    h.assertEqual(p.PlayerData.charinfo.gender, 1)
    h.assertEqual(p.PlayerData.charinfo.birthdate, '1990-01-01')
    h.assertEqual(type(p.PlayerData.metadata.licences), 'table')
    h.assertEqual(type(p.PlayerData.money.cash), 'number')
    for _, name in ipairs({ 'SetPlayerData', 'GetMoney', 'SetMoney', 'SetMetaData' }) do
        h.assertEqual(type(p.Functions[name]), 'function', 'Functions.' .. name)
        h.assertEqual(type(p[name]), 'function', 'method ' .. name)
    end
    h.assertEqual(p.Functions.GetMoney('cash'), p.PlayerData.money.cash)
    h.assertEqual(p:GetMoney('cash'), p.PlayerData.money.cash)
    h.assertEqual(p.GetMoney('cash'), p.PlayerData.money.cash)
end)

h.test('SetMetaData(licences) persists through the funnel', function()
    local p = GetPlayer(1)
    local licences = p.PlayerData.metadata.licences
    licences.weapon = true
    h.assertTrue(p.Functions.SetMetaData('licences', licences))
    h.assertEqual(Core.metadata.getMetaData(1, 'licences').weapon, true)
    h.assertTrue(PI.handle(1)._dirty.metadata, 'metadata column must be dirty')
end)

h.test('missing metadata.licences is defaulted to {} on load', function()
    local data = PI.freshData('CID9', 'license:cid9', 1, { firstname = 'No', lastname = 'Lic', gender = 0 })
    data.metadata.licences = nil
    Core.player.login(9, 'CID9', data)
    h.assertEqual(type(GetPlayer(9).PlayerData.metadata.licences), 'table')
    handle.drainTimeouts()
    Core.player.logout(9)
    handle.drainTimeouts()
end)

h.test('GetPlayersData lists every loaded player as PlayerData', function()
    login(2, 'CID2', { firstname = 'Bo', lastname = 'Peep', gender = 0, birthdate = '1991-02-02' })
    handle.drainTimeouts()
    local all = GetPlayersData()
    h.assertEqual(#all, 2)
    h.assertEqual(all[1].source, 1)
    h.assertEqual(all[2].citizenid, 'CID2')
    h.assertEqual(all[2].charinfo.firstname, 'Bo')
end)

h.test('SetMoney is idempotent: an equal balance writes and notifies nothing', function()
    local p = GetPlayer(1)
    local changes = record('QBCore:Server:OnMoneyChange')
    Core.money.setMoney(1, 'cash', 120, 'seed')
    local base = #changes
    PI.handle(1)._dirty.money = nil
    h.assertTrue(p.Functions.SetMoney('cash', 120, 'Sync cash with inventory'))
    h.assertEqual(#changes, base, 'no OnMoneyChange for an equal balance')
    h.assertEqual(PI.handle(1)._dirty.money, nil, 'no dirty money column')
    h.assertTrue(p.Functions.SetMoney('cash', 75, 'Sync cash with inventory'))
    h.assertEqual(Core.money.getMoney(1, 'cash'), 75)
    h.assertEqual(#changes, base + 1)
    h.assertTrue(p.Functions.SetMoney('cash', 75, 'Sync cash with inventory'))
    h.assertEqual(#changes, base + 1, 'second identical sync is a no-op')
end)

h.test('SetMoney surfaces core errors (negative balance) instead of swallowing them', function()
    local ok = GetPlayer(1).Functions.SetMoney('cash', -5, 'bad')
    h.assertFalse(ok)
    h.assertEqual(Core.money.getMoney(1, 'cash'), 75)
end)

h.test("SetPlayerData('items') mirrors in memory only: no dirty column, no client delta", function()
    local handle1 = PI.handle(1)
    handle1._dirty.items, handle1._dirty.inventory = nil, nil
    local p = GetPlayer(1)
    local pending = 0
    for _ in pairs(handle1._pendingOps) do pending = pending + 1 end
    local items = { [1] = { name = 'water', count = 2, slot = 1, metadata = {} } }
    h.assertTrue(p.Functions.SetPlayerData('items', items))
    h.assertEqual(handle1.PlayerData.items[1].name, 'water')
    h.assertEqual(GetPlayer(1).PlayerData.items[1].count, 2, 'legacy view stays current')
    h.assertEqual(handle1._dirty.inventory, nil)
    h.assertEqual(handle1._dirty.items, nil)
    local after = 0
    for _ in pairs(handle1._pendingOps) do after = after + 1 end
    h.assertEqual(after, pending, 'no replication op queued')
end)

h.test("SetPlayerData for other roots still uses the funnel", function()
    local p = GetPlayer(1)
    h.assertTrue(p.Functions.SetPlayerData('metadata', { licences = { driver = true } }))
    h.assertEqual(Core.metadata.getMetaData(1, 'licences').driver, true)
end)

h.test('GetGroups maps job and gang to zero-based qbx grades (gang none omitted)', function()
    local g = GetGroups(1)
    h.assertEqual(g.unemployed, 0)
    h.assertEqual(g.none, nil)
    Core.jobs.setJob(1, 'police', 3)
    Core.jobs.setGang(1, 'ballas', 2)
    g = GetGroups(1)
    h.assertEqual(g.police, 2)
    h.assertEqual(g.ballas, 1)
    h.assertEqual(g.unemployed, nil)
end)

h.test('onGroupUpdate is re-emitted exactly once per change (server + client)', function()
    local sBefore, cBefore = #groupUpdates, #clientEventsNamed('qbx_core:client:onGroupUpdate')
    Core.jobs.setJob(2, 'police', 1) -- player 2 not yet used: unemployed -> police
    -- the OnPlayerUpdated('all') fan-out re-fires OnJobUpdate; must not double-emit
    TriggerEvent('QBCore:Server:OnPlayerUpdated', 2, 'all')
    TriggerEvent('QBCore:Server:OnPlayerUpdated', 2, 'all')
    local seen = {}
    for i = sBefore + 1, #groupUpdates do
        local u = groupUpdates[i]
        seen[#seen + 1] = ('%s:%s:%s'):format(u[1], tostring(u[2]), tostring(u[3]))
    end
    table.sort(seen)
    h.assertEqual(table.concat(seen, ','), '2:police:0,2:unemployed:nil')
    local cl = clientEventsNamed('qbx_core:client:onGroupUpdate')
    h.assertEqual(#cl - cBefore, 2)
    h.assertEqual(cl[#cl].target, 2)
end)

h.test('duty toggles and no-op writes do not emit group updates', function()
    local before = #groupUpdates
    Core.jobs.setJobDuty(2, false)
    Core.jobs.setJobDuty(2, true)
    Core.jobs.setJob(2, 'police', 1)
    h.assertEqual(#groupUpdates, before)
end)

h.test('gang removal emits a nil grade for the old group', function()
    Core.jobs.setGang(1, 'none', 1)
    local last = groupUpdates[#groupUpdates]
    h.assertEqual(last[2], 'ballas')
    h.assertEqual(last[3], nil)
end)

h.test('IsGradeBoss uses zero-based grades across jobs and gangs', function()
    h.assertTrue(IsGradeBoss('police', 4))
    h.assertFalse(IsGradeBoss('police', 3))
    h.assertTrue(IsGradeBoss('ballas', 2))
    h.assertFalse(IsGradeBoss('nope', 0))
    h.assertFalse(IsGradeBoss('police', 99))
    h.assertFalse(IsGradeBoss(nil, 0))
end)

h.test('CanUseItem returns a callable bound to the registered useable, nil otherwise', function()
    h.assertEqual(CanUseItem('definitely_not_registered'), nil)
    local got
    Core.inventory.createUseable('facade_test_item', function(src, item) got = { src, item } end)
    local cb = CanUseItem('facade_test_item')
    h.assertEqual(type(cb), 'function')
    cb(1, { name = 'facade_test_item' })
    h.assertEqual(got[1], 1)
    h.assertEqual(got[2].name, 'facade_test_item')
end)

h.test('GetVehicleIdByPlate trims and queries player_vehicles by plate', function()
    local sql
    local orig = Kora.sql.single
    Kora.sql.single = function(s, params) sql = { s = s, p = params }; return { id = 42 } end
    h.assertEqual(GetVehicleIdByPlate('abc 123 '), 42)
    Kora.sql.single = orig
    h.assertTrue(sql.s:find('`player_vehicles`', 1, true))
    h.assertTrue(sql.s:find('`deleted_at` IS NULL', 1, true))
    h.assertEqual(sql.p[1], 'abc 123 ')
    h.assertEqual(sql.p[2], 'ABC 123')
    h.assertEqual(GetVehicleIdByPlate('   '), nil)
    h.assertEqual(GetVehicleIdByPlate(nil), nil)
    h.assertEqual(GetVehicleIdByPlate('NOROW'), nil)
end)

h.test('logout clears both bags and re-emits playerLoggedOut exactly once', function()
    local before = #loggedOut
    h.assertTrue(Core.player.logout(1))
    h.assertEqual(handle.playerStates[1].isLoggedIn, false)
    h.assertEqual(handle.playerStates[1].loadInventory, false)
    h.assertEqual(#loggedOut, before + 1)
    h.assertEqual(loggedOut[#loggedOut][1], 1)
    -- a later drop / stray unload for the same session must not re-emit
    TriggerEvent('QBCore:Server:OnPlayerUnload', 1)
    Core.player.dropPlayer(1, 'quit')
    h.assertEqual(#loggedOut, before + 1)
end)

h.test('disconnect (drop) re-emits playerLoggedOut once', function()
    local before = #loggedOut
    Core.player.dropPlayer(2, 'quit')
    h.assertEqual(#loggedOut, before + 1)
    h.assertEqual(loggedOut[#loggedOut][1], 2)
    h.assertEqual(GetPlayer(2), nil)
end)

h.test('relogin on the same source sets loadInventory true again', function()
    login(1, 'CID1')
    handle.drainTimeouts()
    h.assertEqual(handle.playerStates[1].loadInventory, true)
end)

h.test('a logout before the ready tick never sets loadInventory true', function()
    login(5, 'CID5')
    Core.player.logout(5)
    handle.drainTimeouts()
    h.assertEqual(handle.playerStates[5].loadInventory, false)
end)

h.report('qbx_facade')
