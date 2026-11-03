-- Job rule matcher (both realms) -- the ONE implementation behind the server's
-- `Core.jobs.checkJob(src, rule)` and the client's `Kora.player.checkJob(rule)`.
--
-- Pure: no natives, no Core reads, no allocation. It is loaded twice:
--   * inside kora_core as a shared_script, where it publishes
--     CoreInternal.jobs.matchRule for modules/jobs/server.lua;
--   * inside a CONSUMER's VM by '@kora_core/init.lua', which load()s this file
--     and keeps the returned function. That is why it returns the matcher rather
--     than relying only on a global, and why it is listed in `files`.
--
-- Grades are kora_core's native ONE-based levels (legacy qb grade 0 = level 1),
-- the same numbers PlayerData.job.grade.level holds on both realms.

---@class KoraJobRule
---@field name? string|string[]  job name, or any of a list
---@field type? string|string[]  job type ('leo', 'ems', ...), or any of a list
---@field minGrade? integer      lowest accepted one-based grade level
---@field onDuty? boolean        default true: must be on duty; false skips the duty check
---@field boss? boolean          true: the grade must be a boss grade

local EMPTY_RULE = {}

---@param want string|string[]
---@param value any
---@return boolean
local function listHas(want, value)
    if type(want) == 'string' then return want == value end
    for i = 1, #want do
        if want[i] == value then return true end
    end
    return false
end

---@param field string
---@param value any
local function assertNameList(field, value)
    -- The message is only formatted on failure: this runs on every check.
    if type(value) ~= 'string' and type(value) ~= 'table' then
        error(('job rule `%s` must be a string or an array of strings'):format(field), 3)
    end
end

---Checks one job sub-table against a rule. The reason order is fixed:
---no_player, wrong_job, off_duty, grade_too_low, not_boss.
---@param job table|nil PlayerData.job (read live, never copied)
---@param rule KoraJobRule|nil nil means "any job, on duty"
---@return boolean ok
---@return string|nil reason 'no_player'|'wrong_job'|'off_duty'|'grade_too_low'|'not_boss'
local function matchRule(job, rule)
    if rule == nil then rule = EMPTY_RULE end
    assert(type(rule) == 'table', 'job rule must be a table')
    if type(job) ~= 'table' or job.name == nil then return false, 'no_player' end

    local name, jobType = rule.name, rule.type
    if name ~= nil then
        assertNameList('name', name)
        if not listHas(name, job.name) then return false, 'wrong_job' end
    end
    if jobType ~= nil then
        assertNameList('type', jobType)
        if not listHas(jobType, job.type or 'none') then return false, 'wrong_job' end
    end

    local onDuty = rule.onDuty
    assert(onDuty == nil or type(onDuty) == 'boolean', 'job rule `onDuty` must be a boolean')
    if onDuty ~= false and not job.onduty then return false, 'off_duty' end

    local minGrade = rule.minGrade
    if minGrade ~= nil then
        assert(type(minGrade) == 'number', 'job rule `minGrade` must be a number')
        local grade = job.grade
        local level = type(grade) == 'table' and tonumber(grade.level) or 0
        if level < minGrade then return false, 'grade_too_low' end
    end

    if rule.boss and not job.isboss then return false, 'not_boss' end
    return true
end

if Core then
    CoreInternal = CoreInternal or {}
    CoreInternal.jobs = CoreInternal.jobs or {}
    CoreInternal.jobs.matchRule = matchRule
end

return matchRule
