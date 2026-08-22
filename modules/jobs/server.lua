-- Core.jobs (server realm) -- job/gang/duty changes via the funnel, plus a
-- MAINTAINED job index (jobName -> {src set}) so getPlayersByJob is O(1) lookup
-- rather than the O(n) scan legacy qb-core does on every dispatch/paycheck tick.

local PI = CoreInternal.player

-- jobName -> { [src] = true }   and   jobName -> { [src] = true } for on-duty only
local byJob = {}
local byJobOnDuty = {}

local function indexRemove(src, jobName)
    if jobName and byJob[jobName] then byJob[jobName][src] = nil end
    if jobName and byJobOnDuty[jobName] then byJobOnDuty[jobName][src] = nil end
end

local function indexAdd(src, jobName, onDuty)
    byJob[jobName] = byJob[jobName] or {}
    byJob[jobName][src] = true
    byJobOnDuty[jobName] = byJobOnDuty[jobName] or {}
    byJobOnDuty[jobName][src] = onDuty or nil
end

---@param src integer
---@return table|nil
function Core.jobs.getJob(src)
    local p = PI.handle(src)
    return p and p.PlayerData.job or nil
end

---@param src integer
---@return table|nil
function Core.jobs.getGang(src)
    local p = PI.handle(src)
    return p and p.PlayerData.gang or nil
end

---@param src integer
---@param name string
---@param grade integer|nil
---@return boolean, string|nil
function Core.jobs.setJob(src, name, grade)
    local p = PI.handle(src)
    if not p then return false, 'no such player' end
    if not Core.registry.getShared('jobs', name) then return false, 'unknown job' end
    grade = math.max(1, math.floor(tonumber(grade) or 1))

    indexRemove(src, p.PlayerData.job and p.PlayerData.job.name)
    local job = CoreInternal.player.buildJob(name, grade)
    -- Whole `job` root replaced in one funnel write (one dirty column, one
    -- delta op carrying the whole sub-table).
    Core.player.setPath(src, { 'job' }, job)
    indexAdd(src, name, job.onduty)

    TriggerEvent('QBCore:Server:OnJobUpdate', src, job)
    if Config.compat.jobUpdateEventSource ~= 'client' then
        TriggerClientEvent('QBCore:Client:OnJobUpdate', src, job)
    end
    return true
end

---@param src integer
---@param name string
---@param grade integer|nil
---@return boolean, string|nil
function Core.jobs.setGang(src, name, grade)
    local p = PI.handle(src)
    if not p then return false, 'no such player' end
    if not Core.registry.getShared('gangs', name) then return false, 'unknown gang' end
    grade = tonumber(grade) or 0
    local gang = CoreInternal.player.buildGang(name, grade)
    Core.player.setPath(src, { 'gang' }, gang)
    TriggerEvent('QBCore:Server:OnGangUpdate', src, gang)
    if Config.compat.jobUpdateEventSource ~= 'client' then
        TriggerClientEvent('QBCore:Client:OnGangUpdate', src, gang)
    end
    return true
end

---@param src integer
---@param onDuty boolean
---@return boolean
function Core.jobs.setJobDuty(src, onDuty)
    local p = PI.handle(src)
    if not p then return false end
    onDuty = onDuty and true or false
    Core.player.setPath(src, { 'job', 'onduty' }, onDuty)
    local jobName = p.PlayerData.job and p.PlayerData.job.name
    if jobName then
        byJobOnDuty[jobName] = byJobOnDuty[jobName] or {}
        byJobOnDuty[jobName][src] = onDuty or nil
    end
    TriggerEvent('QBCore:Server:SetDuty', src, onDuty)
    TriggerClientEvent('QBCore:Client:SetDuty', src, onDuty)
    return true
end

---Sources with a given job. onDutyOnly filters to on-duty. O(1) via the index.
---@param name string
---@param onDutyOnly boolean|nil
---@return integer[]
function Core.jobs.getPlayersByJob(name, onDutyOnly)
    local set = onDutyOnly and byJobOnDuty[name] or byJob[name]
    local out = {}
    if set then for src in pairs(set) do out[#out + 1] = src end end
    return out
end

---@param name string
---@return integer
function Core.jobs.getDutyCount(name)
    local set = byJobOnDuty[name]
    local n = 0
    if set then for _ in pairs(set) do n = n + 1 end end
    return n
end

-- Keep the index seeded as players load / unload. onChange on the 'job' prefix
-- would double-handle setJob's own writes, so instead we hook the load/drop
-- lifecycle events.
AddEventHandler('qbcore:server:playerLoaded', function(src)
    local p = PI.handle(src)
    if p and p.PlayerData.job then
        indexAdd(src, p.PlayerData.job.name, p.PlayerData.job.onduty)
    end
end)

AddEventHandler('qbcore:server:playerDropped', function(src)
    local p = PI.handle(src)
    -- p may already be gone; sweep the src from every job set defensively.
    for _, set in pairs(byJob) do set[src] = nil end
    for _, set in pairs(byJobOnDuty) do set[src] = nil end
end)
