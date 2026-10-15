-- Core.jobs (server realm) -- job/gang/duty changes via the funnel, plus a
-- MAINTAINED job index (jobName -> {src set}) so getPlayersByJob is O(1) lookup
-- rather than the O(n) scan legacy qb-core does on every dispatch/paycheck tick.
--
-- On top of the index this file keeps live on-duty COUNTERS (+1 when a player
-- enters an on-duty set, -1 when they leave it) and publishes them as
-- GlobalState.OnDuty = { police = 1, leo = 2, ... }. Every 5 minutes the whole
-- index and the counters are rebuilt from PlayerData and any drift is logged.

local PI = CoreInternal.player

-- jobName -> { [src] = true }   and   jobName -> { [src] = true } for on-duty only
local byJob = {}
local byJobOnDuty = {}

-- jobType -> the same two shapes. A separate index rather than a scan over
-- byJob: a type spans several jobs (police + sheriff + statetrooper are all
-- 'leo'), so answering "every on-duty LEO" from byJob alone would mean walking
-- the whole jobs registry on every dispatch call to find which names carry that
-- type. The type is read off the player's own job sub-table (buildJob copies it
-- there), so no registry lookup happens on the index path at all.
local byType = {}
local byTypeOnDuty = {}

-- src -> the jobType it was last indexed under. The type is derived from the
-- job, and a setJob can change both -- without remembering what we indexed we
-- would have to search every type set to remove a stale entry, which is exactly
-- the O(n) sweep this index exists to avoid.
local typeOfSrc = {}

-- Live on-duty counters (the +1 / -1 bookkeeping).
local jobCounts, typeCounts = {}, {}

GlobalState.OnDuty = {}

local publishQueued = false
local function publish()
    publishQueued = false
    -- One table, e.g. { police = 1, leo = 2 }. Types first, jobs second, so a
    -- registered job name always reports that job's count, including zero.
    local merged = {}
    for name, count in pairs(typeCounts) do
        if Core.registry.getShared('jobs', name) then
            merged[name] = jobCounts[name] or 0
        else
            merged[name] = count
        end
    end
    for k, v in pairs(jobCounts) do merged[k] = v end
    -- Must assign a whole new table; mutating GlobalState.OnDuty in place
    -- does not replicate.
    GlobalState.OnDuty = merged
end

-- Coalesce bursts (setJob = remove + add) into a single replication.
local function queuePublish()
    if publishQueued then return end
    publishQueued = true
    SetTimeout(100, publish)
end

local function bump(counts, key, delta)
    local n = (counts[key] or 0) + delta
    counts[key] = n > 0 and n or nil
    queuePublish()
end

-- Only counts on a real membership change, so it is safe to call repeatedly.
local function setDuty(set, counts, key, src, onDuty)
    local had = set[src] == true
    if onDuty and not had then
        set[src] = true
        bump(counts, key, 1)
    elseif not onDuty and had then
        set[src] = nil
        bump(counts, key, -1)
    end
end

local function indexRemove(src, jobName)
    if jobName then
        if byJob[jobName] then byJob[jobName][src] = nil end
        if byJobOnDuty[jobName] then setDuty(byJobOnDuty[jobName], jobCounts, jobName, src, false) end
    end

    local jobType = typeOfSrc[src]
    if jobType then
        if byType[jobType] then byType[jobType][src] = nil end
        if byTypeOnDuty[jobType] then setDuty(byTypeOnDuty[jobType], typeCounts, jobType, src, false) end
        typeOfSrc[src] = nil
    end
end

---Drops a source from every set without needing to know which job it was under.
---Used by the drop sweep and by the reconciler, both of which are recovering
---from a state where the recorded job name can't be trusted.
---@param src integer
local function indexForget(src)
    for _, set in pairs(byJob) do set[src] = nil end
    for _, set in pairs(byType) do set[src] = nil end
    for name, set in pairs(byJobOnDuty) do setDuty(set, jobCounts, name, src, false) end
    for name, set in pairs(byTypeOnDuty) do setDuty(set, typeCounts, name, src, false) end
    typeOfSrc[src] = nil
end

local function indexAdd(src, jobName, onDuty, jobType)
    onDuty = onDuty and true or false
    jobType = jobType or 'none'

    byJob[jobName] = byJob[jobName] or {}
    byJob[jobName][src] = true
    byJobOnDuty[jobName] = byJobOnDuty[jobName] or {}
    setDuty(byJobOnDuty[jobName], jobCounts, jobName, src, onDuty)

    byType[jobType] = byType[jobType] or {}
    byType[jobType][src] = true
    byTypeOnDuty[jobType] = byTypeOnDuty[jobType] or {}
    setDuty(byTypeOnDuty[jobType], typeCounts, jobType, src, onDuty)
    typeOfSrc[src] = jobType
end

---Flips only the on-duty half of both indexes, leaving membership alone.
---@param src integer
---@param jobName string|nil
---@param onDuty boolean
local function indexSetDuty(src, jobName, onDuty)
    onDuty = onDuty and true or false
    if jobName then
        byJobOnDuty[jobName] = byJobOnDuty[jobName] or {}
        setDuty(byJobOnDuty[jobName], jobCounts, jobName, src, onDuty)
    end

    local jobType = typeOfSrc[src]
    if jobType then
        byTypeOnDuty[jobType] = byTypeOnDuty[jobType] or {}
        setDuty(byTypeOnDuty[jobType], typeCounts, jobType, src, onDuty)
    end
end

---Materialises a source set into a dense array.
---@param set table<integer, true>|nil
---@return integer[]
local function toArray(set)
    local out = {}
    if set then for src in pairs(set) do out[#out + 1] = src end end
    return out
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
    indexAdd(src, name, job.onduty, job.type)

    -- QBCore:*:OnJobUpdate are NOT real qb-core's own event names (verified
    -- against qbcore-fivem/qb-core's server/player.lua: it has no
    -- OnJobUpdate/OnGangUpdate at all) -- they're this rebuild's own,
    -- additional fan-out events. Real qb-core instead funnels every
    -- job/gang/duty change through Player:UpdateClient(key, val), which fires
    -- QBCore:Server:OnPlayerUpdated / QBCore:Client:OnPlayerUpdated -- the
    -- event name legacy scripts actually listen for (confirmed:
    -- legacy ambulance and police job resources both key off
    -- OnPlayerUpdated directly, never OnJobUpdate). Both are fired below so
    -- either listening style keeps working. Payload must be legacy-shaped
    -- (zero-based grade.level), same translation as QBCore.Shared.Jobs/the
    -- compat PlayerData view. Guarded on the specific FUNCTION rather than on
    -- `Core.compat` itself: Core is an auto-vivifying proxy (build/
    -- initiate.lua), so merely referencing `Core.compat` always returns a
    -- table (real gameplay boot always loads compat/shared/coreobject.lua,
    -- which fills it in; a test dofiling only this module would otherwise
    -- error on a truthy-but-empty `Core.compat`).
    local legacyJob = Core.compat.toLegacyJobOrGang and Core.compat.toLegacyJobOrGang(job) or job
    TriggerEvent('QBCore:Server:OnJobUpdate', src, legacyJob)
    TriggerEvent('QBCore:Server:OnPlayerUpdated', src, 'job', legacyJob)
    if Config.compat.jobUpdateEventSource ~= 'client' then
        TriggerClientEvent('QBCore:Client:OnJobUpdate', src, legacyJob)
        TriggerClientEvent('QBCore:Client:OnPlayerUpdated', src, 'job', legacyJob)
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
    grade = math.max(1, math.floor(tonumber(grade) or 1))
    local gang = CoreInternal.player.buildGang(name, grade)
    Core.player.setPath(src, { 'gang' }, gang)
    local legacyGang = Core.compat.toLegacyJobOrGang and Core.compat.toLegacyJobOrGang(gang) or gang
    TriggerEvent('QBCore:Server:OnGangUpdate', src, legacyGang)
    TriggerEvent('QBCore:Server:OnPlayerUpdated', src, 'gang', legacyGang)
    if Config.compat.jobUpdateEventSource ~= 'client' then
        TriggerClientEvent('QBCore:Client:OnGangUpdate', src, legacyGang)
        TriggerClientEvent('QBCore:Client:OnPlayerUpdated', src, 'gang', legacyGang)
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
    indexSetDuty(src, p.PlayerData.job and p.PlayerData.job.name, onDuty)
    TriggerEvent('QBCore:Server:SetDuty', src, onDuty)
    TriggerClientEvent('QBCore:Client:SetDuty', src, onDuty)
    return true
end

---Updates a stored job without a legacy Player object. Grades are one-based.
---@param citizenid string
---@param name string
---@param grade integer|nil
---@return boolean, string|nil
function Core.jobs.setOfflineJob(citizenid, name, grade)
    if not Core.registry.getShared('jobs', name) then return false, 'unknown job' end
    local data, err = Core.persistence.getOfflinePlayerData(citizenid)
    if not data then return false, err end
    data.job = CoreInternal.player.buildJob(name, grade)
    return Core.persistence.saveOfflinePlayer(data, { 'job' })
end

---@param citizenid string
---@param name string
---@param grade integer|nil
---@return boolean, string|nil
function Core.jobs.setOfflineGang(citizenid, name, grade)
    if not Core.registry.getShared('gangs', name) then return false, 'unknown gang' end
    local data, err = Core.persistence.getOfflinePlayerData(citizenid)
    if not data then return false, err end
    data.gang = CoreInternal.player.buildGang(name, grade)
    return Core.persistence.saveOfflinePlayer(data, { 'gang' })
end

---Sources with a given job. onDutyOnly filters to on-duty. O(1) via the index.
---@param name string
---@param onDutyOnly boolean|nil
---@return integer[]
function Core.jobs.getPlayersByJob(name, onDutyOnly)
    return toArray(onDutyOnly and byJobOnDuty[name] or byJob[name])
end

---Sources whose job carries a given TYPE ('leo', 'ems', ...), across every job
---that declares it. This is what a dispatch system wants: one alert reaching
---police, sheriff and state troopers without the caller having to know which
---job names exist on this server.
---@param jobType string
---@param onDutyOnly boolean|nil
---@return integer[]
function Core.jobs.getPlayersByJobType(jobType, onDutyOnly)
    return toArray(onDutyOnly and byTypeOnDuty[jobType] or byType[jobType])
end

---@param name string
---@return integer
function Core.jobs.getDutyCount(name)
    return jobCounts[name] or 0
end

---@param jobType string
---@return integer
function Core.jobs.getDutyCountByType(jobType)
    return typeCounts[jobType] or 0
end

---Every job type currently held by an online player, with how many of them are
---on duty. Lets a UI list the services that actually exist right now rather
---than hard-coding a list.
---@param onDutyOnly boolean|nil
---@return table<string, integer>
function Core.jobs.getJobTypeCounts(onDutyOnly)
    local counts = {}
    for jobType, set in pairs(onDutyOnly and byTypeOnDuty or byType) do
        local n = 0
        for _ in pairs(set) do n = n + 1 end
        if n > 0 then counts[jobType] = n end
    end
    return counts
end

---On-duty players as descriptive records rather than bare source ids -- the
---roster a dispatch/MDT unit list needs, resolved once here instead of every
---consumer looping getPlayersByJob and then reaching back into PlayerData.
---
---With no filter it returns every on-duty player of every job. `job` and
---`jobType` narrow it; passing both requires the player to match both.
---@param filter { job: string|nil, jobType: string|nil, onDutyOnly: boolean|nil }|nil
---@return { src: integer, citizenid: string, name: string, callsign: string|nil, job: string, jobLabel: string, jobType: string, grade: integer, gradeLabel: string, onDuty: boolean }[]
function Core.jobs.getOnDutyRoster(filter)
    filter = filter or {}
    local onDutyOnly = filter.onDutyOnly
    if onDutyOnly == nil then onDutyOnly = true end

    -- Pick the narrowest index available so the common cases never scan.
    local sources
    if filter.job then
        sources = Core.jobs.getPlayersByJob(filter.job, onDutyOnly)
    elseif filter.jobType then
        sources = Core.jobs.getPlayersByJobType(filter.jobType, onDutyOnly)
    else
        sources = {}
        for _, set in pairs(onDutyOnly and byTypeOnDuty or byType) do
            for src in pairs(set) do sources[#sources + 1] = src end
        end
    end

    local out = {}
    for _, src in ipairs(sources) do
        local p = PI.handle(src)
        local job = p and p.PlayerData.job
        -- A source can survive in the index for a frame after the handle is
        -- gone (drop ordering), so a missing handle is skipped rather than
        -- treated as an error.
        if job then
            local matchesJob = not filter.job or job.name == filter.job
            local matchesType = not filter.jobType or (job.type or 'none') == filter.jobType

            if matchesJob and matchesType then
                local charinfo = p.PlayerData.charinfo or {}
                out[#out + 1] = {
                    src = src,
                    citizenid = p.PlayerData.citizenid,
                    name = ('%s %s'):format(charinfo.firstname or '', charinfo.lastname or ''):gsub('^%s*(.-)%s*$', '%1'),
                    callsign = p.PlayerData.metadata and p.PlayerData.metadata.callsign or nil,
                    job = job.name,
                    jobLabel = job.label or job.name,
                    jobType = job.type or 'none',
                    grade = job.grade and job.grade.level or 1,
                    gradeLabel = job.grade and job.grade.name or 'Grade',
                    onDuty = job.onduty and true or false,
                }
            end
        end
    end

    return out
end

-- Keep the index seeded as players load / unload. onChange on the 'job' prefix
-- would double-handle setJob's own writes, so instead we hook the load/unload/drop
-- lifecycle events.
AddEventHandler('qbcore:server:playerLoaded', function(src)
    local p = PI.handle(src)
    if p and p.PlayerData.job then
        indexAdd(src, p.PlayerData.job.name, p.PlayerData.job.onduty, p.PlayerData.job.type)
    end
end)

AddEventHandler('qbcore:server:playerDropped', function(src)
    -- The handle may already be gone; sweep the src from every set defensively.
    -- indexForget also decrements the on-duty counters.
    indexForget(src)
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', indexForget)

-- Reconciler for job writes that DIDN'T come through setJob/setJobDuty.
--
-- The legacy compat surface exposes SetJobData(key, value), which writes
-- Core.player.setPath(src, { 'job', key }, value) directly -- so a legacy
-- resource calling SetJobData('onduty', true) used to flip duty with the index
-- none the wiser, and that player then silently received no dispatch alerts and
-- counted as off duty everywhere. Subscribing to the whole 'job' prefix is the
-- only way to see those writes.
--
-- setJob/setJobDuty already maintain the index inline, so this must not
-- double-handle them: it compares the observed job/duty against what the index
-- currently believes and does nothing when they already agree, which is the
-- case for every write those two functions make.
Core.player.onChange({ 'job' }, function(src)
    local p = PI.handle(src)
    local job = p and p.PlayerData.job
    if not job or not job.name then return end

    local jobType = job.type or 'none'
    local onDuty = job.onduty and true or false

    local indexedMember = byJob[job.name] and byJob[job.name][src] or false
    local indexedType = typeOfSrc[src]
    local indexedDuty = (byJobOnDuty[job.name] and byJobOnDuty[job.name][src]) and true or false

    if indexedMember and indexedType == jobType and indexedDuty == onDuty then return end

    -- Membership or type drifted: rebuild this source's entries from scratch.
    if not indexedMember or indexedType ~= jobType then
        indexForget(src)
        indexAdd(src, job.name, onDuty, jobType)
        return
    end

    -- Only duty drifted (the SetJobData('onduty', ...) case).
    indexSetDuty(src, job.name, onDuty)
end)

-- Every 5 minutes: throw the index and counters away and rebuild them from
-- what players' PlayerData actually says right now. Anything that drifted
-- (missed drop, direct SetJobData write, etc.) is corrected and logged.
local function snapshot(t)
    local keys = {}
    for k, v in pairs(t) do keys[#keys + 1] = ('%s=%d'):format(k, v) end
    table.sort(keys)
    return table.concat(keys, ',')
end

local function verifyCounts()
    local before = snapshot(jobCounts) .. '|' .. snapshot(typeCounts)

    byJob, byJobOnDuty, byType, byTypeOnDuty = {}, {}, {}, {}
    typeOfSrc = {}
    jobCounts, typeCounts = {}, {}

    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local p = src and PI.handle(src)
        local job = p and p.PlayerData and p.PlayerData.job
        if job and job.name then
            indexAdd(src, job.name, job.onduty, job.type)
        end
    end

    queuePublish() -- also publish empty results, without a second queued write

    local after = snapshot(jobCounts) .. '|' .. snapshot(typeCounts)
    if before ~= after then
        print(('[Core.jobs] on-duty counts drifted, corrected.\n  before: %s\n  after:  %s'):format(before, after))
    end
end

CreateThread(function()
    Wait(2000)
    verifyCounts() -- covers a resource restart with players already online
    while true do
        Wait(5 * 60 * 1000)
        verifyCounts()
    end
end)
