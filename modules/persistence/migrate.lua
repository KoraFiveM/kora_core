-- Runs kora_core's own SQL migrations at boot via kora_sql's migration runner. Loaded
-- as part of the persistence module (server realm). Migrations are read from
-- sql/*.sql with LoadResourceFile and checksummed Lua-side; kora_sql aborts on a
-- checksum mismatch for an already-applied version.
--
-- CHECKSUM: FiveM Lua has no built-in SHA, and we only need change-DETECTION for
-- a given version (the runner keys by (resource, version)), so a deterministic
-- 64-bit FNV-1a rendered as hex, padded to CHAR(64), is sufficient and stable.

local function fnv1a(str)
    -- 64-bit FNV-1a in pure Lua 5.4 (has 64-bit integers).
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

local VEHICLE_SYNC_TRIGGERS = {
    {
        name = 'qbcore_player_vehicles_model_sync_insert',
        sql = [[CREATE TRIGGER `qbcore_player_vehicles_model_sync_insert`
            BEFORE INSERT ON `player_vehicles` FOR EACH ROW
            SET NEW.`model` = COALESCE(NULLIF(NEW.`model`, ''), NEW.`vehicle`),
                NEW.`vehicle` = COALESCE(NULLIF(NEW.`vehicle`, ''), NEW.`model`)]],
    },
    {
        name = 'qbcore_player_vehicles_model_sync_update',
        sql = [[CREATE TRIGGER `qbcore_player_vehicles_model_sync_update`
            BEFORE UPDATE ON `player_vehicles` FOR EACH ROW
            SET NEW.`model` = CASE
                    WHEN NOT (NEW.`model` <=> OLD.`model`)
                        AND (NEW.`vehicle` <=> OLD.`vehicle`) THEN NEW.`model`
                    WHEN NOT (NEW.`vehicle` <=> OLD.`vehicle`)
                        AND (NEW.`model` <=> OLD.`model`) THEN NEW.`vehicle`
                    ELSE COALESCE(NULLIF(NEW.`model`, ''), NEW.`vehicle`)
                END,
                NEW.`vehicle` = CASE
                    WHEN NOT (NEW.`model` <=> OLD.`model`)
                        AND (NEW.`vehicle` <=> OLD.`vehicle`) THEN NEW.`model`
                    WHEN NOT (NEW.`vehicle` <=> OLD.`vehicle`)
                        AND (NEW.`model` <=> OLD.`model`) THEN NEW.`vehicle`
                    ELSE COALESCE(NULLIF(NEW.`model`, ''), NEW.`vehicle`)
                END]],
    },
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

CreateThread(function()
    -- MySQL may still be starting alongside FXServer. Keep the migration
    -- worker alive so kora_sql's reconnect can recover the whole stack without a
    -- resource/server restart. The timed waits retain a useful status message.
    while not Kora.sql.ready(60000) do
        print('^3[qbcore:migrate]^7 still waiting for qbsql; migrations will resume automatically.')
    end

    local resource = GetCurrentResourceName()
    local applied, err = Kora.sql.migrateFiles(resource, MIGRATIONS, checksum)
    if err then
        print(('^1[qbcore:migrate]^7 migration failed: %s'):format(tostring(err)))
    else
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
        print('^2[qbcore:migrate]^7 schema up to date.')
        -- Warm kora_sql's prepared cache with the hot player statements.
        exports.kora_sql:prepareWarm({
            'SELECT * FROM `players` WHERE `citizenid` = ? AND `deleted_at` IS NULL',
            'SELECT `citizenid`,`cid`,`name`,`charinfo`,`money`,`job`,`gang` FROM `players` WHERE `license` = ? AND `deleted_at` IS NULL ORDER BY `cid`',
        })
        TriggerEvent('qbcore:server:databaseReady')
    end
end)
