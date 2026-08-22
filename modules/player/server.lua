-- Core.player (server realm) -- the authoritative player cache and the SINGLE
-- mutation funnel, Core.player.setPath. Every money/job/metadata/inventory
-- change routes through setPath so dirty-tracking, delta replication, and
-- onChange subscribers are handled in exactly one place.
--
-- Caches (in-memory, zero DB reads on hot paths):
--   bySource[src]        -> Player
--   byCitizenId[cid]     -> Player
-- A Player is never crossed to another resource in the modern API; getPlayer()
-- returns a plain deep-cloned snapshot (see the modern-API stance in AGENTS.md).

local PI = CoreInternal.player
local COLUMN_FOR = PI.COLUMN_FOR

local bySource = {}
local byCitizenId = {}
PI.bySource = bySource
PI.byCitizenId = byCitizenId

-- Path-prefix onChange subscribers: { id -> { resource, prefix (array), handler } }
local subscribers = {}
local nextSubId = 1

local function isCallable(x)
    if type(x) == 'function' then return true end
    local mt = getmetatable(x)
    return mt ~= nil and type(mt.__call) == 'function'
end

-- Does `path` start with `prefix`? Both are key arrays.
local function pathMatchesPrefix(path, prefix)
    if #prefix > #path then return false end
    for i = 1, #prefix do
        if path[i] ~= prefix[i] then return false end
    end
    return true
end

-- --- the funnel ---

---THE single mutation entry point. Writes PlayerData at `path`, marks the
---owning DB column dirty, queues a client delta, and fires matching subscribers.
---@param src integer
---@param path (string|integer)[]
---@param value any
---@param opts table|nil  -- { silent = true skips replication (rare) }
---@return boolean, string|nil
function Core.player.setPath(src, path, value, opts)
    local player = bySource[src]
    if not player then return false, 'no such player' end
    if type(path) ~= 'table' or #path == 0 then return false, 'path must be a non-empty array' end

    Core.util.pathSet(player.PlayerData, path, value)

    local column = COLUMN_FOR[path[1]]
    if column then
        Core.persistence._markDirty(player, column)
    end

    if not (opts and opts.silent) then
        Core.replication._queueOp(player, path, value)
    end

    -- Fire server-side subscribers whose prefix matches this path.
    for _, sub in pairs(subscribers) do
        if pathMatchesPrefix(path, sub.prefix) then
            local ok, err = pcall(sub.handler, src, path, value)
            if not ok then
                print(("^3[qbcore:player]^7 onChange handler errored: %s"):format(tostring(err)))
            end
        end
    end

    -- Inventory authorities may keep session revisions independently of
    -- PlayerData persistence. This generic notification preserves qbcore's
    -- ownership while allowing them to invalidate stale views after an item
    -- write made directly through the funnel.
    if path[1] == 'items' then
        TriggerEvent('qbcore:server:inventoryChanged', src, Core.util.deepClone(path), Core.util.deepClone(value))
    end
    return true
end

-- --- reads ---

---@param src integer
---@return table|nil  -- a deep-cloned PlayerData snapshot (safe to cross the export boundary)
function Core.player.getPlayer(src)
    local player = bySource[src]
    if not player then return nil end
    return Core.util.deepClone(player.PlayerData)
end

---Internal: the LIVE Player handle (never exported; used by compat & modules).
---@param src integer
---@return table|nil
function PI.handle(src) return bySource[src] end

---@param citizenid string
---@return table|nil
function Core.player.getPlayerByCitizenId(citizenid)
    local player = byCitizenId[citizenid]
    return player and Core.util.deepClone(player.PlayerData) or nil
end

---Read a sub-path of a player's data without cloning the whole blob. With no
---path, returns a full clone.
---@param src integer
---@param path (string|integer)[]|nil
---@return any
function Core.player.getPlayerData(src, path)
    local player = bySource[src]
    if not player then return nil end
    if not path then return Core.util.deepClone(player.PlayerData) end
    local v = Core.util.pathGet(player.PlayerData, path)
    return (type(v) == 'table') and Core.util.deepClone(v) or v
end

---@return integer[]
function Core.player.getPlayers()
    local out = {}
    for src in pairs(bySource) do out[#out + 1] = src end
    return out
end

---@return table[]  -- snapshots of every online player
function Core.player.getAllPlayers()
    local out = {}
    for _, player in pairs(bySource) do out[#out + 1] = Core.util.deepClone(player.PlayerData) end
    return out
end

-- --- subscriptions ---

---Subscribe to changes under a path prefix. handler(src, path, value). Prefix is
---a key array, e.g. {'money'} or {'metadata','hunger'}.
---@param pathPrefix (string|integer)[]
---@param handler fun(src:integer, path:table, value:any)
---@return integer|nil, string|nil
function Core.player.onChange(pathPrefix, handler)
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
function Core.player.offChange(id)
    subscribers[id] = nil
end

-- --- lifecycle ---

-- Insert a fully-hydrated Player into the caches and fire loaded events.
local function adopt(src, player)
    player.source = src
    player.PlayerData.source = src
    bySource[src] = player
    byCitizenId[player.citizenid] = player
    Core.persistence._adopt(player)
    Core.replication._adopt(player)

    -- Legacy load events (both directions), plus the modern one.
    TriggerEvent('QBCore:Server:PlayerLoaded', player.PlayerData)          -- legacy server-side
    TriggerClientEvent('QBCore:Client:OnPlayerLoaded', src)               -- legacy client-side
    TriggerEvent('qbcore:server:playerLoaded', src, player.citizenid)     -- modern
    Core.replication._sendSnapshot(player)                                 -- prime the client mirror
    -- The state bag is the authoritative client-facing character-session
    -- signal. It intentionally follows the snapshot so state-bag consumers
    -- can show UI only after the local PlayerData mirror is usable.
    Player(src).state:set('qbcore:loggedIn', true, true)
end

---Log a player in with already-loaded data (from persistence.load). Builds the
---Player handle around the DB blob and adopts it.
---@param src integer
---@param citizenid string
---@param data table  -- decoded PlayerData
---@return boolean, string|nil
function Core.player.login(src, citizenid, data)
    if bySource[src] then return false, 'source already logged in' end
    data.source = src
    data.citizenid = citizenid
    local player = {
        source = src,
        citizenid = citizenid,
        license = data.license,
        cid = data.cid or 1,
        PlayerData = data,
        _dirty = {},
        _encoded = {},           -- seeded by persistence.adopt from the DB row
        _pendingOps = {},
        _seq = 0,
    }
    adopt(src, player)
    return true
end

---Create a brand-new character for a source. Returns (citizenid) or (nil, err).
---An explicit `cid` (e.g. from an admin tool) is honoured if it's in bounds
---and free; the common case (nil, from qb-multicharacter's self-serve
---create) gets the next free slot computed HERE, server-side -- a client's
---own slot guess is never trusted for this, since it gates the character
---count limit below.
---@param src integer
---@param charinfo table
---@param cid integer|nil
---@return string|nil, string|nil
function Core.player.createCharacter(src, charinfo, cid)
    local license = Core.identity.primary(src)
    if not license then return nil, 'could not resolve primary identifier' end

    local maxCharacters = Core.users.getMaxCharacters(license)
    local existing = Core.persistence._listCharacters(license)
    local taken = {}
    for _, character in ipairs(existing) do taken[character.cid] = true end

    if cid then
        if cid < 1 or cid > maxCharacters or taken[cid] then
            return nil, 'requested character slot is unavailable'
        end
    elseif #existing >= maxCharacters then
        return nil, 'character limit reached'
    else
        for candidate = 1, maxCharacters do
            if not taken[candidate] then
                cid = candidate
                break
            end
        end
    end

    -- Unreachable in practice: the elseif above already guarantees a free
    -- slot exists in 1..maxCharacters whenever the loop runs. Asserted
    -- rather than left implicit so a future change to the branch above fails
    -- loudly instead of inserting a row with a nil cid.
    assert(cid ~= nil, 'createCharacter: failed to compute a free slot')

    local citizenid = Core.identity.generateCitizenId()
    local data = PI.freshData(citizenid, license, cid, charinfo or {})

    local ok, err = Core.persistence._insertNew(citizenid, license, cid, data)
    if not ok then return nil, err end

    Core.identity.recordIdentifiers(citizenid, Core.identity.getIdentifiers(src))

    local player = {
        source = src, citizenid = citizenid, license = license, cid = cid,
        PlayerData = data, _dirty = {}, _encoded = {}, _pendingOps = {}, _seq = 0,
    }
    -- Seed _encoded from the freshly-inserted values so the first save is a no-op.
    Core.persistence._seedEncoded(player)
    adopt(src, player)
    return citizenid
end

---Log a player out (keep the connection, drop the character). Flushes first.
---@param src integer
---@return boolean
function Core.player.logout(src)
    local player = bySource[src]
    if not player then return false end
    Core.persistence.saveNow(player)
    -- Clear this before any legacy unload notifications or cache teardown so
    -- state-bag consumers immediately stop rendering character-only UI.
    Player(src).state:set('qbcore:loggedIn', false, true)
    TriggerClientEvent('QBCore:Client:OnPlayerUnload', src)
    TriggerEvent('QBCore:Server:OnPlayerUnload', src)
    byCitizenId[player.citizenid] = nil
    bySource[src] = nil
    Core.replication._forget(player)
    Core.persistence._forget(player)
    return true
end

-- Handle a hard disconnect: flush immediately, then evict from every cache.
---@param src integer
---@param reason string|nil
function Core.player.dropPlayer(src, reason)
    local player = bySource[src]
    if not player then return end
    Core.persistence.saveNow(player)
    byCitizenId[player.citizenid] = nil
    bySource[src] = nil
    Core.replication._forget(player)
    Core.persistence._forget(player)
    TriggerEvent('qbcore:server:playerDropped', src, player.citizenid, reason)
end

AddEventHandler('playerDropped', function(reason)
    Core.player.dropPlayer(source, reason)
end)

-- Readiness marker so @qbcore/init.lua / consumers can detect the core is up.
local coreReady = false
function Core.player.isCoreReady() return coreReady end
CreateThread(function() Wait(0); coreReady = true end)
