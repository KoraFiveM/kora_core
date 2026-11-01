-- Boot-time player_vehicles steps in modules/persistence/migrate.lua that kora_sql's
-- runner cannot express: nullability relaxation, backfill and the opt-in `state`
-- conversion. The real SQL behaviour is proven on MariaDB by test/sql/scratch/run.sh;
-- here the statement sequence is checked against mocked information_schema rows.
local h = dofile('test/harness.lua')

local function boot(columns, optIn)
    local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
    dofile('config.lua')
    dofile('build/initiate.lua')
    Config.persistence.legacyVehicleState = optIn or false
    Kora.sql.migrateFiles = function() return true end
    Kora.sql.query = function(sql)
        if sql:find('information_schema', 1, true) and sql:find('`COLUMNS`', 1, true) then return columns end
        return {}
    end
    local printed = {}
    local realPrint = print
    print = function(...) printed[#printed + 1] = table.concat({ ... }, ' ') end
    dofile('modules/persistence/migrate.lua')
    handle.step()
    print = realPrint
    return handle.sqlCalls.execute, printed
end

local function col(name, dataType, columnType, nullable, default, charset, collation)
    return { name = name, data_type = dataType, column_type = columnType, is_nullable = nullable,
        column_default = default, charset = charset, collation = collation }
end

local function find(calls, needle)
    for i, call in ipairs(calls) do if call.sql:find(needle, 1, true) then return i, call.sql end end
end

local function stockColumns(state)
    return {
        col('vehicle', 'varchar', 'varchar(50)', 'NO', nil, 'utf8mb4', 'utf8mb4_general_ci'),
        col('model', 'varchar', 'varchar(60)', 'YES', 'NULL', 'utf8mb4', 'utf8mb4_general_ci'),
        col('engine', 'float', 'float', 'NO', '1000'),
        col('body', 'float', 'float', 'YES', 'NULL'),
        state,
    }
end
local intState = col('state', 'int', 'int(11)', 'YES', '1')

h.test('stock-style NOT NULL / DEFAULT 1000 columns are relaxed, preserving charset', function()
    local calls = boot(stockColumns(intState))
    local _, vehicle = find(calls, 'MODIFY COLUMN `vehicle`')
    h.assertTrue(vehicle ~= nil and vehicle:find('varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL DEFAULT NULL', 1, true) ~= nil, 'vehicle relaxed')
    h.assertTrue(find(calls, 'MODIFY COLUMN `engine` float NULL DEFAULT NULL') ~= nil, 'engine relaxed')
    h.assertTrue(find(calls, 'MODIFY COLUMN `model`') == nil, 'already nullable model untouched')
    h.assertTrue(find(calls, 'MODIFY COLUMN `body`') == nil, 'already NULL-default body untouched')
end)

h.test('default config never converts a stock INT state, and warns', function()
    local calls, printed = boot(stockColumns(intState))
    h.assertTrue(find(calls, 'MODIFY COLUMN `state`') == nil, 'state untouched')
    local warned = false
    for _, line in ipairs(printed) do if line:find('legacyVehicleState', 1, true) then warned = true end end
    h.assertTrue(warned, 'warning names the opt-in')
end)

h.test('opt-in converts INT state via explicit 0/1/2 mapping, then to the ordered ENUM', function()
    local calls = boot(stockColumns(col('state', 'int', 'int(11)', 'YES', '1')), true)
    local toVarchar = find(calls, 'MODIFY COLUMN `state` VARCHAR(16)')
    local map, mapSql = find(calls, "WHEN `state` = '0' THEN 'out'")
    local toEnum, enumSql = find(calls, "MODIFY COLUMN `state` enum('garaged','impounded','out')")
    h.assertTrue(toVarchar and map and toEnum and toVarchar < map and map < toEnum, 'varchar -> map -> enum order')
    h.assertTrue(mapSql:find("WHEN `state` = '1' THEN 'garaged'", 1, true) ~= nil
        and mapSql:find("WHEN `state` = '2' THEN 'impounded'", 1, true) ~= nil, 'explicit mapping')
    h.assertTrue(enumSql:find("DEFAULT 'garaged'", 1, true) ~= nil, 'kora default kept')
end)

h.test('opt-in on kora ENUM only reorders; custom ENUM and already-ordered are left alone', function()
    local calls = boot({ col('state', 'enum', "enum('out','garaged','impounded')", 'NO', "'garaged'") }, true)
    h.assertTrue(find(calls, "MODIFY COLUMN `state` enum('garaged','impounded','out')") ~= nil, 'reordered')
    h.assertTrue(find(calls, 'VARCHAR(16)') == nil, 'no int round-trip for an ENUM')
    calls = boot({ col('state', 'enum', "enum('garaged','impounded','out')", 'NO', "'garaged'") }, true)
    h.assertTrue(find(calls, 'MODIFY COLUMN `state`') == nil, 'idempotent')
    calls = boot({ col('state', 'enum', "enum('a','b')", 'NO', "'a'") }, true)
    h.assertTrue(find(calls, 'MODIFY COLUMN `state`') == nil, 'custom enum untouched')
end)

h.test('a boot that died between the two state ALTERs resumes', function()
    local calls = boot({ col('state', 'varchar', 'varchar(16)', 'YES', 'NULL', 'utf8mb4', 'utf8mb4_unicode_ci') }, true)
    h.assertTrue(find(calls, "WHEN `state` = '0' THEN 'out'") ~= nil, 'mapping re-run')
    h.assertTrue(find(calls, "MODIFY COLUMN `state` enum('garaged','impounded','out')") ~= nil, 'enum applied')
end)

h.test('health backfill only copies stock -> kora when kora health columns were just missing', function()
    local calls = boot({ col('engine', 'float', 'float', 'YES', 'NULL'), col('body', 'float', 'float', 'YES', 'NULL') })
    h.assertTrue(find(calls, 'SET `engine_health` = GREATEST') ~= nil, 'engine_health from engine')
    calls = boot({ col('engine', 'float', 'float', 'YES', 'NULL'), col('engine_health', 'smallint', 'smallint(5) unsigned', 'NO', '1000') })
    h.assertTrue(find(calls, 'SET `engine_health` = GREATEST') == nil, 'not when kora column already existed')
    h.assertTrue(find(calls, 'SET `engine` = `engine_health`') ~= nil, 'NULL stock side is filled from kora')
end)

h.report('vehicle_compat_boot')
