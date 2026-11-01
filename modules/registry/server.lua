-- Core.registry (server realm) -- the AUTHORITATIVE side. Registration mutates
-- the structures, dispatches subscribers, and broadcasts a delta on two
-- channels: a plain local TriggerEvent (reaches every OTHER server resource's
-- @kora_core/init.lua mirror) and TriggerClientEvent(-1) (reaches every client).
--
-- Subscriptions and registered records are OWNER-TRACKED via
-- Kora.resources.serverRegistry so a resource that registered items and then
-- restarts neither leaks nor double-registers.

local RI = CoreInternal.registry

RI.create('items', 'name')
RI.create('vehicles', 'model')
RI.create('jobs', 'name')
RI.create('gangs', 'name')
RI.create('weapons', 'name')
RI.create('locations', 'key')

local ownedRecords = {}   -- resource -> { [name] = { key = true } }
local recordOwners = {}   -- name -> { [key] = resource }

local function clearOwnership(name, key)
    local owners = recordOwners[name]
    local owner = owners and owners[key]
    if not owner then return end
    ownedRecords[owner][name][key] = nil
    owners[key] = nil
end

-- Jobs and gangs use one-based grade arrays internally.  Resources written for
-- legacy QBCore commonly supply an equivalent map keyed by "0", "1", …;
-- convert that boundary format once so every modern consumer sees the same
-- shape (and setJob/buildJob can resolve the selected grade).
---@param record table
local function normaliseRoleGrades(record)
    local grades = record.grades
    if type(grades) ~= 'table' then return end
    -- A numeric zero key makes #grades non-zero once grade 1 is also present,
    -- so check it explicitly before treating the table as a modern array.
    if #grades > 0 and grades[0] == nil and grades['0'] == nil then return end

    local indexed = {}
    for key, grade in pairs(grades) do
        local level = tonumber(key)
        if level and level >= 0 and level % 1 == 0 and type(grade) == 'table' then
            indexed[#indexed + 1] = { level = level, grade = grade }
        end
    end
    if #indexed == 0 then return end

    table.sort(indexed, function(a, b) return a.level < b.level end)
    local normalised = {}
    for _, entry in ipairs(indexed) do normalised[#normalised + 1] = entry.grade end
    record.grades = normalised
end

local subRegistry = Kora.resources.serverRegistry(function(owner)
    for _, r in pairs(RI.registries) do
        for subId, sub in pairs(r.subscribers) do
            if sub.resource == owner then r.subscribers[subId] = nil end
        end
    end
    local owned = ownedRecords[owner]
    if owned then
        for name, keys in pairs(owned) do
            for key in pairs(keys) do
                Core.registry._unregisterInternal(name, key)
            end
        end
        ownedRecords[owner] = nil
    end
end)

local function broadcast(name, action, key, record)
    local epoch = RI.reg(name).epoch
    TriggerEvent('qbcore:registry:delta', name, action, key, record, epoch)
    TriggerClientEvent('qbcore:registry:delta', -1, name, action, key, record, epoch)
end

---Register/update one record. Returns (true) or (false, errorString).
---@param name string
---@param key string
---@param record table
---@return boolean, string|nil
function Core.registry.registerShared(name, key, record)
    if type(record) ~= 'table' then return false, 'record must be a table' end
    local r = RI.registries[name]
    if not r then return false, ('no registry named %q'):format(tostring(name)) end
    if name == 'jobs' or name == 'gangs' then normaliseRoleGrades(record) end
    record[r.keyField] = record[r.keyField] or key
    if record[r.keyField] ~= key then
        return false, ('record.%s (%s) does not match key (%s)')
            :format(r.keyField, tostring(record[r.keyField]), tostring(key))
    end

    local previous = Core.registry.getShared(name, key)
    local action = RI.apply(name, key, record)

    local owner = GetInvokingResource() or GetCurrentResourceName()
    -- A replacement belongs to its latest owner, even if it reuses the table.
    clearOwnership(name, key)
    if owner then
        -- subRegistry needs one dispose per resource, so the resource name doubles as the tracking id.
        subRegistry.track(owner, owner)
        ownedRecords[owner] = ownedRecords[owner] or {}
        ownedRecords[owner][name] = ownedRecords[owner][name] or {}
        ownedRecords[owner][name][key] = true
        recordOwners[name] = recordOwners[name] or {}
        recordOwners[name][key] = owner
    end

    RI.dispatch(name, action, key, record, previous)
    broadcast(name, action, key, record)
    return true
end

---@param name string
---@param records table[]
---@return integer registered
function Core.registry.registerManyShared(name, records)
    local r = RI.registries[name]
    if not r then return 0 end
    local n = 0
    for _, record in ipairs(records) do
        local key = record[r.keyField]
        if key ~= nil and Core.registry.registerShared(name, key, record) then n = n + 1 end
    end
    return n
end

function Core.registry._unregisterInternal(name, key)
    clearOwnership(name, key)
    local removed = RI.remove(name, key)
    if not removed then return false end
    RI.dispatch(name, 'remove', key, nil, removed)
    broadcast(name, 'remove', key, nil)
    return true
end

---@param name string
---@param key string
---@return boolean
function Core.registry.unregisterShared(name, key)
    return Core.registry._unregisterInternal(name, key)
end

---Subscribe to changes. handler(action, key, record, previous). Owner-tracked.
---@param name string
---@param handler fun(action:string, key:string, record:table|nil, previous:table|nil)
---@return integer|nil, string|nil
function Core.registry.onSharedChange(name, handler)
    local r = RI.registries[name]
    if not r then return nil, 'no such registry' end
    if not RI.isCallable(handler) then return nil, 'handler must be callable' end
    local owner = GetInvokingResource() or GetCurrentResourceName()
    local subId = r.nextSubId
    r.nextSubId = r.nextSubId + 1
    r.subscribers[subId] = { resource = owner, handler = handler }
    if owner then subRegistry.track(owner, owner) end
    return subId
end

---@param name string
---@param subId integer
function Core.registry.offSharedChange(name, subId)
    local r = RI.registries[name]
    if r then r.subscribers[subId] = nil end
end

do
    QBCoreSeed = QBCoreSeed or {}
    local seeds = {
        items = QBCoreSeed.items, vehicles = QBCoreSeed.vehicles,
        jobs = QBCoreSeed.jobs, gangs = QBCoreSeed.gangs,
        weapons = QBCoreSeed.weapons, locations = QBCoreSeed.locations,
    }
    for name, records in pairs(seeds) do
        if records then Core.registry.registerManyShared(name, records) end
    end
end

RegisterNetEvent('qbcore:registry:requestSnapshot', function()
    TriggerClientEvent('qbcore:registry:snapshotAll', source, RI.snapshotAll())
end)
