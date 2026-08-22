-- Core.registry -- a generic runtime registry factory backing the shared
-- items/vehicles/jobs/gangs/weapons/locations lists (the /ideas requirement).
--
-- Each registry holds a DENSE ARRAY (`list`, insertion order) + a LOOKUP TABLE
-- (`index`, key -> position) + a materialised key->record table (which IS the
-- QBCore.Shared.* table legacy code reads). Reads are plain table lookups.
--
-- INTERNALS live on the private `CoreInternal.registry` table so build/finalise
-- never exports them; only the curated public functions (registerShared, ...)
-- sit on Core.registry. shared.lua defines the data structures + reads; server.lua
-- adds authoritative mutation + replication; client.lua adds the receive side.

CoreInternal = CoreInternal or {}
CoreInternal.registry = CoreInternal.registry or {}
local RI = CoreInternal.registry

-- name -> { keyField, list, index, materialised, epoch, subscribers, nextSubId }
RI.registries = RI.registries or {}
local registries = RI.registries

function RI.create(name, keyField)
    if registries[name] then return end
    registries[name] = {
        keyField = keyField,
        list = {}, index = {}, materialised = {},
        epoch = 0, subscribers = {}, nextSubId = 1,
    }
end

function RI.reg(name)
    local r = registries[name]
    if not r then error(("qbcore: no registry named '%s'"):format(tostring(name)), 3) end
    return r
end

-- Apply an add/update. Returns 'add' or 'update'.
function RI.apply(name, key, record)
    local r = registries[name]
    local pos = r.index[key]
    if pos then
        r.list[pos] = record
        r.materialised[key] = record
        return 'update'
    end
    r.list[#r.list + 1] = record
    r.index[key] = #r.list
    r.materialised[key] = record
    return 'add'
end

-- Remove by key. Swap-remove keeps the array dense in O(1); the moved element's
-- index entry is fixed up. Iteration order after a remove is NOT stable
-- (documented in AGENTS.md). Returns the removed record or nil.
function RI.remove(name, key)
    local r = registries[name]
    local pos = r.index[key]
    if not pos then return nil end
    local removed = r.list[pos]
    local lastPos = #r.list
    if pos ~= lastPos then
        local moved = r.list[lastPos]
        r.list[pos] = moved
        r.index[moved[r.keyField]] = pos
    end
    r.list[lastPos] = nil
    r.index[key] = nil
    r.materialised[key] = nil
    return removed
end

-- Full re-seed + epoch bump (used on a resource restart so mirrors re-sync).
-- CRITICAL: `materialised` is exposed as QBCore.Shared.Items etc., which legacy
-- code captures by reference (`local Items = QBCore.Shared.Items`). So it must
-- be CLEARED IN PLACE, never reassigned -- a fresh table would leave every
-- captured reference pointing at stale data. list/index are internal and can be
-- replaced freely.
function RI.reseed(name, records, epoch)
    local r = registries[name]
    r.list, r.index = {}, {}
    for k in pairs(r.materialised) do r.materialised[k] = nil end
    for i = 1, #records do
        local rec = records[i]
        r.list[i] = rec
        r.index[rec[r.keyField]] = i
        r.materialised[rec[r.keyField]] = rec
    end
    r.epoch = epoch or (r.epoch + 1)
end

-- Dispatch subscribers. Handlers are pcall-wrapped so a faulty one never breaks
-- a registration.
function RI.dispatch(name, action, key, record, previous)
    local r = registries[name]
    for _, sub in pairs(r.subscribers) do
        local ok, err = pcall(sub.handler, action, key, record, previous)
        if not ok then
            print(("^3[qbcore:registry]^7 subscriber for '%s' errored: %s"):format(name, tostring(err)))
        end
    end
end

function RI.snapshot(name)
    local out, list = {}, registries[name].list
    for i = 1, #list do out[i] = list[i] end
    return out
end

function RI.snapshotAll()
    local out = {}
    for name, r in pairs(registries) do
        out[name] = { epoch = r.epoch, keyField = r.keyField, records = RI.snapshot(name) }
    end
    return out
end

function RI.isCallable(x)
    if type(x) == 'function' then return true end
    local mt = getmetatable(x)
    return mt ~= nil and type(mt.__call) == 'function'
end

-- --- curated PUBLIC reads (exported flat) ---

---@param name string
---@param key string
---@return table|nil
function Core.registry.getShared(name, key)
    local r = registries[name]
    return r and r.materialised[key] or nil
end

---The dense array of records (live). Do not mutate.
---@param name string
---@return table[]
function Core.registry.allShared(name)
    local r = registries[name]
    return r and r.list or {}
end

---@param name string
---@return integer
function Core.registry.countShared(name)
    local r = registries[name]
    return r and #r.list or 0
end

---Snapshot every registry (for the @qbcore/init.lua mirror seed).
---@return table
function Core.registry.sharedSnapshotAll()
    return RI.snapshotAll()
end
