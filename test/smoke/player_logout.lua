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
dofile('modules/persistence/operations.lua')
dofile('modules/player/server.lua')
dofile('modules/multichar/server.lua')

local caller, activeOperation, storedFence, flushHook, flushCount = nil, false, false, nil, 0
local identities = {}
GetInvokingResource = function() return caller end
Core.identity.primary = function(src) return identities[src] end
exports.kora_sql = { hasActivePlayerOperation = function() return activeOperation end }
local originalSingle, originalEnqueue = Kora.sql.single, Kora.sql.enqueue
Kora.sql.single = function(sql, params)
    if sql:find('kora_core_player_column_operations', 1, true) and storedFence then
        return { operation_key = 'pending' }
    end
    return originalSingle(sql, params)
end
Kora.sql.flush = function()
    flushCount = flushCount + 1
    if flushHook then return flushHook() end
    return true
end
Kora.sql.transactionChecked = function() return { success = true } end
Kora.sql.update = function() return 1 end
local PI = CoreInternal.player
local serial = 100
local function data(src, cid)
    return PI.freshData(cid or ('LOGOUT' .. src), 'license:logout' .. src, 1,
        { firstname = 'Logout', lastname = 'Fixture' })
end
local function player()
    serial = serial + 1
    local src = serial
    identities[src] = 'license:logout' .. src
    local info = data(src)
    h.assertTrue(Core.player.login(src, info.citizenid, info))
    return src, PI.handle(src)
end
local exterior = { x = 200.0, y = 300.0, z = 40.0, h = 90.0 }
local function options() return { position = Core.util.deepClone(exterior) } end
local function unloadCount(src)
    local n = 0
    for _, event in ipairs(handle.clientEvents) do
        if event.name == 'QBCore:Client:OnPlayerUnload' and event.target == src then n = n + 1 end
    end
    return n
end

h.test('housing logout confirms flush before unloading and preserves exterior over the ped sample', function()
    local src, live = player()
    caller = 'kora_housing'
    Core.player.setPath(src, { 'money', 'bank' }, 345)
    flushHook = function()
        h.assertEqual(PI.handle(src), live)
        h.assertTrue(Player(src).state['qbcore:loggedIn'])
        h.assertEqual(unloadCount(src), 0)
        Core.persistence.flushAll()
        local row = handle.sqlCalls.enqueue[#handle.sqlCalls.enqueue].row
        h.assertEqual(json.decode(row.cols.position).x, exterior.x)
        h.assertEqual(json.decode(row.cols.money).bank, 345)
        return true
    end
    h.assertTrue(Core.player.logout(src, options()))
    h.assertEqual(PI.handle(src), nil)
    h.assertFalse(Player(src).state['qbcore:loggedIn'])
    h.assertEqual(unloadCount(src), 1)
    h.assertFalse(Core.persistence._hasColumnOperation(live.citizenid))
    flushHook, caller = nil, nil
end)

h.test('ordinary logout samples authoritative coordinates and requires a flush', function()
    local src = player()
    local oldCoords = GetEntityCoords
    GetEntityCoords = function() return { x = 15, y = 25, z = 35 } end
    local before = flushCount
    h.assertTrue(Core.player.logout(src))
    h.assertEqual(flushCount, before + 1)
    h.assertEqual(json.decode(handle.sqlCalls.enqueue[#handle.sqlCalls.enqueue].row.cols.position).x, 15)
    GetEntityCoords = oldCoords
end)

h.test('failed flush keeps the session and final changes retryable', function()
    local src, live = player()
    caller = 'kora_housing'
    Core.player.setPath(src, { 'money', 'bank' }, 789)
    local position = Core.util.deepClone(live.PlayerData.position)
    flushHook = function() return false, 'database unavailable' end
    local ok, err = Core.player.logout(src, options())
    h.assertFalse(ok); h.assertEqual(err, 'database unavailable')
    h.assertEqual(PI.handle(src), live)
    h.assertTrue(Player(src).state['qbcore:loggedIn'])
    h.assertEqual(unloadCount(src), 0)
    h.assertEqual(live.PlayerData.position.x, position.x)
    h.assertTrue(live._dirty.money)
    h.assertEqual(live._encoded.money, nil)
    h.assertFalse(Core.persistence._hasColumnOperation(live.citizenid))
    h.assertTrue(Core.player.setPath(src, { 'metadata', 'hunger' }, 70))
    flushHook = nil
    h.assertTrue(Core.player.logout(src, options()))
    local row = handle.sqlCalls.enqueue[#handle.sqlCalls.enqueue].row
    h.assertEqual(json.decode(row.cols.money).bank, 789)
    h.assertEqual(json.decode(row.cols.position).x, exterior.x)
    h.assertEqual(row.cols.license, nil); h.assertEqual(row.cols.cid, nil)
    caller = nil
end)

h.test('logout rewrites the final snapshot after an earlier queued save was lost', function()
    local src, live = player()
    Core.player.setPath(src, { 'money', 'bank' }, 1234)
    Core.persistence.saveNow(live)
    h.assertEqual(live._dirty.money, nil)
    h.assertTrue(live._encoded.money ~= nil)
    local before = #handle.sqlCalls.enqueue
    flushHook = function()
        h.assertEqual(#handle.sqlCalls.enqueue, before + 1)
        local row = handle.sqlCalls.enqueue[#handle.sqlCalls.enqueue].row
        h.assertEqual(json.decode(row.cols.money).bank, 1234)
        for _, column in pairs(PI.COLUMN_FOR) do h.assertTrue(row.cols[column] ~= nil) end
        h.assertEqual(row.cols.license, nil); h.assertEqual(row.cols.cid, nil)
        return true
    end
    h.assertTrue(Core.player.logout(src))
    flushHook = nil
end)

h.test('thrown enqueue and missing flush acknowledgement never unload', function()
    local src, live = player()
    Kora.sql.enqueue = function() error('enqueue failed') end
    local ok, err = Core.player.logout(src)
    h.assertFalse(ok); h.assertTrue(err:find('enqueue failed', 1, true) ~= nil)
    h.assertEqual(PI.handle(src), live)
    h.assertFalse(Core.persistence._hasColumnOperation(live.citizenid))
    Kora.sql.enqueue = originalEnqueue
    flushHook = function() return nil end
    h.assertFalse(Core.player.logout(src))
    h.assertEqual(unloadCount(src), 0)
    flushHook = nil
    h.assertTrue(Core.player.logout(src))
end)

h.test('untrusted or nonfinite exterior overrides are rejected before persistence', function()
    local src, live = player()
    local before = flushCount
    caller = 'untrusted-resource'
    h.assertFalse(Core.player.logout(src, options()))
    caller = 'kora_housing'
    for _, bad in ipairs({ { x = 0/0, y = 0, z = 1 }, { x = 1, y = math.huge, z = 1 },
        { x = 1, y = 2, z = 3, h = '90' }, { x = '1', y = 2, z = 3 } }) do
        h.assertFalse(Core.player.logout(src, { position = bad }))
    end
    h.assertEqual(flushCount, before)
    h.assertEqual(PI.handle(src), live)
    caller = nil
    h.assertTrue(Core.player.logout(src))
end)

h.test('durable and ordinary player operations block logout', function()
    local src, live = player()
    local before = flushCount
    storedFence = true
    h.assertFalse(Core.player.logout(src))
    storedFence = false; activeOperation = true
    h.assertFalse(Core.player.logout(src))
    activeOperation = false
    h.assertTrue(Core.persistence._beginOfflineWrite(live.citizenid))
    h.assertFalse(Core.player.logout(src))
    Core.persistence._endOfflineWrite(live.citizenid)
    h.assertEqual(flushCount, before)
    h.assertTrue(Core.player.logout(src))
end)

h.test('logout fences writes and new durable operations until acknowledgement', function()
    local src, live = player()
    flushHook = function()
        h.assertFalse(Core.player.setPath(src, { 'money', 'bank' }, 99999))
        h.assertFalse(Core.player.logout(src))
        caller = 'kora_inventory'
        local token, code = Core.persistence.beginPlayerColumnOperation('logout-race', { live.citizenid }, { 'money' })
        h.assertEqual(token, nil); h.assertEqual(code, 'pending')
        caller = nil
        return true
    end
    h.assertTrue(Core.player.logout(src))
    flushHook = nil
    h.assertFalse(Core.persistence._hasColumnOperation(live.citizenid))
end)

h.test('source reuse during flush cannot unload or evict the replacement session', function()
    local src, old = player()
    local replacement
    flushHook = function()
        Core.player.dropPlayer(src, 'test reconnect')
        local fresh = data(src, old.citizenid .. 'NEW')
        h.assertTrue(Core.player.login(src, fresh.citizenid, fresh))
        replacement = PI.handle(src)
        return true
    end
    local ok, err = Core.player.logout(src)
    h.assertFalse(ok); h.assertEqual(err, 'player session changed')
    h.assertEqual(PI.handle(src), replacement)
    h.assertEqual(PI.byCitizenId[replacement.citizenid], replacement)
    h.assertTrue(Player(src).state['qbcore:loggedIn'])
    h.assertEqual(unloadCount(src), 0)
    h.assertFalse(Core.persistence._hasColumnOperation(old.citizenid))
    flushHook = nil
    h.assertTrue(Core.player.logout(src))
end)

h.test('joining epoch change during flush rejects the old logout', function()
    local src, live = player()
    flushHook = function() handle.fireEvent('playerJoining', src); return true end
    h.assertFalse(Core.player.logout(src))
    h.assertEqual(PI.handle(src), live)
    h.assertTrue(Player(src).state['qbcore:loggedIn'])
    h.assertEqual(unloadCount(src), 0)
    flushHook = nil
    h.assertTrue(Core.player.logout(src))
end)

h.test('unload subscribers cannot cause replacement-cache eviction', function()
    local src, old = player()
    local entered, replacement = false, nil
    AddEventHandler('QBCore:Server:OnPlayerUnload', function(unloading)
        if unloading ~= src or entered then return end
        entered = true
        Core.player.dropPlayer(src, 'subscriber reconnect')
        local fresh = data(src, old.citizenid .. 'NEXT')
        h.assertTrue(Core.player.login(src, fresh.citizenid, fresh))
        replacement = PI.handle(src)
    end)
    h.assertTrue(Core.player.logout(src))
    h.assertEqual(PI.handle(src), replacement)
    h.assertEqual(PI.byCitizenId[replacement.citizenid], replacement)
    h.assertTrue(Player(src).state['qbcore:loggedIn'])
    h.assertTrue(Core.player.logout(src))
end)

h.test('delete refuses a failed logout and never reaches the soft-delete write', function()
    local src, live = player()
    local load = Core.persistence._load
    Core.persistence._load = function() return Core.util.deepClone(live.PlayerData) end
    flushHook = function() return false, 'save unavailable' end
    local before = #handle.sqlCalls.execute
    local ok, err = Core.multichar.deleteCharacter(src, live.citizenid)
    h.assertFalse(ok); h.assertEqual(err, 'save unavailable')
    h.assertEqual(#handle.sqlCalls.execute, before)
    h.assertEqual(PI.handle(src), live)
    Core.persistence._load, flushHook = load, nil
    h.assertTrue(Core.player.logout(src))
end)

h.test('soft deletion rejects an online character before and after its storage wait', function()
    local src, live = player()
    h.assertFalse(Core.persistence._deleteCharacterRow(live.citizenid))
    local available = Core.persistence._persistentColumnsAvailable
    local before = #handle.sqlCalls.execute
    Core.persistence._persistentColumnsAvailable = function(cid)
        PI.byCitizenId[cid] = live
        return true
    end
    h.assertFalse(Core.persistence._deleteCharacterRow('OFFLINE_RACE'))
    h.assertEqual(#handle.sqlCalls.execute, before)
    PI.byCitizenId.OFFLINE_RACE = nil
    Core.persistence._persistentColumnsAvailable = available
    h.assertTrue(Core.player.logout(src))
end)

h.test('stale login data refreshes persisted position and metadata after logout', function()
    local src, live = player()
    local stale = Core.util.deepClone(live.PlayerData)
    caller = 'kora_housing'
    Core.player.setPath(src, { 'metadata', 'hunger' }, 42)
    h.assertTrue(Core.player.logout(src, options()))
    caller = nil
    local load = Core.persistence._load
    Core.persistence._load = function() return Core.util.deepClone(live.PlayerData) end
    h.assertTrue(Core.player.login(src, live.citizenid, stale))
    h.assertEqual(Core.player.getPlayer(src).position.x, exterior.x)
    h.assertEqual(Core.player.getPlayer(src).metadata.hunger, 42)
    Core.persistence._load = load
    h.assertTrue(Core.player.logout(src))
end)

h.report('player logout')
