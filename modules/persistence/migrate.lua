-- Runs qbcore's own SQL migrations at boot via qbsql's migration runner. Loaded
-- as part of the persistence module (server realm). Migrations are read from
-- sql/*.sql with LoadResourceFile and checksummed Lua-side; qbsql aborts on a
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

CreateThread(function()
    -- MySQL may still be starting alongside FXServer. Keep the migration
    -- worker alive so qbsql's reconnect can recover the whole stack without a
    -- resource/server restart. The timed waits retain a useful status message.
    while not QB.sql.ready(60000) do
        print('^3[qbcore:migrate]^7 still waiting for qbsql; migrations will resume automatically.')
    end

    local resource = GetCurrentResourceName()
    local applied, err = QB.sql.migrateFiles(resource, MIGRATIONS, checksum)
    if err then
        print(('^1[qbcore:migrate]^7 migration failed: %s'):format(tostring(err)))
    else
        print('^2[qbcore:migrate]^7 schema up to date.')
        -- Warm qbsql's prepared cache with the hot player statements.
        exports.qbsql:prepareWarm({
            'SELECT * FROM `players` WHERE `citizenid` = ? AND `deleted_at` IS NULL',
            'SELECT `citizenid`,`cid`,`name`,`charinfo`,`money`,`job`,`gang` FROM `players` WHERE `license` = ? AND `deleted_at` IS NULL ORDER BY `cid`',
        })
        TriggerEvent('qbcore:server:databaseReady')
    end
end)
