local function clamp16(expr)
    return ('GREATEST(0, LEAST(65535, ROUND(%s)))'):format(expr)
end

local VEHICLE_SYNC_TRIGGERS = {
    {
        name = 'kora_core_player_vehicles_compat_insert',
        sql = ([[CREATE TRIGGER `kora_core_player_vehicles_compat_insert`
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
        name = 'kora_core_player_vehicles_compat_update',
        sql = ([[CREATE TRIGGER `kora_core_player_vehicles_compat_update`
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

local function logSchemaWarnings(reports)
    for _, report in ipairs(reports or {}) do
        for _, warning in ipairs(report.warnings or {}) do
            print(('^3[qbcore:schema]^7 %s'):format(tostring(warning)))
        end
    end
end

local function applySchema()
    local reports, err = Kora.sql.ensureTables(KoraCoreSchema)
    if err then return false, err end
    logSchemaWarnings(reports)
    if Config.persistence.generatedColumns then
        local generated, generatedErr = Kora.sql.ensureTables(KoraCoreGeneratedSchema)
        if generatedErr then return false, generatedErr end
        logSchemaWarnings(generated)
    end
    return true
end

CreateThread(function()
    while not Kora.sql.ready(60000) do
        print('^3[qbcore:schema]^7 still waiting for qbsql; schema setup will resume automatically.')
    end

    local applied, err = applySchema()
    if not applied then
        print(('^1[qbcore:schema]^7 schema setup failed: %s'):format(tostring(err)))
        return
    end
    local triggersReady, triggerErr = ensureVehicleSyncTriggers()
    if not triggersReady then
        print(('^1[qbcore:schema]^7 vehicle sync trigger setup failed: %s'):format(tostring(triggerErr)))
    end
    print('^2[qbcore:schema]^7 schema up to date.')
    exports.kora_sql:prepareWarm({
        'SELECT * FROM `players` WHERE `citizenid` = ? AND `deleted_at` IS NULL',
        'SELECT `citizenid`,`cid`,`name`,`charinfo`,`money`,`job`,`gang` FROM `players` WHERE `license` = ? AND `deleted_at` IS NULL ORDER BY `cid`',
    })
    TriggerEvent('qbcore:server:databaseReady')
end)
