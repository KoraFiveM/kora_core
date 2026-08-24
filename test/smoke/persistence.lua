-- Persistence smoke test -- the correctness core of the write path:
--   * mutating money marks exactly {money} dirty;
--   * mutating twice still produces one row;
--   * setting a value back to its original enqueues ZERO columns;
--   * license/cid never appear in a write set;
--   * position below/above the epsilon behaves.
-- Server realm (registry + player + persistence + replication + money).

local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua')
local handle = mocks.install()

dofile('config.lua')
dofile('shared/items.lua'); dofile('shared/jobs.lua'); dofile('shared/gangs.lua')
dofile('shared/vehicles.lua'); dofile('shared/weapons.lua'); dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua')
dofile('modules/registry/server.lua')
dofile('modules/player/shared.lua')
dofile('modules/replication/server.lua')
dofile('modules/persistence/server.lua')
dofile('modules/player/server.lua')
dofile('modules/money/server.lua')
dofile('modules/metadata/server.lua')

local PI = CoreInternal.player

-- Log a player in with a fixed data blob so _encoded is seeded.
local function loginTestPlayer()
    local data = CoreInternal.player.freshData('CID1', 'license:abc', 1, { firstname = 'A', lastname = 'B' })
    Core.player.login(1, 'CID1', data)
    return PI.handle(1)
end

h.test('mutating money marks exactly {money} dirty', function()
    local p = loginTestPlayer()
    p._dirty = {}   -- clear any load-time dirt
    Core.money.addMoney(1, 'cash', 100, 'test')
    local keys = {}
    for k in pairs(p._dirty) do keys[#keys + 1] = k end
    h.assertEqual(#keys, 1, 'exactly one column dirty')
    h.assertEqual(keys[1], 'money')
end)

h.test('flushAll enqueues one row with ONLY the money column', function()
    -- The FIRST flush also persists position (no baseline yet). Establish that
    -- baseline, then a subsequent money-only change writes only money (the mock
    -- ped coords are stable, so position stays below the epsilon thereafter).
    Core.persistence.flushAll()
    Core.money.addMoney(1, 'cash', 10, 'baseline')
    handle.sqlCalls.enqueueMany = {}
    Core.persistence.flushAll()
    local call = handle.sqlCalls.enqueueMany[1]
    h.assertTrue(call ~= nil, 'expected an enqueueMany')
    h.assertEqual(call.table, 'players')
    h.assertEqual(call.opts.writeMode, 'update', 'existing player saves must never use a partial upsert')
    h.assertEqual(#call.rows, 1, 'one dirty player')
    local cols = call.rows[1].cols
    local colNames = {}
    for k in pairs(cols) do colNames[#colNames + 1] = k end
    h.assertEqual(#colNames, 1, 'only one column written')
    h.assertEqual(colNames[1], 'money')
end)

h.test('mutating twice before a flush still produces ONE row', function()
    Core.money.addMoney(1, 'cash', 50, 't')
    Core.money.addMoney(1, 'bank', 25, 't')
    handle.sqlCalls.enqueueMany = {}
    Core.persistence.flushAll()
    local call = handle.sqlCalls.enqueueMany[1]
    h.assertEqual(#call.rows, 1, 'still one row for the one player')
end)

h.test('setting a value back to its original enqueues ZERO columns (byte-identical gate)', function()
    local p = PI.handle(1)
    local before = p.PlayerData.money.cash
    -- Change then revert within one window.
    Core.money.setMoney(1, 'cash', before + 999, 't')
    Core.money.setMoney(1, 'cash', before, 't')
    handle.sqlCalls.enqueueMany = {}
    local flushed = Core.persistence.flushAll()
    -- The money column re-encodes identically to the last-saved value, so it is
    -- dropped -> no row enqueued at all.
    h.assertEqual(flushed, 0, 'a reverted change must write nothing')
end)

h.test('license and cid never appear in a write set', function()
    local p = PI.handle(1)
    -- Force them dirty artificially and ensure collectRows skips them.
    p._dirty['license'] = true
    p._dirty['cid'] = true
    p._dirty['money'] = true
    p.PlayerData.money.cash = p.PlayerData.money.cash + 1   -- make money genuinely change
    handle.sqlCalls.enqueueMany = {}
    Core.persistence.flushAll()
    local call = handle.sqlCalls.enqueueMany[1]
    if call then
        for _, row in ipairs(call.rows) do
            h.assertTrue(row.cols.license == nil, 'license must never be written')
            h.assertTrue(row.cols.cid == nil, 'cid must never be written')
        end
    end
end)

-- A sparse slot map serialises to a JSON OBJECT, so json.decode hands the slot
-- keys back as STRINGS. PlayerData.items is contractually a NUMERIC slot-keyed
-- map (modules/inventory/AGENTS.md), and every reader looks up items[slot] with
-- a number -- so before this was normalised, a character restored from the
-- database had an inventory that rendered correctly but could not be moved:
-- the first drag reported "invalid item amount" because items[1] was nil while
-- items['1'] held the item.
h.test('_load re-keys JSON string slot keys back to numbers', function()
    local sql = 'SELECT * FROM `players` WHERE `citizenid` = ? AND `deleted_at` IS NULL'
    handle.sqlResponses.single[sql] = {
        citizenid = 'CID9', license = 'license:z', cid = 1, name = 'jay sixty',
        money = '{}', charinfo = '{}', job = '{}', gang = '{}',
        position = '{}', metadata = '{}', phone_number = nil,
        -- Exactly the shape the live players.inventory column holds.
        inventory = '{"1":{"slot":1,"name":"weapon_knife","amount":1,"weight":500},'
            .. '"29":{"slot":29,"name":"weapon_knife","amount":1,"weight":500}}',
    }

    local data = Core.persistence._load('CID9')
    h.assertTrue(data ~= nil, 'character loaded')
    h.assertTrue(data.items[1] ~= nil, 'slot 1 is reachable by NUMBER')
    h.assertTrue(data.items[29] ~= nil, 'slot 29 is reachable by NUMBER')
    h.assertEqual(data.items[1].name, 'weapon_knife')
    h.assertEqual(data.items[1].slot, 1)
    h.assertTrue(data.items['1'] == nil, 'the string key does not survive')

    -- An empty inventory persists as '[]', which must stay an empty map.
    handle.sqlResponses.single[sql].inventory = '[]'
    local empty = Core.persistence._load('CID9')
    h.assertEqual(next(empty.items), nil, 'an empty inventory decodes to an empty map')
end)

h.report('persistence')
