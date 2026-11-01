-- Runs kora_core's own SQL migrations at boot via kora_sql's migration runner. Loaded
-- as part of the persistence module (server realm). Migrations are read from
-- sql/*.sql with LoadResourceFile and checksummed Lua-side; kora_sql aborts on a
-- checksum mismatch for an already-applied version.
--
-- CHECKSUM: FiveM Lua has no built-in SHA, and we only need change-DETECTION for
-- a given version (the runner keys by (resource, version)), so a deterministic
-- 64-bit FNV-1a rendered as hex, padded to CHAR(64), is sufficient and stable.

local function fnv1a(str)
    local hash = 0xCBF29CE484222325
    local prime = 0x100000001B3
    for i = 1, #str do
        hash = hash ~ string.byte(str, i)
        hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF
    end
    return hash
end

local function checksum(str)
    -- Combine two FNV passes (forward + reversed) into a 32-hex-char digest,
    -- padded to 64 so it fits the runner's CHAR(64) column deterministically.
    local a = fnv1a(str)
    local b = fnv1a(str:reverse())
    return (('%016x%016x'):format(a, b) .. string.rep('0', 32))
end

-- Legacy vehicle-column sync (see sql/011_legacy_vehicle_compat.sql and
-- docs/vehicles-compat.md). kora's columns win when both sides change in one
-- statement. Each trigger is ONE SET statement (no BEGIN/END, so it survives
-- kora_sql's multi-statement guard); MariaDB/MySQL evaluate the assignments
-- left to right, so later assignments read the already-resolved kora value.
local function clamp16(expr)
    return ('GREATEST(0, LEAST(65535, ROUND(%s)))'):format(expr)
end

local VEHICLE_SYNC_TRIGGERS = {
    {
        name = 'qbcore_player_vehicles_compat_insert',
        sql = ([[CREATE TRIGGER `qbcore_player_vehicles_compat_insert`
            BEFORE INSERT ON `player_vehicles` FOR EACH ROW
            SET NEW.`model` = COALESCE(NULLIF(NEW.`model`, ''), NEW.`vehicle`),
                NEW.`vehicle` = NEW.`model`,
                NEW.`garage_id` = COALESCE(NULLIF(NEW.`garage_id`, ''), NEW.`garage`),
                NEW.`garage` = NEW.`garage_id`,
                NEW.`engine_health` = CASE WHEN NEW.`engine` IS NOT NULL
                    THEN %s ELSE NEW.`engine_health` END,
                NEW.`engine` = COALESCE(NEW.`engine`, NEW.`engine_health`),
                NEW.`body_health` = CASE WHEN NEW.`body` IS NOT NULL
                    THEN %s ELSE NEW.`body_health` END,
                NEW.`body` = COALESCE(NEW.`body`, NEW.`body_health`)]]):format(
            clamp16('NEW.`engine`'), clamp16('NEW.`body`')),
    },
    {
        name = 'qbcore_player_vehicles_compat_update',
        sql = ([[CREATE TRIGGER `qbcore_player_vehicles_compat_update`
            BEFORE UPDATE ON `player_vehicles` FOR EACH ROW
            SET NEW.`model` = CASE
                    WHEN NOT (NEW.`vehicle` <=> OLD.`vehicle`)
                        AND (NEW.`model` <=> OLD.`model`) THEN NEW.`vehicle`
                    ELSE COALESCE(NULLIF(NEW.`model`, ''), NEW.`vehicle`)
                END,
                NEW.`vehicle` = NEW.`model`,
                NEW.`garage_id` = CASE
                    WHEN NOT (NEW.`garage` <=> OLD.`garage`)
                        AND (NEW.`garage_id` <=> OLD.`garage_id`) THEN NEW.`garage`
                    ELSE NEW.`garage_id`
                END,
                NEW.`garage` = NEW.`garage_id`,
                NEW.`engine` = CASE
                    WHEN NOT (NEW.`engine_health` <=> OLD.`engine_health`) THEN NEW.`engine_health`
                    WHEN NOT (NEW.`engine` <=> OLD.`engine`) THEN COALESCE(NEW.`engine`, NEW.`engine_health`)
                    ELSE NEW.`engine`
                END,
                NEW.`engine_health` = CASE
                    WHEN (NEW.`engine_health` <=> OLD.`engine_health`)
                        AND NOT (NEW.`engine` <=> OLD.`engine`)
                        THEN %s ELSE NEW.`engine_health` END,
                NEW.`body` = CASE
                    WHEN NOT (NEW.`body_health` <=> OLD.`body_health`) THEN NEW.`body_health`
                    WHEN NOT (NEW.`body` <=> OLD.`body`) THEN COALESCE(NEW.`body`, NEW.`body_health`)
                    ELSE NEW.`body`
                END,
                NEW.`body_health` = CASE
                    WHEN (NEW.`body_health` <=> OLD.`body_health`)
                        AND NOT (NEW.`body` <=> OLD.`body`)
                        THEN %s ELSE NEW.`body_health` END]]):format(
            clamp16('NEW.`engine`'), clamp16('NEW.`body`')),
    },
}

-- Superseded by the compat triggers above (model/vehicle is handled there).
local LEGACY_VEHICLE_TRIGGERS = {
    'qbcore_player_vehicles_model_sync_insert',
    'qbcore_player_vehicles_model_sync_update',
}

local function ensureVehicleSyncTriggers()
    local rows, queryErr = Kora.sql.query([[SELECT `TRIGGER_NAME` AS `name`
        FROM `information_schema`.`TRIGGERS`
        WHERE `TRIGGER_SCHEMA` = DATABASE()
            AND `EVENT_OBJECT_TABLE` = 'player_vehicles'
            AND `TRIGGER_NAME` IN (?, ?)]], {
        VEHICLE_SYNC_TRIGGERS[1].name, VEHICLE_SYNC_TRIGGERS[2].name,
    })
    if not rows then return false, queryErr end

    local existing = {}
    for _, row in ipairs(rows) do existing[row.name] = true end
    for _, trigger in ipairs(VEHICLE_SYNC_TRIGGERS) do
        if not existing[trigger.name] then
            local created, createErr = Kora.sql.execute(trigger.sql)
            if created == nil and createErr then return false, createErr end
        end
    end
    -- Drop the old model-only triggers only once the replacements exist.
    for _, name in ipairs(LEGACY_VEHICLE_TRIGGERS) do
        Kora.sql.execute(('DROP TRIGGER IF EXISTS `%s`'):format(name))
    end
    return true
end

-- Boot-time steps that kora_sql's runner cannot express (it only accepts
-- CREATE TABLE IF NOT EXISTS / ALTER ... ADD ... IF NOT EXISTS). They inspect
-- information_schema first, so they are idempotent and do not need any
-- MariaDB-only `IF [NOT] EXISTS` clause support.
local KORA_STATE_ENUM = "enum('out','garaged','impounded')"
-- Same strings, ordered so that MariaDB's numeric enum index of a stock script's
-- integer write lines up with stock's meaning (1 garaged, 2 impounded); 0 (out)
-- has no enum index and is rejected loudly rather than stored inverted.
local STOCK_ALIGNED_STATE_ENUM = "enum('garaged','impounded','out')"

local function readVehicleColumns()
    local rows, err = Kora.sql.query([[SELECT `COLUMN_NAME` AS `name`, `DATA_TYPE` AS `data_type`,
            `COLUMN_TYPE` AS `column_type`, `IS_NULLABLE` AS `is_nullable`,
            `COLUMN_DEFAULT` AS `column_default`, `CHARACTER_SET_NAME` AS `charset`,
            `COLLATION_NAME` AS `collation`
        FROM `information_schema`.`COLUMNS`
        WHERE `TABLE_SCHEMA` = DATABASE() AND `TABLE_NAME` = 'player_vehicles']])
    if not rows then return nil, err end
    local cols = {}
    for _, row in ipairs(rows) do cols[row.name] = row end
    return cols
end

local function isNull(value)
    return value == nil or value == Kora.sql.NULL or tostring(value):upper() == 'NULL'
end

-- Column definition that preserves type + charset/collation (a bare MODIFY would
-- silently re-collate a text column to the table default).
local function nullableDefinition(col)
    local ctype = tostring(col.column_type or '')
    if not ctype:match('^[%w%(%),%s]+$') then return nil end
    local parts = { ctype }
    if not isNull(col.charset) and not isNull(col.collation)
        and tostring(col.charset):match('^[%w_]+$') and tostring(col.collation):match('^[%w_]+$') then
        parts[#parts + 1] = ('CHARACTER SET %s COLLATE %s'):format(col.charset, col.collation)
    end
    parts[#parts + 1] = 'NULL DEFAULT NULL'
    return table.concat(parts, ' ')
end

-- Stock columns are NOT NULL (`vehicle`, no default) or DEFAULT 1000 (`engine`,
-- `body`). A kora-style INSERT naming only model/garage_id/engine_health would
-- then be rejected, or have its health overwritten by the stock default (the
-- trigger cannot tell an omitted column from an explicit one). Make them
-- NULL-default; the triggers fill them from kora's columns.
local function relaxLegacyVehicleColumns(cols)
    for _, name in ipairs({ 'model', 'vehicle', 'engine', 'body' }) do
        local col = cols[name]
        if col and (col.is_nullable == 'NO' or not isNull(col.column_default)) then
            local definition = nullableDefinition(col)
            if not definition then
                return false, ('unrecognised definition of player_vehicles.%s'):format(name)
            end
            local ok, err = Kora.sql.execute(
                ('ALTER TABLE `player_vehicles` MODIFY COLUMN `%s` %s'):format(name, definition))
            if ok == nil and err then return false, err end
        end
    end
    return true
end

-- Copy stock values into kora's columns for rows imported from stock qb-core.
-- garage_id is idempotent on its own; the health columns need `legacyHealth`
-- because 011 adds them with a DEFAULT 1000 that is indistinguishable afterwards.
-- `last_updated` is pinned so the backfill does not look like a modification.
local function backfillLegacyVehicleRows(legacyHealth)
    local statements = {
        [[UPDATE `player_vehicles` SET `garage_id` = `garage`, `last_updated` = `last_updated`
            WHERE `garage_id` IS NULL AND `garage` IS NOT NULL]],
        [[UPDATE `player_vehicles` SET `garage` = `garage_id`, `last_updated` = `last_updated`
            WHERE `garage` IS NULL AND `garage_id` IS NOT NULL]],
        [[UPDATE `player_vehicles` SET `engine` = `engine_health`, `last_updated` = `last_updated`
            WHERE `engine` IS NULL]],
        [[UPDATE `player_vehicles` SET `body` = `body_health`, `last_updated` = `last_updated`
            WHERE `body` IS NULL]],
    }
    -- Health from stock goes first so the NULL-fill above never copies the 1000 default back.
    if legacyHealth.engine then
        table.insert(statements, 1, ('UPDATE `player_vehicles` SET `engine_health` = %s, '
            .. '`last_updated` = `last_updated` WHERE `engine` IS NOT NULL'):format(clamp16('`engine`')))
    end
    if legacyHealth.body then
        table.insert(statements, 1, ('UPDATE `player_vehicles` SET `body_health` = %s, '
            .. '`last_updated` = `last_updated` WHERE `body` IS NOT NULL'):format(clamp16('`body`')))
    end
    for _, sql in ipairs(statements) do
        local ok, err = Kora.sql.execute(sql)
        if ok == nil and err then return false, err end
    end
    return true
end

-- Detect (before migrating) a stock-qb table whose kora health columns are about
-- to be created, so their values can be backfilled from `engine`/`body`.
local function detectLegacyHealth()
    local cols = readVehicleColumns()
    if not cols then return {} end
    return {
        engine = cols.engine ~= nil and cols.engine_health == nil,
        body = cols.body ~= nil and cols.body_health == nil,
    }
end

local function reconcileLegacyVehicleTable(legacyHealth)
    local cols, colErr = readVehicleColumns()
    if not cols then return false, colErr end
    local ok, err = relaxLegacyVehicleColumns(cols)
    if not ok then return false, err end
    return backfillLegacyVehicleRows(legacyHealth)
end

local INTEGER_TYPES = {
    tinyint = true, smallint = true, mediumint = true, int = true, integer = true, bigint = true,
}

-- `state`: kora's column is an ENUM of strings and every kora writer/reader uses
-- the strings; stock scripts use integers (0 out, 1 garaged, 2 impounded). One
-- column cannot serve both (see docs/vehicles-compat.md). Default: leave it
-- alone, warn if it is not an ENUM. Config.persistence.legacyVehicleState = true
-- converts a stock INT column to kora's ENUM (explicit 0/1/2 -> string mapping,
-- never the enum-index reinterpretation) and orders the ENUM so stock integer
-- 1/2 writes land on garaged/impounded.
local function ensureVehicleState(cols)
    local col = cols.state
    if not col then return true end
    if Config.persistence.legacyVehicleState ~= true then
        if col.data_type ~= 'enum' then
            print(('^3[qbcore:migrate]^7 player_vehicles.state is %s, not kora\'s ENUM: kora_garages, kora_dealership and the core garage code write strings and will fail. Set Config.persistence.legacyVehicleState = true to convert it (stock integer-state scripts then only partly work; see docs/vehicles-compat.md).'):format(tostring(col.column_type)))
        end
        return true
    end

    local currentType = col.column_type
    if INTEGER_TYPES[col.data_type] then
        local ok, err = Kora.sql.execute(
            'ALTER TABLE `player_vehicles` MODIFY COLUMN `state` VARCHAR(16) NULL DEFAULT NULL')
        if ok == nil and err then return false, err end
        col.data_type = 'varchar'
    end
    if col.data_type == 'varchar' then
        -- Also the resume point if a previous boot died between the two ALTERs.
        local ok, err = Kora.sql.execute([[UPDATE `player_vehicles`
            SET `state` = CASE
                    WHEN `state` = '0' THEN 'out'
                    WHEN `state` = '1' THEN 'garaged'
                    WHEN `state` = '2' THEN 'impounded'
                    WHEN `state` IS NULL OR `state` = '' THEN 'garaged'
                    ELSE `state` END,
                `last_updated` = `last_updated`]])
        if ok == nil and err then return false, err end
        currentType = nil
    elseif col.data_type ~= 'enum' then
        return false, ('unsupported player_vehicles.state type %s'):format(tostring(col.column_type))
    end

    if currentType == STOCK_ALIGNED_STATE_ENUM then return true end
    if currentType ~= nil and currentType ~= KORA_STATE_ENUM then
        print('^3[qbcore:migrate]^7 player_vehicles.state has a custom ENUM definition; leaving it unchanged.')
        return true
    end
    local ok, err = Kora.sql.execute(("ALTER TABLE `player_vehicles` MODIFY COLUMN `state` %s "
        .. "NOT NULL DEFAULT 'garaged'"):format(STOCK_ALIGNED_STATE_ENUM))
    if ok == nil and err then return false, err end
    return true
end

local MIGRATIONS = {
    { version = 1, name = 'core',        file = 'sql/001_core.sql' },
    { version = 2, name = 'identifiers', file = 'sql/002_identifiers.sql' },
}

-- Generated columns are opt-in.
if Config.persistence.generatedColumns then
    MIGRATIONS[#MIGRATIONS + 1] = {
        version = 3,
        name = 'generated_columns',
        file = 'sql/003_generated_columns.sql',
        -- v3 originally shipped without IF NOT EXISTS. Its replacement is
        -- retry-safe, and this exact old digest is the only historic form the
        -- runner may accept rather than treating as unexplained schema drift.
        acceptedChecksums = {
            'c55391eb33cd16ea6e66f4d337786e5800000000000000000000000000000000',
        },
    }
end

-- Unconditional, fixed version number 4 regardless of whether the opt-in
-- migration above ran -- the runner keys applied migrations by this literal
-- number, so it must stay stable independent of Config.persistence.generatedColumns.
MIGRATIONS[#MIGRATIONS + 1] = { version = 4, name = 'users', file = 'sql/004_users.sql' }
MIGRATIONS[#MIGRATIONS + 1] = { version = 5, name = 'vehicles', file = 'sql/005_vehicles.sql' }
MIGRATIONS[#MIGRATIONS + 1] = { version = 6, name = 'legacy_players', file = 'sql/006_legacy_players.sql' }
MIGRATIONS[#MIGRATIONS + 1] = { version = 7, name = 'legacy_vehicle_finance', file = 'sql/007_legacy_vehicle_finance.sql' }
MIGRATIONS[#MIGRATIONS + 1] = { version = 8, name = 'active_character_slots', file = 'sql/008_active_character_slots.sql' }
MIGRATIONS[#MIGRATIONS + 1] = { version = 9, name = 'legacy_vehicle_model', file = 'sql/009_legacy_vehicle_model.sql' }
MIGRATIONS[#MIGRATIONS + 1] = { version = 10, name = 'player_column_operations', file = 'sql/010_player_column_operations.sql' }
MIGRATIONS[#MIGRATIONS + 1] = { version = 11, name = 'legacy_vehicle_compat', file = 'sql/011_legacy_vehicle_compat.sql' }

CreateThread(function()
    -- MySQL may still be starting alongside FXServer. Keep the migration
    -- worker alive so kora_sql's reconnect can recover the whole stack without a
    -- resource/server restart. The timed waits retain a useful status message.
    while not Kora.sql.ready(60000) do
        print('^3[qbcore:migrate]^7 still waiting for qbsql; migrations will resume automatically.')
    end

    local resource = GetCurrentResourceName()
    local legacyHealth = detectLegacyHealth()
    local applied, err = Kora.sql.migrateFiles(resource, MIGRATIONS, checksum)
    if err then
        print(('^1[qbcore:migrate]^7 migration failed: %s'):format(tostring(err)))
    else
        local reconciled, reconcileErr = reconcileLegacyVehicleTable(legacyHealth)
        if not reconciled then
            print(('^1[qbcore:migrate]^7 legacy vehicle column reconcile failed: %s'):format(tostring(reconcileErr)))
        end
        local synced, syncErr = Kora.sql.execute([[UPDATE `player_vehicles`
            SET `model` = COALESCE(NULLIF(`model`, ''), `vehicle`),
                `vehicle` = COALESCE(NULLIF(`vehicle`, ''), `model`)
            WHERE (`model` IS NULL OR `model` = '') OR (`vehicle` IS NULL OR `vehicle` = '')]])
        if synced == nil and syncErr then
            print(('^1[qbcore:migrate]^7 vehicle column sync failed: %s'):format(tostring(syncErr)))
        end
        local triggersReady, triggerErr = ensureVehicleSyncTriggers()
        if not triggersReady then
            print(('^1[qbcore:migrate]^7 vehicle sync trigger setup failed: %s'):format(tostring(triggerErr)))
        end
        local stateCols = readVehicleColumns()
        if stateCols then
            local stateOk, stateErr = ensureVehicleState(stateCols)
            if not stateOk then
                print(('^1[qbcore:migrate]^7 vehicle state setup failed: %s'):format(tostring(stateErr)))
            end
        end
        print('^2[qbcore:migrate]^7 schema up to date.')
        -- Warm kora_sql's prepared cache with the hot player statements.
        exports.kora_sql:prepareWarm({
            'SELECT * FROM `players` WHERE `citizenid` = ? AND `deleted_at` IS NULL',
            'SELECT `citizenid`,`cid`,`name`,`charinfo`,`money`,`job`,`gang` FROM `players` WHERE `license` = ? AND `deleted_at` IS NULL ORDER BY `cid`',
        })
        TriggerEvent('qbcore:server:databaseReady')
    end
end)
