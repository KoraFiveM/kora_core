-- Legacy player_vehicles compat: the schema declares every stock column, the
-- residual migration is registered, and the installed triggers map both directions.
-- The real-SQL behaviour is tested by test/sql/scratch/run.sh.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('build/initiate.lua')

local ensured, migrations
Kora.sql.ensureTables = function(specs) ensured = ensured or specs; return {} end
Kora.sql.migrate = function(_, list) migrations = list; return true end
Kora.sql.query = function() return {} end
dofile('modules/persistence/schema.lua')
dofile('modules/persistence/migrate.lua')
handle.step()

local function spec(name)
    for _, s in ipairs(KoraCoreSchema) do if s.name == name then return s end end
end

local function column(tbl, name)
    for _, c in ipairs(tbl.columns) do if c.name == name then return c end end
end

h.test('boot applies the declarative schema and the v111 residual migration', function()
    h.assertTrue(ensured == KoraCoreSchema, 'ensureTables receives KoraCoreSchema')
    local found
    for _, m in ipairs(migrations or {}) do if m.version == 111 then found = m end end
    h.assertTrue(found ~= nil and found.sql ~= nil and found.checksum ~= nil, 'v111 registered with sql + checksum')
    for _, m in ipairs(migrations) do h.assertTrue(m.version > 11, 'no collision with the retired v1-v11') end
end)

h.test('schema declares every kora_core table', function()
    for _, name in ipairs({ 'players', 'player_identifiers', 'inventories', 'bans', 'users',
        'player_vehicles', 'qbcore_player_column_operations' }) do
        h.assertTrue(spec(name) ~= nil, name)
    end
    h.assertTrue(column(spec('players'), 'active_cid').generated ~= nil, 'players.active_cid is generated')
end)

h.test('player_vehicles declares every stock column and never extends/drops', function()
    local vehicles = spec('player_vehicles')
    for _, col in ipairs({ 'license', 'hash', 'fakeplate', 'garage', 'engine', 'body', 'depotprice',
        'drivingdistance', 'status', 'balance', 'paymentamount', 'paymentsleft', 'financetime', 'vehicle' }) do
        h.assertTrue(column(vehicles, col) ~= nil, col)
    end
    h.assertFalse(vehicles.extend == true, 'player_vehicles is created by kora_core')
    h.assertEqual(table.concat(column(vehicles, 'state').values, ','), 'out,garaged,impounded', 'kora state ENUM is the declared one')
    h.assertEqual(column(vehicles, 'model').null, true, 'model is nullable, matching the live relaxed state')
end)

h.test('opt-in generated columns extend players without recreating it', function()
    local generated = KoraCoreGeneratedSchema[1]
    h.assertTrue(generated.extend == true and generated.name == 'players', 'extend spec on players')
    for _, name in ipairs({ 'cash', 'bank', 'job_name' }) do
        h.assertTrue(column(generated, name).generated.stored == false, name .. ' is VIRTUAL')
    end
end)

h.test('the v111 residual statement passes kora_sql runner retry-safety gate', function()
    -- Mirrors kora_sql/server/js/migrate.js: ALTER TABLE with every ADD ... IF NOT EXISTS
    -- and every DROP INDEX IF EXISTS.
    local stmt
    for _, m in ipairs(migrations) do if m.version == 111 then stmt = m.sql end end
    h.assertTrue(stmt:match('^%s*ALTER%s+TABLE') ~= nil, 'only ALTER TABLE')
    local adds, safeAdds, drops, safeDrops = 0, 0, 0, 0
    for _ in stmt:gmatch('%f[%w]ADD%f[%W]') do adds = adds + 1 end
    for _ in stmt:gmatch('ADD%s+UNIQUE%s+INDEX%s+IF%s+NOT%s+EXISTS') do safeAdds = safeAdds + 1 end
    for _ in stmt:gmatch('%f[%w]DROP%f[%W]') do drops = drops + 1 end
    for _ in stmt:gmatch('DROP%s+INDEX%s+IF%s+EXISTS') do safeDrops = safeDrops + 1 end
    h.assertTrue(adds > 0 and adds == safeAdds, 'every ADD is IF NOT EXISTS')
    h.assertEqual(drops, safeDrops, 'every DROP is DROP INDEX IF EXISTS')
    h.assertFalse(stmt:find('MODIFY', 1, true) ~= nil, 'no MODIFY')
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
