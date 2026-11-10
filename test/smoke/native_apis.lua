local h = dofile('test/harness.lua')
local handle = dofile('test/mocks.lua').install()
dofile('config.lua')
for _, name in ipairs({ 'items', 'vehicles', 'jobs', 'gangs', 'weapons', 'locations' }) do
    dofile('shared/' .. name .. '.lua')
end
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua'); dofile('modules/registry/server.lua')
dofile('modules/player/shared.lua'); dofile('compat/shared/coreobject.lua')
dofile('modules/identity/server.lua'); dofile('modules/replication/server.lua')
dofile('modules/persistence/server.lua'); dofile('modules/player/server.lua')
dofile('modules/money/server.lua'); dofile('modules/jobs/server.lua')

GetNumPlayerIdentifiers = function() return 1 end
GetPlayerIdentifier = function() return 'license:abc' end
GetPlayerEndpoint = function() return '127.0.0.1' end

h.test('native bucket changes keep compatibility tracking and voice notification', function()
    local bucket, notifications
    SetPlayerRoutingBucket = function(src, value) h.assertEqual(src, 1); bucket = value end
    local trigger = TriggerEvent
    TriggerEvent = function(name, src)
        h.assertEqual(name, 'kora_voice:server:bucketChanged')
        h.assertEqual(src, 1); notifications = (notifications or 0) + 1
    end
    h.assertTrue(Core.player.setPlayerBucket(1, 42))
    h.assertEqual(bucket, 42); h.assertEqual(notifications, 1)
    local license = Core.identity.getIdentifiers(1).license
    h.assertEqual(QBCore.Player_Buckets[license].bucket, 42)
    TriggerEvent = trigger
end)

h.test('starter definitions are snapshots and saves use the live handle', function()
    local items = Core.player.getStarterItems()
    items.phone.item = 'changed'
    h.assertEqual(QBCore.Shared.StarterItems.phone.item, 'phone')
    local data = CoreInternal.player.freshData('ONLINE', 'license:abc', 1, { firstname = 'A', lastname = 'B' })
    h.assertTrue(Core.player.login(1, 'ONLINE', data))
    Core.player.setPath(1, { 'metadata', 'test' }, true)
    h.assertTrue(Core.player.savePlayer(1))
    h.assertTrue(#handle.sqlCalls.enqueue > 0)
    h.assertEqual(handle.sqlCalls.enqueue[#handle.sqlCalls.enqueue].opts.priority, 'immediate')
    h.assertFalse(Core.player.savePlayer(999))
end)

local writes, result = {}, 1
local row = {
    citizenid = 'OFFLINE', license = 'license:offline', cid = 7, name = 'Offline',
    charinfo = json.encode({}), money = json.encode({ bank = 100 }),
    job = json.encode({}), gang = json.encode({}), metadata = json.encode({}),
    inventory = json.encode({}), position = json.encode({}),
}
Kora.sql.single = function(_, params) return params[1] == row.citizenid and row or nil end
Kora.sql.update = function(sql, params)
    writes[#writes + 1] = { sql = sql, params = params }
    return result, result == nil and 'database unavailable' or nil
end

h.test('offline roles keep native grade levels and update only their column', function()
    h.assertTrue(Core.jobs.setOfflineJob('OFFLINE', 'police', 2))
    h.assertEqual(writes[1].params[1], json.encode(CoreInternal.player.buildJob('police', 2)))
    h.assertTrue(writes[1].sql:find('SET `job` = ?', 1, true) ~= nil)
    h.assertEqual(writes[1].params[2], 'OFFLINE')
    h.assertTrue(Core.jobs.setOfflineGang('OFFLINE', 'none', 1))
    h.assertTrue(writes[2].sql:find('SET `gang` = ?', 1, true) ~= nil)
    h.assertFalse(Core.jobs.setOfflineJob('OFFLINE', 'unknown', 1))
    h.assertFalse(Core.jobs.setOfflineJob('MISSING', 'police', 1))
end)

h.test('offline writes reject immutable keys and online character snapshots', function()
    h.assertFalse(Core.persistence.saveOfflinePlayer(row, { 'license' }))
    h.assertFalse(Core.persistence.saveOfflinePlayer(row, { 'cid' }))
    h.assertFalse(Core.persistence.saveOfflinePlayer(row, {}))
    h.assertFalse(Core.persistence.saveOfflinePlayer({ citizenid = 'ONLINE' }, { 'job' }))
    h.assertEqual(#writes, 2)
    result = 0
    h.assertTrue(Core.persistence.saveOfflinePlayer(row, { 'job' }), 'unchanged existing rows still save')
    h.assertFalse(Core.persistence.saveOfflinePlayer({ citizenid = 'MISSING' }, { 'job' }))
    result = nil
    h.assertFalse(Core.persistence.saveOfflinePlayer(row, { 'job' }))
    result = 1
end)

h.test('offline credit uses an atomic increment and checks its result', function()
    h.assertTrue(Core.money.addOfflineMoney('OFFLINE', 'bank', 25))
    local write = writes[#writes]
    h.assertTrue(write.sql:find('JSON_EXTRACT', 1, true) ~= nil)
    h.assertEqual(write.params[1], '$."bank"')
    h.assertEqual(write.params[3], 25); h.assertEqual(write.params[4], 'OFFLINE')
    local count = #writes
    h.assertFalse(Core.money.addOfflineMoney('ONLINE', 'bank', 25))
    for _, amount in ipairs({ 0, -1, math.huge, 'invalid' }) do
        h.assertFalse(Core.money.addOfflineMoney('OFFLINE', 'bank', amount))
    end
    h.assertFalse(Core.money.addOfflineMoney('OFFLINE', 'unknown', 25))
    h.assertEqual(#writes, count)
    result = 0
    h.assertFalse(Core.money.addOfflineMoney('MISSING', 'bank', 25))
    result = nil
    h.assertFalse(Core.money.addOfflineMoney('OFFLINE', 'bank', 25))
end)

h.report('native APIs')
