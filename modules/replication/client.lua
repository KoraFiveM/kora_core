-- Core.replication (client realm) -- the local PlayerData mirror, delta apply,
-- seq/resync safety net, local onChange subscribers, and the legacy compat
-- events (fired CLIENT-SIDE from the already-mirrored table, so they never cross
-- the network).

local mirror = nil          -- the local PlayerData table (nil until first snapshot)
local expectedSeq = 0
local stats = { seq = 0, resyncs = 0, opsApplied = 0, lastDeltaAt = 0 }

-- Local subscribers: id -> { prefix (array), handler }
local subscribers = {}
local nextSubId = 1

local function isCallable(x)
    if type(x) == 'function' then return true end
    local mt = getmetatable(x)
    return mt ~= nil and type(mt.__call) == 'function'
end

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

local function pathMatchesPrefix(path, prefix)
    if #prefix > #path then return false end
    for i = 1, #prefix do if path[i] ~= prefix[i] then return false end end
    return true
end

local function dispatch(path, value)
    for _, sub in pairs(subscribers) do
        if pathMatchesPrefix(path, sub.prefix) then
            local ok, err = pcall(sub.handler, path, value)
            if not ok then print(("^3[qbcore:rep]^7 onChange errored: %s"):format(tostring(err))) end
        end
    end
end

-- Identifying our OWN compatibility re-fire needs a marker that survives the
-- trip, because neither obvious approach works:
--   * table identity (`data ~= mirror`) -- the name is registered with
--     RegisterNetEvent, so CFX msgpack-copies the payload even for a local
--     TriggerEvent; the handler never sees the same table back.
--   * a boolean set/reset around the TriggerEvent call -- TriggerEvent QUEUES,
--     it does not dispatch synchronously, so the flag is already back to false
--     by the time the handler runs a tick later.
-- A nonce passed as a second argument survives serialization and is immune to
-- dispatch timing. Legacy handlers take only `data`, so the extra argument is
-- invisible to them.
local REFIRE_TOKEN = 'qbcore:rep:refire'

-- Fire the legacy full-blob events LOCALLY from the mirror. Every legacy
-- resource listening for QBCore:Player:SetPlayerData keeps working unchanged.
--
-- QBCore:*-named events are the legacy-compat protocol (real qb-core's own
-- event names) -- their payload must be legacy-shaped, i.e. job/gang
-- grade.level translated to zero-based (see Core.compat.toLegacyPlayerData's
-- comment; qbcore's internal model stays one-based throughout, including
-- `mirror` here -- this builds a translated VIEW for the event payload only,
-- never mutates `mirror` itself). Guarded on the specific FUNCTION (not
-- `Core.compat` itself -- Core is an auto-vivifying proxy, see build/
-- initiate.lua, so merely referencing `Core.compat` always returns a table).
local function fireLegacy(changedRoots)
    local legacyData = Core.compat.toLegacyPlayerData and Core.compat.toLegacyPlayerData(mirror) or mirror

    -- Real qb-core keeps a plain global `QBCore.PlayerData` table, updated on
    -- every player-data change -- plenty of legacy scripts read it directly
    -- instead of calling GetPlayerData(). We don't maintain one anywhere
    -- else, so this is the one place both the data AND the "something
    -- changed" signal already exist. Guarded: this module (unlike compat/)
    -- has no hard dependency on the QBCore global existing (e.g. a test that
    -- dofiles only replication/client.lua in isolation).
    if QBCore then QBCore.PlayerData = legacyData end

    if Config.compat.fireLegacyPlayerDataEvent then
        local ok, err = pcall(TriggerEvent, 'QBCore:Player:SetPlayerData', legacyData, REFIRE_TOKEN)
        if not ok then error(err, 0) end
    end
    if changedRoots.job and (Config.compat.jobUpdateEventSource ~= 'server') then
        TriggerEvent('QBCore:Client:OnJobUpdate', legacyData.job)
    end
    if changedRoots.gang and (Config.compat.jobUpdateEventSource ~= 'server') then
        TriggerEvent('QBCore:Client:OnGangUpdate', legacyData.gang)
    end
end

---Re-fire the full-blob legacy event from the mirror's CURRENT data, without
---touching the mirror. Used by compat/client/qb-core-events.lua's
---QBCore:Client:OnPlayerUpdated handler (key == 'all'/nil case) so it never
---has to TriggerEvent('QBCore:Player:SetPlayerData', ...) itself -- doing so
---directly WITHOUT REFIRE_TOKEN would be caught by this module's own
---foreign-write acceptor below (the "an unknown resource wrote PlayerData
---directly" handler), which merges the payload INTO the live mirror -- and
---that payload is legacy-shaped (zero-based grade.level), so it would corrupt
---the internal one-based mirror. Going through this function instead reuses
---the exact same REFIRE_TOKEN'd path fireLegacy already uses on every delta,
---so the resulting local TriggerEvent is safely recognised as our own re-fire
---and ignored by the acceptor.
---@return boolean  -- false if there is no mirror yet (nothing to announce)
function Core.replication.reannounceFull()
    if not mirror then return false end
    local legacyData = Core.compat.toLegacyPlayerData and Core.compat.toLegacyPlayerData(mirror) or mirror
    if QBCore then QBCore.PlayerData = legacyData end
    if Config.compat.fireLegacyPlayerDataEvent then
        local ok, err = pcall(TriggerEvent, 'QBCore:Player:SetPlayerData', legacyData, REFIRE_TOKEN)
        if not ok then error(err, 0) end
    end
    return true
end

-- Full snapshot: replace the mirror wholesale and reset the expected seq.
RegisterNetEvent('qbcore:rep:snapshot', function(seq, data)
    mirror = data
    expectedSeq = seq
    stats.seq = seq
    TriggerEvent('qbcore:client:playerLoaded', mirror)
    fireLegacy({ job = true, gang = true })
end)

-- Delta batch: apply ops in order. A seq gap means we missed a batch -> request
-- a resync (server rate-limits) rather than applying onto stale data.
RegisterNetEvent('qbcore:rep:delta', function(seq, ops)
    if not mirror then
        -- No snapshot yet; ask for one.
        TriggerServerEvent('qbcore:rep:resync')
        return
    end
    if seq ~= expectedSeq + 1 then
        stats.resyncs = stats.resyncs + 1
        TriggerServerEvent('qbcore:rep:resync')
        return
    end
    expectedSeq = seq
    stats.seq = seq
    stats.lastDeltaAt = GetGameTimer()

    local changedRoots = {}
    for _, op in ipairs(ops) do
        if op.d then
            pathSet(mirror, op.p, nil)
        else
            pathSet(mirror, op.p, op.v)
        end
        changedRoots[op.p[1]] = true
        stats.opsApplied = stats.opsApplied + 1
        dispatch(op.p, op.v)
    end
    fireLegacy(changedRoots)
end)

-- Inbound legacy write: a foreign resource TriggerEvent's the full-blob event.
-- Accept it (replace the mirror) but warn -- it bypassed the delta stream and
-- will be overwritten by the next server snapshot.
RegisterNetEvent('QBCore:Player:SetPlayerData', function(data, token)
    -- Our own re-fire from fireLegacy above: nothing to do, the mirror already
    -- holds exactly this. See REFIRE_TOKEN for why neither table identity nor a
    -- boolean flag can detect it.
    if token == REFIRE_TOKEN then return end
    -- Belt-and-braces for a local trigger from inside this resource that
    -- somehow lost the token (a genuinely foreign local trigger reports that
    -- resource's name, and a remote one reports nil).
    local writer = GetInvokingResource and GetInvokingResource() or nil
    if writer == GetCurrentResourceName() then return end
    if data == mirror or type(data) ~= 'table' then return end

    print(('^3[qbcore:rep]^7 %s wrote PlayerData directly via the legacy event -- it bypassed the '
        .. 'delta stream and will be overwritten on the next server snapshot.')
        :format(writer and ("resource '" .. writer .. "'") or 'an unknown resource'))

    -- Accept the write, but copy INTO the existing table rather than replacing
    -- it. getData() with no path returns the mirror as a LIVE reference
    -- (documented in this module's AGENTS.md), so reassigning here would
    -- orphan every reference callers are already holding -- the same
    -- "clear in place, never reassign" discipline modules/registry/shared.lua
    -- applies to its materialised tables.
    if not mirror then
        mirror = data
    else
        for k in pairs(mirror) do mirror[k] = nil end
        for k, v in pairs(data) do mirror[k] = v end
    end
end)

-- --- public API ---

---Read the local mirror (a live reference with no path, or a value by path).
---@param path (string|integer)[]|nil
---@return any
function Core.replication.getData(path)
    if not mirror then return nil end
    if not path then return mirror end
    return pathGet(mirror, path)
end

---@param pathPrefix (string|integer)[]
---@param handler fun(path:table, value:any)
---@return integer|nil, string|nil
function Core.replication.onChange(pathPrefix, handler)
    if not isCallable(handler) then return nil, 'handler must be callable' end
    local id = nextSubId
    nextSubId = nextSubId + 1
    subscribers[id] = {
        resource = GetInvokingResource() or GetCurrentResourceName(),
        prefix = type(pathPrefix) == 'table' and pathPrefix or { pathPrefix },
        handler = handler,
    }
    return id
end

---@param id integer
function Core.replication.offChange(id)
    subscribers[id] = nil
end

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    if mirror then
        for key in pairs(mirror) do mirror[key] = nil end
    end
    mirror = nil
    expectedSeq = 0
    stats.seq = 0
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then return end
    for id, subscriber in pairs(subscribers) do
        if subscriber.resource == resource then subscribers[id] = nil end
    end
end)

function Core.replication.requestResync()
    TriggerServerEvent('qbcore:rep:resync')
end

---@return table
function Core.replication.getStats()
    return { seq = stats.seq, resyncs = stats.resyncs, opsApplied = stats.opsApplied, lastDeltaAt = stats.lastDeltaAt }
end
