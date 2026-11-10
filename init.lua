assert(Kora, '@kora_core/init.lua must be loaded AFTER @kora_lib/init.lua (add its shared_script first).')

Kora.shared = Kora.shared or {}

local mirror = {}
local subs = {}
local nextSubId = 1

local function ensure(name)
    if not mirror[name] then
        mirror[name] = { list = {}, index = {}, epoch = 0 }
        subs[name] = subs[name] or {}
    end
    return mirror[name]
end

local function reseed(name, keyField, records, epoch)
    local m = ensure(name)
    for i = #m.list, 1, -1 do m.list[i] = nil end
    m.index = {}
    m.keyField = keyField
    for i = 1, #records do
        local rec = records[i]
        m.list[i] = rec
        m.index[rec[keyField]] = i
    end
    m.epoch = epoch or m.epoch
end

local function applyDelta(name, action, key, record, epoch)
    local m = ensure(name)
    if epoch and m.epoch ~= 0 and epoch ~= m.epoch and action ~= 'remove' then
        if IsDuplicityVersion and IsDuplicityVersion() then
            local ok, all = pcall(function() return exports.kora_core:sharedSnapshotAll() end)
            if ok and type(all) == 'table' then
                for n, payload in pairs(all) do reseed(n, payload.keyField, payload.records, payload.epoch) end
            end
        else
            TriggerServerEvent('kora_core:registry:requestSnapshot')
        end
        return
    end
    local previous = key and (function()
        local pos = m.index[key]; return pos and m.list[pos] or nil
    end)() or nil

    if action == 'remove' then
        local pos = m.index[key]
        if pos then
            local lastPos = #m.list
            if pos ~= lastPos then
                local moved = m.list[lastPos]
                m.list[pos] = moved
                m.index[moved[m.keyField]] = pos
            end
            m.list[lastPos] = nil
            m.index[key] = nil
        end
    else
        local pos = m.index[key]
        if pos then
            m.list[pos] = record
        else
            m.list[#m.list + 1] = record
            m.index[key] = #m.list
        end
    end
    if epoch then m.epoch = epoch end

    for _, handler in pairs(subs[name] or {}) do
        local ok, err = pcall(handler, action, key, record, previous)
        if not ok then
            print(("^3[kora_core:shared]^7 onChange handler for '%s' errored: %s"):format(name, tostring(err)))
        end
    end
end

---Read one record by key. Plain local hash lookup -- ZERO boundary crossing.
---@param name string
---@param key string
---@return table|nil
function Kora.shared.get(name, key)
    local m = mirror[name]
    if not m then return nil end
    local pos = m.index[key]
    return pos and m.list[pos] or nil
end

---The dense array of records (live -- do not mutate; use register()).
---@param name string
---@return table[]
function Kora.shared.all(name)
    local m = mirror[name]
    return m and m.list or {}
end

---@param name string
---@return integer
function Kora.shared.epoch(name)
    local m = mirror[name]
    return m and m.epoch or 0
end

---Register/update a record. Forwards to kora_core (server-authoritative); the
---change replicates back and patches this and every other consumer's mirror.
---@param name string
---@param key string
---@param record table
---@return boolean, string|nil
function Kora.shared.register(name, key, record)
    return exports.kora_core:registerShared(name, key, record)
end

---@param name string
---@param key string
---@return boolean
function Kora.shared.unregister(name, key)
    return exports.kora_core:unregisterShared(name, key)
end

---Subscribe to changes for a registry. handler(action, key, record, previous).
---LOCAL subscription -- dispatched in this VM when a delta arrives. Returns an
---id for offChange. No owner tracking: the handler dies with this resource.
---@param name string
---@param handler fun(action:string, key:string, record:table|nil, previous:table|nil)
---@return integer
function Kora.shared.onChange(name, handler)
    ensure(name)
    local id = nextSubId
    nextSubId = nextSubId + 1
    subs[name][id] = handler
    return id
end

---@param name string
---@param id integer
function Kora.shared.offChange(name, id)
    if subs[name] then subs[name][id] = nil end
end

local isServerRealm = IsDuplicityVersion and IsDuplicityVersion()

if not isServerRealm then
    RegisterNetEvent('kora_core:registry:delta')
end
AddEventHandler('kora_core:registry:delta', function(name, action, key, record, epoch)
    applyDelta(name, action, key, record, epoch)
end)

if not isServerRealm then
    RegisterNetEvent('kora_core:registry:snapshotAll')
end
AddEventHandler('kora_core:registry:snapshotAll', function(all)
    for name, payload in pairs(all) do
        reseed(name, payload.keyField, payload.records, payload.epoch)
    end
end)

CreateThread(function()
    if isServerRealm then
        for _ = 1, 200 do
            local ok, all = pcall(function() return exports.kora_core:sharedSnapshotAll() end)
            if ok and type(all) == 'table' and next(all) ~= nil then
                for name, payload in pairs(all) do
                    reseed(name, payload.keyField, payload.records, payload.epoch)
                end
                return
            end
            Wait(25)
        end
    else
        Wait(0)
        TriggerServerEvent('kora_core:registry:requestSnapshot')
    end
end)
