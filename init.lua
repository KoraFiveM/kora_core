-- '@kora_core/init.lua' -- installs a LIVE-UPDATING shared-registry mirror into the
-- consumer's own Lua VM, as Kora.shared.*. This is what the /ideas file and the
-- user's follow-up ask for: shared items/vehicles/jobs lists that are
-- updateable at runtime from any resource and have change handlers "across other
-- resources that have called on the shared list" fire automatically.
--
-- A consumer opts in with, in order:
--     shared_script '@kora_lib/init.lua'
--     shared_script '@kora_core/init.lua'
--
-- Same trick as @kora_sql/init.lua: kora_lib's `Kora` table has only __index, so
-- `Kora.shared = {...}` is a plain rawset in the consumer's VM. The mirror is LOCAL
-- tables patched by 'qbcore:registry:delta'; onChange handlers dispatch IN-VM (no
-- boundary crossing, and they die with the resource). Each registry carries an epoch
-- so a kora_core restart triggers a re-seed rather than silent drift.

assert(Kora, '@kora_core/init.lua must be loaded AFTER @kora_lib/init.lua (add its shared_script first).')

Kora.shared = Kora.shared or {}

-- name -> { list = {}, index = {}, epoch = 0 }
local mirror = {}
-- name -> { subId -> handler }
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
    -- Preserve the array reference across a full resync. Consumers should call
    -- Kora.shared.all() when building a list, but an accidental cached reference
    -- should still observe the newest snapshot rather than freeze forever.
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
    -- Epoch gap on a non-remove means we missed a reseed: pull a fresh snapshot
    -- rather than applying a delta onto stale data. On the server the snapshot is
    -- a same-VM export call; on the client it must go over the network.
    if epoch and m.epoch ~= 0 and epoch ~= m.epoch and action ~= 'remove' then
        if IsDuplicityVersion and IsDuplicityVersion() then
            local ok, all = pcall(function() return exports.kora_core:sharedSnapshotAll() end)
            if ok and type(all) == 'table' then
                for n, payload in pairs(all) do reseed(n, payload.keyField, payload.records, payload.epoch) end
            end
        else
            TriggerServerEvent('qbcore:registry:requestSnapshot')
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
            print(("^3[qbcore:shared]^7 onChange handler for '%s' errored: %s"):format(name, tostring(err)))
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

-- Net registrations below are CLIENT-ONLY on purpose: on the client the events arrive
-- over the wire and are dropped without RegisterNetEvent; on the server they are
-- same-VM events, and registering them would let any client inject records into every
-- consumer's mirror.
local isServerRealm = IsDuplicityVersion and IsDuplicityVersion()

if not isServerRealm then
    RegisterNetEvent('qbcore:registry:delta')
end
AddEventHandler('qbcore:registry:delta', function(name, action, key, record, epoch)
    applyDelta(name, action, key, record, epoch)
end)

-- Full-snapshot handler (initial seed + epoch-gap resync). Works in both realms.
if not isServerRealm then
    RegisterNetEvent('qbcore:registry:snapshotAll')   -- client path (server->client)
end
AddEventHandler('qbcore:registry:snapshotAll', function(all)
    for name, payload in pairs(all) do
        reseed(name, payload.keyField, payload.records, payload.epoch)
    end
end)

-- Seed the mirror as soon as kora_core is available. On the server this is a direct
-- export call (same process); on the client it asks the server for a snapshot.
CreateThread(function()
    if isServerRealm then
        -- Same process: pull the authoritative snapshot directly, retrying until
        -- kora_core's exports are up.
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
        -- Client: request the snapshot over the network; the snapshotAll handler
        -- above reseeds when it arrives.
        Wait(0)
        TriggerServerEvent('qbcore:registry:requestSnapshot')
    end
end)
