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

-- Fire the legacy full-blob events LOCALLY from the mirror. No network cost --
-- it's a table reference pass. Every legacy resource listening for
-- QBCore:Player:SetPlayerData keeps working unchanged.
local function fireLegacy(changedRoots)
    if Config.compat.fireLegacyPlayerDataEvent then
        TriggerEvent('QBCore:Player:SetPlayerData', mirror)
    end
    if changedRoots.job and (Config.compat.jobUpdateEventSource ~= 'server') then
        TriggerEvent('QBCore:Client:OnJobUpdate', mirror.job)
    end
    if changedRoots.gang and (Config.compat.jobUpdateEventSource ~= 'server') then
        TriggerEvent('QBCore:Client:OnGangUpdate', mirror.gang)
    end
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
RegisterNetEvent('QBCore:Player:SetPlayerData', function(data)
    -- Only act on a genuinely foreign payload (our own fireLegacy passes the
    -- SAME table reference we already hold; ignore that to avoid a loop).
    if data ~= mirror and type(data) == 'table' then
        print('^3[qbcore:rep]^7 a resource wrote PlayerData directly via the legacy event -- it bypassed the '
            .. 'delta stream and will be overwritten on the next server snapshot.')
        mirror = data
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
        prefix = type(pathPrefix) == 'table' and pathPrefix or { pathPrefix },
        handler = handler,
    }
    return id
end

---@param id integer
function Core.replication.offChange(id)
    subscribers[id] = nil
end

function Core.replication.requestResync()
    TriggerServerEvent('qbcore:rep:resync')
end

---@return table
function Core.replication.getStats()
    return { seq = stats.seq, resyncs = stats.resyncs, opsApplied = stats.opsApplied, lastDeltaAt = stats.lastDeltaAt }
end
