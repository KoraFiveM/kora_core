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

-- ===========================================================================
-- Kora.player (CLIENT only) -- a local copy of the local player's data.
--
-- Target `canInteract` checks and HUD/UI code used to call
-- exports.kora_core:getPlayerData() every tick: a cross-resource call that
-- msgpack-copies the requested data each time. This keeps one LOCAL copy of
-- the roots a consumer reads (job, gang, metadata, charinfo by default; any
-- other root is added on first read), seeded once per root with getPlayerData
-- and patched by ONE onPlayerDataChange subscription per root. Reads are plain
-- table lookups. It is a read model for UI only: the server re-checks.
--
-- Re-attached when kora_core restarts (Kora.resources.onStart) and when
-- kora_lib restarts (Kora.onReady), so the subscriptions never silently die.
-- ===========================================================================
if not isServerRealm then
    -- The same matcher kora_core's server checkJob uses. Loaded into a private
    -- environment so the file's kora_core-only branch cannot touch our globals.
    local matchJobRule = (function()
        local path = 'modules/jobs/shared.lua'
        local source = assert(LoadResourceFile('kora_core', path), 'Unable to load @kora_core/' .. path)
        local chunk = assert(load(source, '@@kora_core/' .. path, 't', setmetatable({}, { __index = _G })))
        return chunk()
    end)()

    local player = {}
    local data = {}                 -- root -> local copy (nil until seeded)
    local watched = {}              -- root -> true
    local subIds = {}               -- root -> kora_core onPlayerDataChange id
    local handlers = {}             -- id -> { prefix = string[], fn = function }
    local nextHandlerId = 0
    local DEFAULT_ROOTS = { 'job', 'gang', 'metadata', 'charinfo' }

    local function pathGet(t, path)
        local node = t
        for i = 1, #path do
            if type(node) ~= 'table' then return nil end
            node = node[path[i]]
        end
        return node
    end

    local function pathSet(t, path, value)
        local node = t
        for i = 1, #path - 1 do
            local k = path[i]
            if type(node[k]) ~= 'table' then node[k] = {} end
            node = node[k]
        end
        node[path[#path]] = value
    end

    -- true when path `a` is path `b` or lies under it
    local function isUnder(a, b)
        if #b > #a then return false end
        for i = 1, #b do if a[i] ~= b[i] then return false end end
        return true
    end

    local function call(handler, path, value)
        local ok, err = pcall(handler.fn, path, value)
        if not ok then print(('^3[kora_core:player]^7 onChange handler errored: %s'):format(tostring(err))) end
    end

    -- A delta from kora_core. Handlers at or above the changed path get the
    -- delta; a handler deeper than it (an { 'job', 'onduty' } handler when
    -- setJob replaces the whole job) gets its own path's new value.
    local function onDelta(path, value)
        if type(path) ~= 'table' or path[1] == nil then return end
        pathSet(data, path, value)
        for _, handler in pairs(handlers) do
            if isUnder(path, handler.prefix) then
                call(handler, path, value)
            elseif isUnder(handler.prefix, path) then
                call(handler, handler.prefix, pathGet(data, handler.prefix))
            end
        end
    end

    -- After a login, logout or restart every handler sees its current value.
    local function announceAll()
        for _, handler in pairs(handlers) do call(handler, handler.prefix, pathGet(data, handler.prefix)) end
    end

    local function subscribe(root)
        local old = subIds[root]
        if old then
            subIds[root] = nil
            pcall(function() exports.kora_core:offPlayerDataChange(old) end)
        end
        local ok, id = pcall(function() return exports.kora_core:onPlayerDataChange({ root }, onDelta) end)
        if ok and id then subIds[root] = id end
    end

    local function seedRoot(root)
        local ok, value = pcall(function() return exports.kora_core:getPlayerData({ root }) end)
        if ok then data[root] = value end
    end

    local function watch(root)
        if watched[root] then return end
        watched[root] = true
        if GetResourceState('kora_core') == 'started' then
            subscribe(root)
            seedRoot(root)
        end
    end

    -- (Re)attach to a running kora_core. Idempotent: an old subscription is
    -- dropped before a new one is made, so running it twice never doubles events.
    local function attach()
        for root in pairs(watched) do subscribe(root) end
        seedRoot('citizenid')
        for root in pairs(watched) do seedRoot(root) end
        announceAll()
    end

    for i = 1, #DEFAULT_ROOTS do watched[DEFAULT_ROOTS[i]] = true end

    -- kora_core's snapshot (login, character switch, resync) arrives as this
    -- local event with the full data, so reseeding costs no export calls.
    AddEventHandler('qbcore:client:playerLoaded', function(snapshot)
        if type(snapshot) ~= 'table' then return end
        data.citizenid = snapshot.citizenid
        for root in pairs(watched) do data[root] = snapshot[root] end
        announceAll()
    end)

    RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
        for key in pairs(data) do data[key] = nil end
        announceAll()
    end)

    local function register()
        Kora.resources.onStart('kora_core', attach)
        Kora.resources.onStop('kora_core', function()
            -- kora_core's subscriber table died with it; the ids are meaningless now.
            for root in pairs(subIds) do subIds[root] = nil end
        end)
    end
    if rawget(Kora, 'onReady') then Kora.onReady(register) else register() end

    ---Reads the local copy: no export call, no copy. `path` is a root key
    ---('job') or a key array ({ 'metadata', 'hunger' }); nil returns the whole
    ---local table. A root outside the defaults is watched from its first read.
    ---The result is live: read it, never modify it.
    ---@param path string|(string|integer)[]|nil
    ---@return any
    function player.get(path)
        if path == nil then return data end
        if type(path) == 'table' then
            local root = path[1]
            if root == nil then return data end
            if not watched[root] and root ~= 'citizenid' then watch(root) end
            return pathGet(data, path)
        end
        if not watched[path] and path ~= 'citizenid' then watch(path) end
        return data[path]
    end

    ---@return boolean
    function player.isLoaded() return data.citizenid ~= nil end

    ---@return table|nil
    function player.job() return data.job end

    ---@return table|nil
    function player.gang() return data.gang end

    ---@param key string|nil nil returns the whole metadata table
    ---@return any
    function player.metadata(key)
        local metadata = data.metadata
        if key == nil then return metadata end
        if type(metadata) ~= 'table' then return nil end
        return metadata[key]
    end

    ---Same rule shape and reasons as the server's exports.kora_core:checkJob.
    ---For UI only (showing or hiding an option); the server must re-check.
    ---@param rule KoraJobRule|nil
    ---@return boolean ok
    ---@return string|nil reason
    function player.checkJob(rule)
        return matchJobRule(data.job, rule)
    end

    ---Runs `fn(path, value)` when the local copy changes at or under `prefix`
    ---(a root key or a key array), and once with the current value after every
    ---login, logout and kora_core restart. Handlers run in this resource.
    ---@param prefix string|(string|integer)[]
    ---@param fn fun(path: (string|integer)[], value: any)
    ---@return integer id
    function player.onChange(prefix, fn)
        if type(prefix) == 'string' then prefix = { prefix } end
        assert(type(prefix) == 'table' and prefix[1] ~= nil, 'Kora.player.onChange requires a root key or a key array')
        assert(type(fn) == 'function' or Kora.util.isCallable(fn), 'Kora.player.onChange requires a function')
        local copy = {}
        for i = 1, #prefix do copy[i] = prefix[i] end
        if not watched[copy[1]] and copy[1] ~= 'citizenid' then watch(copy[1]) end
        nextHandlerId = nextHandlerId + 1
        handlers[nextHandlerId] = { prefix = copy, fn = fn }
        return nextHandlerId
    end

    ---@param id integer
    ---@return boolean removed
    function player.offChange(id)
        if handlers[id] == nil then return false end
        handlers[id] = nil
        return true
    end

    Kora.player = player
end
