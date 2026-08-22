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
        gang = CoreInternal.player.buildGang('none', 0),
        position = { x = 195.17, y = -933.77, z = 30.69, h = 144.0 },
        metadata = {
            hunger = 100, thirst = 100, stress = 0, armor = 0,
            isdead = false, inlaststand = false, ishandcuffed = false,
            jailed = 0, licences = { driver = true, weapon = false },
            phone = {}, bloodtype = 'O+',
        },
        items = {},
        phone = charinfo.phone,
    }
end

-- Compose a job sub-table from the registry definition + a grade.
---@param name string
---@param grade integer
---@return table
function CoreInternal.player.buildJob(name, grade)
    local def = Core.registry.getShared('jobs', name)
    if not def then
        return { name = name, label = name, onduty = true, isboss = false,
                 payment = 0, grade = { name = 'Unknown', level = grade } }
    end
    local g = def.grades and (def.grades[grade] or def.grades[0]) or { name = 'Grade', payment = 0 }
    return {
        name = def.name,
        label = def.label,
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
    local def = Core.registry.getShared('gangs', name)
    if not def then
        return { name = name, label = name, isboss = false, grade = { name = 'None', level = grade } }
    end
    local g = def.grades and (def.grades[grade] or def.grades[0]) or { name = 'None' }
    return {
        name = def.name,
        label = def.label,
        isboss = g.isboss or false,
        grade = { name = g.name or 'None', level = grade },
    }
end
