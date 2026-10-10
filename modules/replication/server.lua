-- Core.replication (server realm) -- delta emission with per-frame coalescing.
--
-- Legacy qb-core resends the entire PlayerData blob to a client on every field
-- change. Here the wire carries only DELTAS: each op is { p = keyArray, v = value }
-- (or { p, d = true } for a delete). Ops are coalesced per player per frame, so
-- 30 writes to metadata.hunger in one frame produce ONE op. A per-player `seq`
-- lets the client detect a dropped batch and request a resync.
--
-- Loaded before player.lua (player.adopt calls into here).

local PI = CoreInternal.player

-- Players with pending ops this frame: citizenid -> true. A single SetTimeout(0)
-- drains all of them at end of frame.
local pendingPlayers = {}
local flushScheduled = false

-- Rate-limit resync requests: citizenid -> last-served timestamp.
local lastResync = {}

-- Serialise a key path to a stable map key for per-frame op coalescing.
local function opKey(path)
    return table.concat(path, '\31')   -- unit separator; item/meta keys may contain '.'
end

local function isParentPath(parent, path)
    if #parent >= #path then return false end
    for i = 1, #parent do
        if parent[i] ~= path[i] then return false end
    end
    return true
end

local function scheduleFlush()
    if flushScheduled then return end
    flushScheduled = true
    SetTimeout(0, function()
        flushScheduled = false
        local players = pendingPlayers
        pendingPlayers = {}
        for cid in pairs(players) do
            local player = PI.byCitizenId[cid]
            if player then
                local ops = {}
                for _, op in pairs(player._pendingOps) do ops[#ops + 1] = op end
                player._pendingOps = {}
                if #ops > 0 then
                    player._seq = player._seq + 1
                    TriggerClientEvent('qbcore:rep:delta', player.source, player._seq, ops)
                end
            end
        end
    end)
end

---Queue one op for a player. Called by the funnel. Coalesces by path within the
---frame (last value wins). `value == nil` becomes a delete op.
---@param player table
---@param path (string|integer)[]
---@param value any
function Core.replication._queueOp(player, path, value)
    -- Overlapping paths must collapse so unordered flushing cannot replay a
    -- stale slot after an inventory replacement, or delete a revived root.
    for pendingKey, op in pairs(player._pendingOps) do
        if isParentPath(op.p, path) then
            op.v = Core.util.pathGet(player.PlayerData, op.p)
            op.d = op.v == nil and true or nil
            return
        end
        if isParentPath(path, op.p) then
            player._pendingOps[pendingKey] = nil
        end
    end
    local key = opKey(path)
    -- Copy the path array (the caller may reuse/mutate it).
    local pcopy = {}
    for i = 1, #path do pcopy[i] = path[i] end
    if value == nil then
        player._pendingOps[key] = { p = pcopy, d = true }
    else
        player._pendingOps[key] = { p = pcopy, v = value }
    end
    pendingPlayers[player.citizenid] = true
    scheduleFlush()
end

-- Send a full snapshot to a client (initial load + resync). Resets the client's
-- expected seq to the current server seq.
---@param player table
function Core.replication._sendSnapshot(player)
    TriggerClientEvent('qbcore:rep:snapshot', player.source, player._seq, player.PlayerData)
end

function Core.replication._adopt(player)
    player._pendingOps = player._pendingOps or {}
end

function Core.replication._forget(player)
    pendingPlayers[player.citizenid] = nil
    lastResync[player.citizenid] = nil
end

-- A client that detected a seq gap asks for a fresh snapshot. Rate-limited.
RegisterNetEvent('qbcore:rep:resync', function()
    local src = source
    local player = PI.bySource[src]
    if not player then return end
    local now = GetGameTimer()
    local last = lastResync[player.citizenid]
    if last and (now - last) < Config.replication.resyncRateLimit then return end
    lastResync[player.citizenid] = now
    Core.replication._sendSnapshot(player)
end)
