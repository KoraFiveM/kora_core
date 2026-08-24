-- Core.registry (server realm) -- the AUTHORITATIVE side. Registration mutates
-- the structures, dispatches subscribers, and broadcasts a delta on two
-- channels: a plain local TriggerEvent (reaches every OTHER server resource's
-- @qbcore/init.lua mirror) and TriggerClientEvent(-1) (reaches every client).
--
-- Subscriptions and registered records are OWNER-TRACKED via
-- QB.resources.serverRegistry so a resource that registered items and then
-- restarts neither leaks nor double-registers.

local RI = CoreInternal.registry

RI.create('items', 'name')
RI.create('vehicles', 'model')
RI.create('jobs', 'name')
RI.create('gangs', 'name')
RI.create('weapons', 'name')
RI.create('locations', 'key')

local ownedRecords = {}   -- resource -> { [name] = { key = true } }

local subRegistry = QB.resources.serverRegistry(function(owner)
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
    record[r.keyField] = record[r.keyField] or key
    if record[r.keyField] ~= key then
        return false, ('record.%s (%s) does not match key (%s)')
            :format(r.keyField, tostring(record[r.keyField]), tostring(key))
    end

    local previous = r.materialised[key]
    local action = RI.apply(name, key, record)

    local owner = GetInvokingResource() or GetCurrentResourceName()
    if owner then
        -- subRegistry only needs one dispose call per resource (its callback
        -- does its own manual sweep below, not per-id cleanup), so the
        -- resource name doubles as its own tracking id -- QB.resources.
        -- serverRegistry's track(resource, id) requires both.
        subRegistry.track(owner, owner)
        ownedRecords[owner] = ownedRecords[owner] or {}
        ownedRecords[owner][name] = ownedRecords[owner][name] or {}
        ownedRecords[owner][name][key] = true
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

-- Internal unregister used by the owner-stop sweep (no owner bookkeeping).
function Core.registry._unregisterInternal(name, key)
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
    local owner = GetInvokingResource() or GetCurrentResourceName()
    if owner and ownedRecords[owner] and ownedRecords[owner][name] then
        ownedRecords[owner][name][key] = nil
    end
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

-- Ingest the seed data (loaded before this file via shared/*.lua). Applied
-- directly (no broadcast) so the epoch starts clean at 0 with the seeds present.
do
    QBCoreSeed = QBCoreSeed or {}
    local seeds = {
        items = QBCoreSeed.items, vehicles = QBCoreSeed.vehicles,
        jobs = QBCoreSeed.jobs, gangs = QBCoreSeed.gangs,
        weapons = QBCoreSeed.weapons, locations = QBCoreSeed.locations,
    }
    for name, records in pairs(seeds) do
        if records then
            local r = RI.registries[name]
            for _, record in ipairs(records) do
                RI.apply(name, record[r.keyField], record)
            end
        end
    end
end

-- Serve a full snapshot to a client that connected / requested one.
RegisterNetEvent('qbcore:registry:requestSnapshot', function()
    TriggerClientEvent('qbcore:registry:snapshotAll', source, RI.snapshotAll())
end)
