CoreInternal = CoreInternal or {}
CoreInternal.registry = CoreInternal.registry or {}
local RI = CoreInternal.registry

RI.registries = RI.registries or {}
local registries = RI.registries

function RI.create(name, keyField)
    if registries[name] then return end
    registries[name] = {
        keyField = keyField,
        list = {}, index = {},
        epoch = 0, subscribers = {}, nextSubId = 1,
    }
end

function RI.reg(name)
    local r = registries[name]
    if not r then error(("kora_core: no registry named '%s'"):format(tostring(name)), 3) end
    return r
end

function RI.apply(name, key, record)
    local r = registries[name]
    local pos = r.index[key]
    if pos then
        r.list[pos] = record
        return 'update'
    end
    r.list[#r.list + 1] = record
    r.index[key] = #r.list
    return 'add'
end

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
    return removed
end

function RI.reseed(name, records, epoch)
    local r = registries[name]
    for i = #r.list, 1, -1 do r.list[i] = nil end
    r.index = {}
    for i = 1, #records do
        local rec = records[i]
        r.list[i] = rec
        r.index[rec[r.keyField]] = i
    end
    r.epoch = epoch or (r.epoch + 1)
end

function RI.dispatch(name, action, key, record, previous)
    local r = registries[name]
    for _, sub in pairs(r.subscribers) do
        local ok, err = pcall(sub.handler, action, key, record, previous)
        if not ok then
            print(("^3[kora_core:registry]^7 subscriber for '%s' errored: %s"):format(name, tostring(err)))
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

---@param name string
---@param key string
---@return table|nil
function Core.registry.getShared(name, key)
    local r = registries[name]
    if not r then return nil end
    local pos = r.index[key]
    return pos and r.list[pos] or nil
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

---Snapshot every registry (for the @kora_core/init.lua mirror seed).
---@return table
function Core.registry.sharedSnapshotAll()
    return RI.snapshotAll()
end
