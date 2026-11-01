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

local isCallable = Kora.util.isCallable

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

-- Marker identifying our OWN compat re-fire. Table identity fails (RegisterNetEvent
-- makes CFX msgpack-copy the payload) and a boolean flag fails (TriggerEvent queues,
-- so the flag is reset before the handler runs). A nonce passed as a 2nd argument
-- survives both; legacy handlers take only `data` and ignore it.
local REFIRE_TOKEN = 'qbcore:rep:refire'
local pendingLegacy = nil

local function announceLegacyPlayerData(data, inventoryOnly)
    if not Config.compat.fireLegacyPlayerDataEvent then
        pendingLegacy = nil
        return
    end

    local interval = tonumber(Config.compat.inventoryPlayerDataEventInterval) or 0
    if inventoryOnly and interval > 0 then
        if pendingLegacy then return end
        -- Anchor the timer to the first change so continuous fire cannot defer it forever.
        local token = {}
        pendingLegacy = token
        SetTimeout(interval, function()
            if pendingLegacy ~= token then return end
            Core.replication.reannounceFull()
        end)
        return
    end

    pendingLegacy = nil
    local ok, err = pcall(TriggerEvent, 'QBCore:Player:SetPlayerData', data, REFIRE_TOKEN)
    if not ok then error(err, 0) end
end

--
-- QBCore:* payloads must be legacy-shaped (grade.level zero-based); this builds a
-- translated VIEW and never mutates `mirror` (one-based). Guarded on the specific
-- FUNCTION because Core is an auto-vivifying proxy, so `Core.compat` is always a table.
local function fireLegacy(changedRoots, inventoryOnly)
    local legacyData = Core.compat.toLegacyPlayerData and Core.compat.toLegacyPlayerData(mirror) or mirror

    -- Keep the global `QBCore.PlayerData` that legacy scripts read directly. Guarded:
    -- this module has no hard dependency on the QBCore global (isolated tests).
    if QBCore then QBCore.PlayerData = legacyData end

    announceLegacyPlayerData(legacyData, inventoryOnly)
    if changedRoots.job and (Config.compat.jobUpdateEventSource ~= 'server') then
        TriggerEvent('QBCore:Client:OnJobUpdate', legacyData.job)
    end
    if changedRoots.gang and (Config.compat.jobUpdateEventSource ~= 'server') then
        TriggerEvent('QBCore:Client:OnGangUpdate', legacyData.gang)
    end

    -- Stock qb-core fires QBCore:Client:OnPlayerUpdated (key, val) for job/gang changes;
    -- OnJobUpdate/OnGangUpdate above are not stock, so legacy listeners need this one.
    -- REFIRE_TOKEN as a 3rd arg tells compat/client/qb-core-events.lua this delta already
    -- fired OnJobUpdate/OnGangUpdate, so it does not fire them a second time.
    if changedRoots.job and (Config.compat.jobUpdateEventSource ~= 'server') then
        TriggerEvent('QBCore:Client:OnPlayerUpdated', 'job', legacyData.job, REFIRE_TOKEN)
    end
    if changedRoots.gang and (Config.compat.jobUpdateEventSource ~= 'server') then
        TriggerEvent('QBCore:Client:OnPlayerUpdated', 'gang', legacyData.gang, REFIRE_TOKEN)
    end
end

---Re-fire the full-blob legacy event from the mirror's CURRENT data, without touching the
---mirror. Callers must use this instead of a raw TriggerEvent('QBCore:Player:SetPlayerData'):
---without REFIRE_TOKEN the foreign-write acceptor below would merge the legacy-shaped
---(zero-based) payload into the one-based mirror.
---@return boolean  -- false if there is no mirror yet (nothing to announce)
function Core.replication.reannounceFull()
    pendingLegacy = nil
    if not mirror then return false end
    local legacyData = Core.compat.toLegacyPlayerData and Core.compat.toLegacyPlayerData(mirror) or mirror
    if QBCore then QBCore.PlayerData = legacyData end
    announceLegacyPlayerData(legacyData)
    return true
end

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
    local inventoryOnly = #ops > 0
    for _, op in ipairs(ops) do
        if op.d then
            pathSet(mirror, op.p, nil)
        else
            pathSet(mirror, op.p, op.v)
        end
        changedRoots[op.p[1]] = true
        if op.p[1] ~= 'items' then inventoryOnly = false end
        stats.opsApplied = stats.opsApplied + 1
        dispatch(op.p, op.v)
    end
    fireLegacy(changedRoots, inventoryOnly)
end)

-- Inbound legacy write: a foreign resource TriggerEvent's the full-blob event.
-- Accept it (replace the mirror) but warn -- it bypassed the delta stream and
-- will be overwritten by the next server snapshot.
RegisterNetEvent('QBCore:Player:SetPlayerData', function(data, token)
    -- Our own re-fire from fireLegacy: the mirror already holds exactly this.
    if token == REFIRE_TOKEN then return end
    -- Belt-and-braces for a local trigger from inside this resource that
    -- somehow lost the token (a genuinely foreign local trigger reports that
    -- resource's name, and a remote one reports nil).
    local writer = GetInvokingResource and GetInvokingResource() or nil
    if writer == GetCurrentResourceName() then return end
    if data == mirror or type(data) ~= 'table' then return end
    pendingLegacy = nil

    print(('^3[qbcore:rep]^7 %s wrote PlayerData directly via the legacy event -- it bypassed the '
        .. 'delta stream and will be overwritten on the next server snapshot.')
        :format(writer and ("resource '" .. writer .. "'") or 'an unknown resource'))

    -- Copy INTO the existing table: getData() returns the mirror as a LIVE reference,
    -- so reassigning would orphan callers' references.
    if not mirror then
        mirror = data
    else
        for k in pairs(mirror) do mirror[k] = nil end
        for k, v in pairs(data) do mirror[k] = v end
    end
end)

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
    pendingLegacy = nil
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
