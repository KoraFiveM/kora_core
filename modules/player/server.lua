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
-- Opaque same-VM capability for Core.money's ledger-to-item migration. It is
-- never exported, so another resource cannot forge the exception accepted by
-- setPath below.
local physicalCashWriteToken = {}

-- Resource-owned, replicated-only PlayerData roots. These fields let a domain
-- resource expose a read model to client UI without putting that domain's
-- authoritative state in the players.metadata JSON blob.
local playerDataFields = {}
local playerDataFieldWriteToken = {}

-- Path-prefix onChange subscribers: { id -> { resource, prefix (array), handler } }
local subscribers = {}
local nextSubId = 1

local isCallable = QB.util.isCallable

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

    local field = playerDataFields[path[1]]
    if field and not (opts and opts._playerDataFieldWriteToken == playerDataFieldWriteToken) then
        local invokingResource = GetInvokingResource() or GetCurrentResourceName()
        if invokingResource ~= field.resource then
            return false, ('PlayerData field %s is owned by %s'):format(path[1], field.resource)
        end
    end

    -- Once qbinventory owns a physical cash account, a generic direct write
    -- here would create a second balance beside the cash item. The only
    -- exception is Core.money's one-way, preflighted ledger-to-item migration.
    if path[1] == 'money' and Core.money and Core.money.isPhysicalCash
        and Core.money.isPhysicalCash(path[2]) and not (opts and opts._physicalCashToken == physicalCashWriteToken) then
        return false, 'physical cash account is inventory-owned'
    end

    Core.util.pathSet(player.PlayerData, path, value)

    -- Optional compat hook: keeps a legacy-shaped PlayerData table (returned
    -- to third-party resources across the export boundary, so it must be a
    -- real table, never a live metatable proxy -- those don't survive
    -- msgpack marshaling) incrementally in sync with every write this funnel
    -- makes, without qbcore's own modules knowing compat exists. nil unless
    -- compat/shared/coreobject.lua has registered it. See its own comment for
    -- why this is the single correct hook point (every mutation, including
    -- job/gang, routes through here).
    -- Core is an auto-vivifying proxy (build/initiate.lua) -- merely
    -- REFERENCING Core.compat materialises it as {}, so the presence check
    -- must be on the specific function, not the module table.
    if Core.compat.onPlayerDataChanged then
        Core.compat.onPlayerDataChanged(src, path, value)
    end

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

function PI._setPhysicalCashLedger(src, account, value)
    return Core.player.setPath(src, { 'money', account }, value, { _physicalCashToken = physicalCashWriteToken })
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

local RESERVED_PLAYER_DATA_FIELDS = {
    source = true,
    citizenid = true,
    license = true,
    cid = true,
}

for key in pairs(COLUMN_FOR) do RESERVED_PLAYER_DATA_FIELDS[key] = true end

local function validPlayerDataField(key)
    return type(key) == 'string' and #key <= 32 and key:match('^[a-z][%w_]*$') ~= nil
        and not RESERVED_PLAYER_DATA_FIELDS[key]
end

local function loadPlayerDataField(field, player)
    local ok, value, err = pcall(field.provider, player.source, player.citizenid)
    if not ok then return nil, tostring(value) end
    if err then return nil, tostring(err) end
    return Core.util.deepClone(value)
end

---Register a resource-owned, replicated-only root field. The provider is run
---before each initial snapshot and receives (source, citizenid). Its returned
---value is never persisted by qbcore.
---@param key string
---@param provider fun(src:integer, citizenid:string):any, string|nil
---@return boolean, string|nil
function Core.player.registerPlayerDataField(key, provider)
    if not validPlayerDataField(key) then return false, 'invalid or reserved PlayerData field' end
    if not isCallable(provider) then return false, 'provider must be callable' end

    local resource = GetInvokingResource() or GetCurrentResourceName()
    local existing = playerDataFields[key]
    if existing then
        if existing.resource == resource then return false, 'PlayerData field is already registered' end
        return false, ('PlayerData field is owned by %s'):format(existing.resource)
    end

    local field = { resource = resource, provider = provider }
    playerDataFields[key] = field

    -- A resource can restart while characters are already online. Hydrate
    -- those sessions immediately; ordinary logins are hydrated in adopt().
    for src, player in pairs(bySource) do
        local value, err = loadPlayerDataField(field, player)
        if err then
            print(('^3[qbcore:player]^7 %s could not hydrate PlayerData.%s for %s: %s')
                :format(resource, key, player.citizenid, err))
        else
            Core.player.setPath(src, { key }, value, { _playerDataFieldWriteToken = playerDataFieldWriteToken })
        end
    end
    return true
end

---Update a registered replicated-only field. Only its registering resource can
---write it; server authority must remain in that resource's own store/cache.
---@param src integer
---@param key string
---@param value any
---@return boolean, string|nil
function Core.player.setPlayerDataField(src, key, value)
    local field = playerDataFields[key]
    if not field then return false, 'PlayerData field is not registered' end
    local resource = GetInvokingResource() or GetCurrentResourceName()
    if field.resource ~= resource then return false, ('PlayerData field is owned by %s'):format(field.resource) end
    return Core.player.setPath(src, { key }, value, { _playerDataFieldWriteToken = playerDataFieldWriteToken })
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

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then return end
    for id, subscriber in pairs(subscribers) do
        if subscriber.resource == resource then subscribers[id] = nil end
    end
    for key, field in pairs(playerDataFields) do
        if field.resource == resource then
            playerDataFields[key] = nil
            for src in pairs(bySource) do
                Core.player.setPath(src, { key }, nil, { _playerDataFieldWriteToken = playerDataFieldWriteToken })
            end
        end
    end
end)

-- --- lifecycle ---

-- Insert a fully-hydrated Player into the caches and fire loaded events.
local function adopt(src, player)
    player.source = src
    player.PlayerData.source = src
    bySource[src] = player
    byCitizenId[player.citizenid] = player
    Core.persistence._adopt(player)
    Core.replication._adopt(player)

    -- Hydrate external read models after persistence has captured its baseline
    -- but before any load event or snapshot can expose an incomplete shape.
    for key, field in pairs(playerDataFields) do
        local value, err = loadPlayerDataField(field, player)
        if err then
            print(('^3[qbcore:player]^7 %s could not hydrate PlayerData.%s for %s: %s')
                :format(field.resource, key, player.citizenid, err))
        else
            Core.player.setPath(src, { key }, value, {
                silent = true,
                _playerDataFieldWriteToken = playerDataFieldWriteToken,
            })
        end
    end

    -- qbinventory may own the physical cash account. Convert any persisted
    -- ledger balance before a snapshot or legacy load event can expose it;
    -- failure is fail-closed, avoiding a hidden or duplicated balance.
    if Core.money and Core.money.migratePhysicalCash then
        local migrated, migrateErr = Core.money.migratePhysicalCash(src)
        if not migrated then
            bySource[src] = nil
            byCitizenId[player.citizenid] = nil
            Core.replication._forget(player)
            Core.persistence._forget(player)
            return false, migrateErr
        end
    end

    -- Legacy load events (both directions), plus the modern one.
    -- Stock qb-core sends the Player wrapper. Legacy resources (including
    -- qb-inventory) immediately dereference Player.PlayerData here.
    TriggerEvent('QBCore:Server:PlayerLoaded', player)                     -- legacy server-side
    TriggerEvent('qbcore:server:playerLoaded', src, player.citizenid)     -- modern
    Core.replication._sendSnapshot(player)                                 -- prime the client mirror
    if Core.money and Core.money.syncState then Core.money.syncState(src) end
    -- The state bag is the authoritative client-facing character-session
    -- signal. It intentionally follows the snapshot so state-bag consumers
    -- can show UI only after the local PlayerData mirror is usable.
    Player(src).state:set('qbcore:loggedIn', true, true)
    -- Legacy mirror. Real qb-core sets a bare 'isLoggedIn' key, which legacy
    -- consumers read directly as LocalPlayer.state['isLoggedIn'] (real
    -- qb-doorlock's client.lua gates its whole main loop on it). The
    -- namespaced key above stays the one qbcore's own resources use; this is
    -- purely the legacy-facing alias, same "rebuilt legacy view alongside the
    -- modern shape" pattern compat/shared/coreobject.lua uses for grades.
    Player(src).state:set('isLoggedIn', true, true)
    -- Preserve the legacy client event, but dispatch it only after the
    -- snapshot has reached the client.  Legacy consumers now observe usable
    -- PlayerData rather than having to race the replication channel.
    TriggerClientEvent('QBCore:Client:OnPlayerLoaded', src)
    return true
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
    return adopt(src, player)
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
local creatingCharacter = {}

local function trim(value)
    return type(value) == 'string' and QB.util.trim(value) or nil
end

local function boundedText(value, field, minimum, maximum)
    value = trim(value)
    if not value or value:find('[%z\1-\31\127]') then return nil, ('invalid %s'):format(field) end
    local ok, length = pcall(utf8.len, value)
    if not ok or not length or length < minimum or length > maximum then
        return nil, ('%s must be between %d and %d characters'):format(field, minimum, maximum)
    end
    return value
end

local function validBirthdate(value)
    if type(value) ~= 'string' then return false end
    local year, month, day = value:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    if not year or month < 1 or month > 12 then return false end
    local days = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if year % 400 == 0 or (year % 4 == 0 and year % 100 ~= 0) then days[2] = 29 end
    if day < 1 or day > days[month] then return false end
    return value <= os.date('!%Y-%m-%d')
end

local function normalizeCharinfo(raw)
    raw = type(raw) == 'table' and raw or {}
    local firstname, err = boundedText(raw.firstname, 'first name', 1, 24)
    if not firstname then return nil, err end
    local lastname
    lastname, err = boundedText(raw.lastname, 'last name', 1, 24)
    if not lastname then return nil, err end

    local birthdate = raw.birthdate or '1990-01-01'
    if not validBirthdate(birthdate) then return nil, 'birth date must be a valid non-future YYYY-MM-DD date' end

    local gender = tonumber(raw.gender == nil and 0 or raw.gender)
    if gender ~= 0 and gender ~= 1 then return nil, 'gender must be 0 or 1' end

    local nationality
    nationality, err = boundedText(raw.nationality or 'USA', 'nationality', 2, 32)
    if not nationality then return nil, err end

    return {
        firstname = firstname,
        lastname = lastname,
        birthdate = birthdate,
        gender = gender,
        nationality = nationality,
        -- Never accept a client-supplied phone. There is no phone allocation
        -- service in this core yet, so generate the same seven-digit shape the
        -- legacy UI used, but on the authoritative side of the boundary.
        phone = tostring(math.random(1000000, 9999999)),
    }
end

local function createCharacterUnlocked(src, charinfo, cid)
    if bySource[src] then return nil, 'source already logged in' end
    local normalizedCharinfo, validationErr = normalizeCharinfo(charinfo)
    if not normalizedCharinfo then return nil, validationErr end
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
    local data = PI.freshData(citizenid, license, cid, normalizedCharinfo)

    -- Only authoritative creation grants eligibility; loading an old character
    -- must never recreate a consumed cityhall starter entitlement.
    data.metadata.starterItems = {}
    local starterItems = QBCore and QBCore.Shared and QBCore.Shared.StarterItems or {}
    for _, starterItem in pairs(starterItems) do
        if type(starterItem) == 'table' and type(starterItem.item) == 'string' then
            data.metadata.starterItems[starterItem.item] = true
        end
    end

    local ok, err = Core.persistence._insertNew(citizenid, license, cid, data)
    if not ok then return nil, err end

    Core.identity.recordIdentifiers(citizenid, Core.identity.getIdentifiers(src))

    local player = {
        source = src, citizenid = citizenid, license = license, cid = cid,
        PlayerData = data, _dirty = {}, _encoded = {}, _pendingOps = {}, _seq = 0,
    }
    -- Seed _encoded from the freshly-inserted values so the first save is a no-op.
    Core.persistence._seedEncoded(player)
    local adopted, adoptErr = adopt(src, player)
    if not adopted then return nil, adoptErr end
    return citizenid
end

function Core.player.createCharacter(src, charinfo, cid)
    if bySource[src] then return nil, 'source already logged in' end
    if creatingCharacter[src] then return nil, 'character creation already in progress' end
    creatingCharacter[src] = true
    local results = table.pack(pcall(createCharacterUnlocked, src, charinfo, cid))
    creatingCharacter[src] = nil
    if not results[1] then error(results[2], 0) end
    return table.unpack(results, 2, results.n)
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
    Player(src).state:set('isLoggedIn', false, true) -- legacy mirror, see login()
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
    -- Legacy-named events on the SAME disconnect path (verified against real
    -- qb-core v1.3.0 source). Both are server-LOCAL only -- upstream sends
    -- nothing to the disconnecting client either, since it's already gone.
    TriggerEvent('QBCore:Server:PlayerDropped', src, reason)
    TriggerEvent('QBCore:Server:OnPlayerUnload', src)
end

AddEventHandler('playerDropped', function(reason)
    Core.player.dropPlayer(source, reason)
end)

-- Readiness marker so @qbcore/init.lua / consumers can detect the core is up.
local coreReady = false
function Core.player.isCoreReady() return coreReady end
CreateThread(function() Wait(0); coreReady = true end)
