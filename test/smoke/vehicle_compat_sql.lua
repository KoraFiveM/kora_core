-- Migration 011 / legacy player_vehicles compat: the migration is registered,
-- adds every stock column, and the installed triggers map both directions.
-- The real-SQL behaviour is tested by test/sql/scratch/run.sh.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('build/initiate.lua')

local migrations
Kora.sql.migrateFiles = function(_, list) migrations = list; return true end
Kora.sql.query = function(sql, params)
    if sql:find('information_schema', 1, true) then return {} end
    return {}
end
dofile('modules/persistence/migrate.lua')
handle.step()

local function read(path) local f = assert(io.open(path, 'rb')); local d = f:read('a'); f:close(); return d end

h.test('migration 11 is registered with a stable version', function()
    local found
    for _, m in ipairs(migrations) do if m.version == 11 then found = m end end
    h.assertTrue(found ~= nil and found.file == 'sql/011_legacy_vehicle_compat.sql', 'v11 registered')
end)

h.test('migration adds every missing stock column idempotently', function()
    local sql = read('sql/011_legacy_vehicle_compat.sql')
    for _, col in ipairs({ 'license', 'hash', 'fakeplate', 'garage', 'engine', 'body',
        'depotprice', 'drivingdistance', 'status' }) do
        h.assertTrue(sql:find('ADD COLUMN IF NOT EXISTS `' .. col .. '`', 1, true) ~= nil, col)
    end
    h.assertFalse(sql:find('DROP COLUMN', 1, true) ~= nil, 'never drops kora columns')
    h.assertFalse(sql:find('MODIFY COLUMN `state`', 1, true) ~= nil, 'kora state ENUM is left alone')
end)

h.test('every 011 statement passes kora_sql runner retry-safety gate', function()
    -- Mirrors kora_sql/server/js/migrate.js: only CREATE TABLE IF NOT EXISTS and
    -- ALTER TABLE with every ADD ... IF NOT EXISTS (and no other DDL/DML) is accepted.
    local sql = read('sql/011_legacy_vehicle_compat.sql'):gsub('%-%-[^\n]*', '')
    local count = 0
    for stmt in sql:gmatch('[^;]+') do
        if stmt:find('%S') then
            count = count + 1
            h.assertTrue(stmt:match('^%s*ALTER%s+TABLE') ~= nil, 'only ALTER TABLE')
            local adds, safe = 0, 0
            for _ in stmt:gmatch('%f[%w]ADD%f[%W]') do adds = adds + 1 end
            for _ in stmt:gmatch('ADD%s+COLUMN%s+IF%s+NOT%s+EXISTS') do safe = safe + 1 end
            h.assertTrue(adds > 0 and adds == safe, 'every ADD is IF NOT EXISTS')
            h.assertFalse(stmt:find('MODIFY', 1, true) ~= nil
                or stmt:find('DROP', 1, true) ~= nil, 'no MODIFY/DROP in the migration file')
        end
    end
    h.assertEqual(count, 2, 'two ALTER statements')
end)

h.test('migration also adds kora\'s own columns for a stock-imported table', function()
    local sql = read('sql/011_legacy_vehicle_compat.sql')
    for _, col in ipairs({ 'job', 'garage_id', 'engine_health', 'body_health', 'last_position', 'impound_fee',
        'impound_lot', 'impounded_at', 'created_at', 'last_updated', 'deleted_at' }) do
        h.assertTrue(sql:find('ADD COLUMN IF NOT EXISTS `' .. col .. '`', 1, true) ~= nil, col)
    end
end)

h.test('update trigger lets kora win a same-statement conflict without touching float precision', function()
    local update
    for _, call in ipairs(handle.sqlCalls.execute) do
        if call.sql:find('compat_update', 1, true) and call.sql:find('CREATE TRIGGER', 1, true) then update = call.sql end
    end
    h.assertTrue(update ~= nil, 'update trigger created')
    -- engine/body are resolved from the kora column first, then kora is re-derived only on a stock-only change.
    local a = update:find('NEW.`engine` = CASE', 1, true)
    local b = update:find('NEW.`engine_health` = CASE', 1, true)
    h.assertTrue(a and b and a < b, 'stock column is resolved before the kora column')
end)

local created = {}
for _, call in ipairs(handle.sqlCalls.execute) do
    if call.sql:find('CREATE TRIGGER', 1, true) then created[#created + 1] = call.sql end
end

h.test('compat triggers are installed and cover every mapped pair', function()
    h.assertEqual(#created, 2, 'insert + update trigger')
    for _, sql in ipairs(created) do
        for _, pair in ipairs({ 'model', 'vehicle', 'garage_id', 'garage', 'engine_health', 'engine',
            'body_health', 'body' }) do
            h.assertTrue(sql:find('NEW.`' .. pair .. '`', 1, true) ~= nil, pair)
        end
        h.assertFalse(sql:find('BEGIN', 1, true) ~= nil, 'single statement, no BEGIN/END')
    end
end)

h.test('superseded model-sync triggers are dropped only after replacements', function()
    local lastCreate, firstDrop = 0, math.huge
    for i, call in ipairs(handle.sqlCalls.execute) do
        if call.sql:find('CREATE TRIGGER', 1, true) then lastCreate = i end
        if call.sql:find('DROP TRIGGER IF EXISTS', 1, true) and i < firstDrop then firstDrop = i end
    end
    h.assertTrue(firstDrop > lastCreate, 'drop after create')
end)

h.report('vehicle_compat_sql')
