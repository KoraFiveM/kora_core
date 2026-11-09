local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('build/initiate.lua')

local ensured, migrateCalls = nil, 0
Kora.sql.ensureTables = function(specs) ensured = ensured or specs; return {} end
Kora.sql.migrate = function() migrateCalls = migrateCalls + 1; return true end
Kora.sql.query = function() return {} end
dofile('modules/persistence/schema.lua')
dofile('modules/persistence/boot.lua')
handle.step()

local function spec(name)
    for _, s in ipairs(KoraCoreSchema) do if s.name == name then return s end end
end

local function column(tbl, name)
    for _, c in ipairs(tbl.columns) do if c.name == name then return c end end
end

h.test('boot applies the declarative schema and runs no migration', function()
    h.assertTrue(ensured == KoraCoreSchema, 'ensureTables receives KoraCoreSchema')
    h.assertEqual(migrateCalls, 0, 'no migrate call')
    for _, call in ipairs(handle.sqlCalls.execute) do
        h.assertFalse(call.sql:find('ALTER TABLE', 1, true) ~= nil, 'no ALTER TABLE at boot')
        h.assertFalse(call.sql:find('UPDATE `player_vehicles`', 1, true) ~= nil, 'no vehicle backfill at boot')
    end
end)

h.test('schema declares every kora_core table', function()
    for _, name in ipairs({ 'players', 'player_identifiers', 'inventories', 'bans', 'users',
        'player_vehicles', 'kora_core_player_column_operations' }) do
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
    h.assertEqual(column(vehicles, 'model').null, true, 'model is nullable')
end)

h.test('opt-in generated columns extend players without recreating it', function()
    local generated = KoraCoreGeneratedSchema[1]
    h.assertTrue(generated.extend == true and generated.name == 'players', 'extend spec on players')
    for _, name in ipairs({ 'cash', 'bank', 'job_name' }) do
        h.assertTrue(column(generated, name).generated.stored == false, name .. ' is VIRTUAL')
    end
end)

h.test('update trigger lets kora win a same-statement conflict without touching float precision', function()
    local update
    for _, call in ipairs(handle.sqlCalls.execute) do
        if call.sql:find('compat_update', 1, true) and call.sql:find('CREATE TRIGGER', 1, true) then update = call.sql end
    end
    h.assertTrue(update ~= nil, 'update trigger created')
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

h.report('vehicle_compat_sql')
