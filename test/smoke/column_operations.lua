local h = dofile('test/harness.lua')
local handle = dofile('test/mocks.lua').install()
dofile('config.lua')
for _, name in ipairs({ 'items', 'vehicles', 'jobs', 'gangs', 'weapons', 'locations' }) do dofile('shared/' .. name .. '.lua') end
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua'); dofile('modules/registry/server.lua')
dofile('modules/player/shared.lua'); dofile('modules/inventory/shared.lua')
dofile('modules/replication/server.lua'); dofile('modules/persistence/server.lua')
dofile('modules/persistence/operations.lua'); dofile('modules/player/server.lua')
dofile('modules/money/server.lua'); dofile('modules/inventory/server.lua')
local caller = 'qbbanking'
GetInvokingResource = function() return caller end
exports.qbsql = { hasActivePlayerOperation = function() return false end }
QB.sql.transactionChecked = function() return { success = true } end
QB.sql.update = function() return 1 end
local data = CoreInternal.player.freshData('DURABLE', 'license:durable', 1, {})
assert(Core.player.login(1, 'DURABLE', data))
local function finish(token, amount)
    h.assertTrue(Core.persistence.finishPlayerColumnOperation(token, { DURABLE = { money = { cash = 500, bank = amount, crypto = 0 } } }))
end

h.test('only configured providers can fence supported player columns', function()
    caller = 'untrusted'
    h.assertEqual(Core.persistence.beginPlayerColumnOperation('x', { 'DURABLE' }, { 'money' }), nil)
    caller = 'qbbanking'
    h.assertEqual(Core.persistence.beginPlayerColumnOperation('x', { 'DURABLE' }, { 'license' }), nil)
end)

h.test('interleaved saves cannot enqueue or restore the fenced money snapshot', function()
    assert(Core.money.setMoney(1, 'bank', 1000))
    local ordinaryFlush = QB.sql.flush
    QB.sql.flush = function() coroutine.yield('pending flush'); return true end
    local thread = coroutine.create(function() return Core.persistence.beginPlayerColumnOperation('sale', { 'DURABLE' }, { 'money' }) end)
    local ok, wait = coroutine.resume(thread)
    h.assertTrue(ok); h.assertEqual(wait, 'pending flush')
    h.assertFalse(Core.money.addMoney(1, 'bank', 100))
    h.assertFalse(Core.money.removeMoney(1, 'bank', 100))
    h.assertFalse(Core.money.setMoney(1, 'bank', 0))
    h.assertFalse(Core.player.setPath(1, { 'money' }, { bank = 0 }, { _columnOperationToken = {} }))
    local before = #handle.sqlCalls.enqueueMany
    Core.persistence.flushAll()
    for index = before + 1, #handle.sqlCalls.enqueueMany do
        for _, row in ipairs(handle.sqlCalls.enqueueMany[index].rows) do h.assertEqual(row.cols.money, nil) end
    end
    local resumed, token = coroutine.resume(thread)
    h.assertTrue(resumed); h.assertTrue(type(token) == 'string')
    QB.sql.flush = ordinaryFlush
    finish(token, 700)
    h.assertEqual(Core.money.getMoney(1, 'bank'), 700)
    h.assertEqual(Core.persistence.flushAll(), 0, 'Committed money is already the encoded baseline')
    h.assertTrue(Core.money.addMoney(1, 'bank', 50))
    Core.persistence.flushAll()
    local last = handle.sqlCalls.enqueueMany[#handle.sqlCalls.enqueueMany]
    h.assertEqual(json.decode(last.rows[1].cols.money).bank, 750)
end)

h.test('offline writes and character login cannot cross an active operation', function()
    local token = assert(Core.persistence.beginPlayerColumnOperation('offline', { 'OFFLINE' }, { 'money' }))
    h.assertFalse(Core.money.addOfflineMoney('OFFLINE', 'bank', 20))
    h.assertFalse(Core.persistence.saveOfflinePlayer({ citizenid = 'OFFLINE' }, { 'money' }))
    h.assertFalse(Core.player.login(2, 'OFFLINE', {}))
    h.assertFalse(Core.persistence._deleteCharacterRow('OFFLINE'))
    h.assertTrue(Core.persistence.abortPlayerColumnOperation(token))
end)

h.test('an offline writer already in flight blocks a later durable operation', function()
    local update = QB.sql.update
    QB.sql.update = function() coroutine.yield('offline update'); return 1 end
    local thread = coroutine.create(function() return Core.money.addOfflineMoney('INFLIGHT', 'bank', 25) end)
    h.assertTrue(coroutine.resume(thread))
    local token, code = Core.persistence.beginPlayerColumnOperation('racing', { 'INFLIGHT' }, { 'money' })
    h.assertEqual(token, nil); h.assertEqual(code, 'pending')
    h.assertFalse(Core.player.login(2, 'INFLIGHT', {}))
    h.assertTrue(coroutine.resume(thread))
    QB.sql.update = update
    token = assert(Core.persistence.beginPlayerColumnOperation('racing', { 'INFLIGHT' }, { 'money' }))
    h.assertTrue(Core.persistence.abortPlayerColumnOperation(token))
end)

h.test('a stale character query is rejected when a transaction crosses its read', function()
    local single = QB.sql.single
    QB.sql.single = function(sql)
        if sql:find('qbcore_player_column_operations', 1, true) then return nil end
        coroutine.yield('read'); return { citizenid = 'RACE' }
    end
    local thread = coroutine.create(function() return Core.persistence._load('RACE') end)
    h.assertTrue(coroutine.resume(thread))
    local token = assert(Core.persistence.beginPlayerColumnOperation('read-race', { 'RACE' }, { 'money' }))
    assert(Core.persistence.abortPlayerColumnOperation(token))
    local ok, value, err = coroutine.resume(thread)
    h.assertTrue(ok); h.assertEqual(value, nil); h.assertTrue(type(err) == 'string')
    QB.sql.single = single
end)

h.test('inventory fallback mutators cannot edit live item references while fenced', function()
    assert(Core.inventory.addItem(1, 'water_bottle', 2))
    caller = Config.inventory.provider
    local token = assert(Core.persistence.beginPlayerColumnOperation('recovery', { 'DURABLE' }, { 'inventory' }))
    local before = json.encode(Core.player.getPlayerData(1, { 'items' }))
    h.assertFalse(Core.inventory.addItem(1, 'water_bottle', 1))
    h.assertFalse(Core.inventory.removeItem(1, 'water_bottle', 1))
    h.assertFalse(Core.inventory.clearInventory(1))
    h.assertFalse(Core.inventory.setItems(1, {}))
    h.assertEqual(json.encode(Core.player.getPlayerData(1, { 'items' })), before)
    h.assertTrue(Core.persistence.finishPlayerColumnOperation(token, { DURABLE = { inventory = {} } }))
    caller = 'qbbanking'
end)

h.test('flush failure releases the fence without publishing different money', function()
    local flush = QB.sql.flush
    QB.sql.flush = function() return false, 'controlled storage failure' end
    local token, code = Core.persistence.beginPlayerColumnOperation('failed', { 'DURABLE' }, { 'money' })
    h.assertEqual(token, nil); h.assertEqual(code, 'unavailable')
    h.assertTrue(Core.money.addMoney(1, 'bank', 1))
    QB.sql.flush = flush
end)

h.test('a yielding legacy transfer cannot be captured between its debit and credit', function()
    local other = CoreInternal.player.freshData('RECIPIENT', 'license:recipient', 1, {})
    assert(Core.player.login(3, 'RECIPIENT', other))
    local subscription = Core.player.onChange({ 'money', 'bank' }, function(src)
        if src == 1 then coroutine.yield('debit applied') end
    end)
    local thread = coroutine.create(function() return Core.money.transferMoney(1, 3, 'bank', 10, 'test', true) end)
    local ok, waiting = coroutine.resume(thread)
    h.assertTrue(ok); h.assertEqual(waiting, 'debit applied')
    local token, code = Core.persistence.beginPlayerColumnOperation('during-transfer', { 'DURABLE', 'RECIPIENT' }, { 'money' })
    h.assertEqual(token, nil); h.assertEqual(code, 'pending')
    local resumed, transferred = coroutine.resume(thread)
    h.assertTrue(resumed); h.assertTrue(transferred)
    Core.player.offChange(subscription)
    token = assert(Core.persistence.beginPlayerColumnOperation('after-transfer', { 'DURABLE', 'RECIPIENT' }, { 'money' }))
    h.assertTrue(Core.persistence.abortPlayerColumnOperation(token))
end)

h.test('offline credit rechecks a login that completes during its storage guard', function()
    local single, first = QB.sql.single, true
    QB.sql.single = function()
        if first then first = false; coroutine.yield('offline guard') end
        return nil
    end
    local thread = coroutine.create(function() return Core.money.addOfflineMoney('LOGIN_RACE', 'bank', 20) end)
    h.assertTrue(coroutine.resume(thread))
    local latest = CoreInternal.player.freshData('LOGIN_RACE', 'license:loginrace', 1, {})
    h.assertTrue(Core.player.login(5, 'LOGIN_RACE', latest))
    local resumed, credited, err = coroutine.resume(thread)
    h.assertTrue(resumed); h.assertFalse(credited); h.assertEqual(err, 'player is online')
    h.assertFalse(Core.player.login(6, 'LOGIN_RACE', latest), 'One character must have only one authoritative live balance')
    QB.sql.single = single
end)

h.test('a core restart recovers durable fences before login and publishes current data', function()
    local query, single, checked, update = QB.sql.query, QB.sql.single, QB.sql.transactionChecked, QB.sql.update
    local stored, committed = {}, { cash = 500, bank = 42, crypto = 0 }
    QB.sql.query = function() return Core.util.deepClone(stored) end
    QB.sql.single = function(sql)
        if sql:find('qbcore_player_column_operations', 1, true) then return stored[1] end
        return { citizenid = 'RESTART', license = 'license:restart', money = json.encode(committed), inventory = '{}' }
    end
    QB.sql.transactionChecked = function(statements)
        for _, statement in ipairs(statements) do
            local p = statement.values
            stored[#stored + 1] = { citizenid = p[1], column_name = p[2], resource = p[3], operation_key = p[4], fingerprint = p[5] }
        end
        return { success = true }
    end
    QB.sql.update = function() stored = {}; return 1 end
    assert(Core.persistence.beginPlayerColumnOperation('survives-restart', { 'RESTART' }, { 'money' }))
    dofile('modules/persistence/operations.lua')
    local stale = CoreInternal.player.freshData('RESTART', 'license:restart', 1, {})
    stale.money.bank = 999
    h.assertFalse(Core.player.login(4, 'RESTART', stale), 'Persistent fence must block a fresh core cache')
    local operations = Core.persistence.getPlayerColumnOperations()
    h.assertEqual(#operations, 1)
    h.assertEqual(operations[1].operationKey, 'survives-restart')
    h.assertTrue(Core.persistence.finishPlayerColumnOperation(operations[1].token, { RESTART = { money = committed } }))
    h.assertTrue(Core.player.login(4, 'RESTART', stale))
    h.assertEqual(Core.money.getMoney(4, 'bank'), 42, 'Stale pre-operation login data must reload after recovered commit')
    h.assertEqual(#stored, 0)
    QB.sql.query, QB.sql.single, QB.sql.transactionChecked, QB.sql.update = query, single, checked, update
end)

h.report('durable column operations')
