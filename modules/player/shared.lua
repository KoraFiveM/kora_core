-- Core.player (shared realm) -- the PlayerData shape helpers and the root-key ->
-- DB-column map used by the funnel. Kept in the shared realm so both the server
-- funnel and any client-side shape checks agree on the mapping.

CoreInternal = CoreInternal or {}
CoreInternal.player = CoreInternal.player or {}

-- Root key of PlayerData -> the DB column that persists it. The funnel marks a
-- column dirty from path[1]; a root key absent here does not persist (and the
-- compat SetPlayerData shim warns when that happens). `license`/`cid` are
-- intentionally ABSENT: they are immutable after character creation and must
-- never appear in a save write-set (see the schema's two-unique-key hazard).
CoreInternal.player.COLUMN_FOR = {
    charinfo = 'charinfo',
    job = 'job',
    gang = 'gang',
    money = 'money',
    metadata = 'metadata',
    items = 'inventory',
    position = 'position',
    name = 'name',
    phone = 'phone_number',
}

-- Build a fresh PlayerData blob for a NEW character.
---@param citizenid string
---@param license string
---@param cid integer
---@param charinfo table
---@return table
function CoreInternal.player.freshData(citizenid, license, cid, charinfo)
    local money = {}
    for _, acc in ipairs(Config.money.types) do
        money[acc] = (Config.money.default and Config.money.default[acc]) or 0
    end

    local defaultJob = CoreInternal.player.buildJob(Config.jobs.defaultJob, Config.jobs.defaultGrade)
    return {
        citizenid = citizenid,
        license = license,
        cid = cid,
        name = ('%s %s'):format(charinfo.firstname or 'John', charinfo.lastname or 'Doe'),
        money = money,
        charinfo = charinfo,
        job = defaultJob,
        gang = CoreInternal.player.buildGang('none', 1),
        position = { x = 195.17, y = -933.77, z = 30.69, h = 144.0 },
        metadata = {
            hunger = 100, thirst = 100, stress = 0, armor = 0,
            isdead = false, inlaststand = false, ishandcuffed = false,
            jailed = 0, injail = 0, -- injail mirrors jailed for legacy readers, see modules/jail/server.lua
            licences = { driver = true, weapon = false },
            phone = {}, bloodtype = 'O+',
            -- Real qb-core seeds both on every new character (config.lua's
            -- PlayerDefaults.metadata) -- fingerprint feeds the police flow's
            -- fingerprint-scan feature, walletid feeds any wallet/banking
            -- script that reads it. Real qb-core pre-checks uniqueness
            -- against the DB before accepting a candidate; this rebuild
            -- follows Core.identity.generateCitizenId's own established
            -- convention instead (a plain random candidate, no async
            -- pre-check -- a JSON metadata field has no DB unique index to
            -- collide against here anyway, unlike citizenid's real column).
            fingerprint = ('%s%s%s%s%s%s'):format(
                Core.util.randomStr(2), Core.util.randomInt(3), Core.util.randomStr(1),
                Core.util.randomInt(2), Core.util.randomStr(3), Core.util.randomInt(4)),
            walletid = ('QB-%s'):format(Core.util.randomInt(8)),
        },
        items = {},
        phone = charinfo.phone,
    }
end

-- Compose a job sub-table from the registry definition + a grade.
--
-- `type` IS copied here (defaulting to 'none'), unlike `blip` and the rest of
-- the registry record. It has to be: real qb-core puts a job type on
    -- PlayerData.job, and both police and ambulance flows gate roughly thirty
-- call sites on `Player.PlayerData.job.type == 'leo'` / `== 'ems'`. Without it
-- every one of those checks is silently false and those resources simply don't
-- work -- as was `compat/server/qb-core.lua`'s own `jd.type == job` branch in
-- GetPlayersByJob. It is also what Core.jobs' job-type index and any dispatch
-- system key off, so a per-consumer registry lookup would mean re-deriving the
-- same mapping in every caller.
--
-- `blip` deliberately stays registry-only: nothing reads it off PlayerData, and
-- copying a nested table into the persisted job blob for no reader would just
-- widen the column.
---@param name string
---@param grade integer
---@return table
function CoreInternal.player.buildJob(name, grade)
    grade = math.max(1, math.floor(tonumber(grade) or 1))
    local def = Core.registry.getShared('jobs', name)
    if not def then
        return { name = name, label = name, type = 'none', onduty = true, isboss = false,
                 payment = 0, grade = { name = 'Unknown', level = grade } }
    end
    local g = def.grades and (def.grades[grade] or def.grades[1]) or { name = 'Grade', payment = 0 }
    return {
        name = def.name,
        label = def.label,
        type = def.type or 'none',
        payment = g.payment or 0,
        onduty = def.defaultDuty ~= false,
        isboss = g.isboss or false,
        grade = { name = g.name or 'Grade', level = grade },
    }
end

-- Compose a gang sub-table from the registry definition + a grade.
---@param name string
---@param grade integer
---@return table
function CoreInternal.player.buildGang(name, grade)
    grade = math.max(1, math.floor(tonumber(grade) or 1))
    local def = Core.registry.getShared('gangs', name)
    if not def then
        return { name = name, label = name, isboss = false, grade = { name = 'None', level = grade } }
    end
    local g = def.grades and (def.grades[grade] or def.grades[1]) or { name = 'None' }
    return {
        name = def.name,
        label = def.label,
        isboss = g.isboss or false,
        grade = { name = g.name or 'None', level = grade },
    }
end
