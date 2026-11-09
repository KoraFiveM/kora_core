CoreInternal = CoreInternal or {}
CoreInternal.player = CoreInternal.player or {}

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
            jailed = 0, injail = 0,
            licences = { driver = true, weapon = false },
            phone = {}, bloodtype = 'O+',
            fingerprint = ('%s%s%s%s%s%s'):format(
                Core.util.randomStr(2), Core.util.randomInt(3), Core.util.randomStr(1),
                Core.util.randomInt(2), Core.util.randomStr(3), Core.util.randomInt(4)),
            walletid = ('QB-%s'):format(Core.util.randomInt(8)),
        },
        items = {},
        phone = charinfo.phone,
    }
end

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
