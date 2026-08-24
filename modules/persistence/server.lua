-- Core.persistence (server realm) -- dirty-column tracking, the two-gate
-- collectRows, position throttling, and the coalescing flush that feeds
-- qbsql's enqueueMany. Loaded BEFORE player.lua because player.login/create call
-- adopt()/seedEncoded()/insertNew() at runtime.
--
-- The JSON columns (money, charinfo, job, gang, position, metadata, inventory)
-- are encoded ONCE per flush and ONLY when dirty AND changed -- the two gates
-- that make a save write the minimum. Legacy qb-core re-encodes all seven on
-- every save regardless of what changed.

local PI = CoreInternal.player
local COLUMN_FOR = PI.COLUMN_FOR

-- Which PlayerData root key backs each DB column (inverse of COLUMN_FOR, but
-- position/name/phone need custom encoders below).
local COLUMN_SOURCE = {
    money = 'money', charinfo = 'charinfo', job = 'job', gang = 'gang',
    metadata = 'metadata', inventory = 'items',
}

-- Players with at least one dirty column since the last flush.
local dirty = {}   -- citizenid -> true

-- Position sampling state per citizenid: last persisted coords + timestamp.
local posState = {}   -- citizenid -> { x, y, z, at }

-- Encode one column's current value to the string that will hit the wire.
-- position/name/phone are scalar-ish and handled specially.
local function encodeColumn(player, column)
    if column == 'position' then
        local p = player.PlayerData.position or {}
        return json.encode({ x = p.x or 0.0, y = p.y or 0.0, z = p.z or 0.0, h = p.h or 0.0 })
    elseif column == 'name' then
        return tostring(player.PlayerData.name or 'unknown')
    elseif column == 'phone_number' then
        return player.PlayerData.phone and tostring(player.PlayerData.phone) or nil
    end
    local srcKey = COLUMN_SOURCE[column]
    return json.encode(player.PlayerData[srcKey] or (srcKey == 'inventory' and {} or {}))
end

-- --- public-to-modules API (not exported: all _-prefixed or on Core.persistence
-- but only meaningful internally; finalise still exports the non-_ ones, which
-- is harmless -- saveNow/flushAll are legitimately useful externally) ---

---Mark a DB column dirty for this player.
---@param player table
---@param column string
function Core.persistence._markDirty(player, column)
    if not column then return end
    player._dirty[column] = true
    dirty[player.citizenid] = true
end

-- Adopt a loaded player: seed _encoded from the CURRENT PlayerData so a login
-- that changes nothing writes nothing (the second gate needs a baseline).
function Core.persistence._adopt(player)
    Core.persistence._seedEncoded(player)
    posState[player.citizenid] = nil
end

-- Seed/refresh the _encoded baseline for every persisted column.
function Core.persistence._seedEncoded(player)
    for _, column in pairs(COLUMN_FOR) do
        player._encoded[column] = encodeColumn(player, column)
    end
end

function Core.persistence._forget(player)
    dirty[player.citizenid] = nil
    posState[player.citizenid] = nil
end

-- Sample a player's position at flush time (server-side, OneSync). Marks the
-- position column dirty only if the player moved past the epsilon or the max
-- age elapsed -- so a parked player never re-writes position.
local function samplePosition(player)
    local src = player.source
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local cid = player.citizenid
    local st = posState[cid]
    local now = GetGameTimer()

    local moved = true
    if st then
        local dx, dy, dz = coords.x - st.x, coords.y - st.y, coords.z - st.z
        local dist2 = dx * dx + dy * dy + dz * dz
        local eps = Config.persistence.positionEpsilon
        moved = dist2 >= (eps * eps) or (now - st.at) >= Config.persistence.positionMaxAge
    end

    if moved then
        player.PlayerData.position = { x = coords.x, y = coords.y, z = coords.z, h = heading }
        Core.persistence._markDirty(player, 'position')
        posState[cid] = { x = coords.x, y = coords.y, z = coords.z, at = now }
    end
end

-- Build the rows to enqueue for every dirty player. Applies the two gates.
-- Returns an array of { pk = citizenid, cols = {column = encoded} }.
local function collectRows()
    local rows, n = {}, 0
    for cid in pairs(dirty) do
        local player = PI.byCitizenId[cid]
        if player then
            local cols
            for column in pairs(player._dirty) do
                -- Never persist license/cid (immutable; the two-unique-key
                -- corruption hazard). They are not in COLUMN_FOR, so a mutation
                -- can't mark them dirty -- this is a belt-and-braces skip.
                if column ~= 'license' and column ~= 'cid' then
                    local encoded = encodeColumn(player, column)
                    -- Gate 2: byte-identical JSON means nothing actually
                    -- changed -> drop it, never reaches the wire.
                    if encoded ~= player._encoded[column] then
                        cols = cols or {}
                        cols[column] = encoded
                        player._encoded[column] = encoded
                    end
                end
            end
            if cols then
                n = n + 1
                rows[n] = { pk = cid, cols = cols }
            end
            player._dirty = {}
        end
    end
    dirty = {}
    return rows
end

-- Flush all dirty players in one enqueueMany (one boundary crossing).
---@return integer players flushed
function Core.persistence.flushAll()
    -- Sample positions for everyone online before collecting.
    for _, player in pairs(PI.bySource) do samplePosition(player) end
    local rows = collectRows()
    if #rows > 0 then
        -- Every Player in this cache came from _load() or _insertNew(), so its
        -- row already exists. A partial INSERT ... ON DUPLICATE KEY UPDATE is
        -- unsafe for players: MariaDB validates required immutable columns
        -- (license/cid) before considering the duplicate branch. Update-only
        -- batching keeps the compact dirty-column writes without that insert.
        QB.sql.enqueueMany('players', 'citizenid', rows, { mode = 'assign', writeMode = 'update' })
    end
    return #rows
end

-- Immediate save of one player (drop/logout path). Marks everything the player
-- has changed dirty (already tracked), samples position, then enqueues at
-- immediate priority so qbsql flushes it out of band.
---@param player table
function Core.persistence.saveNow(player)
    samplePosition(player)
    local cols
    for column in pairs(player._dirty) do
        if column ~= 'license' and column ~= 'cid' then
            local encoded = encodeColumn(player, column)
            if encoded ~= player._encoded[column] then
                cols = cols or {}
                cols[column] = encoded
                player._encoded[column] = encoded
            end
        end
    end
    player._dirty = {}
    dirty[player.citizenid] = nil
    if cols then
        QB.sql.enqueue('players', 'citizenid', { pk = player.citizenid, cols = cols }, {
            priority = 'immediate', mode = 'assign', writeMode = 'update',
        })
    end
end

-- Insert a brand-new character row with a plain INSERT (NOT an upsert), so a
-- genuine (license,cid) or citizenid collision raises rather than silently
-- overwriting a different row. Yields.
---@return boolean, string|nil
function Core.persistence._insertNew(citizenid, license, cid, data)
    local ok, err = QB.sql.execute(
        'INSERT INTO `players` (`citizenid`,`license`,`cid`,`name`,`money`,`charinfo`,`job`,`gang`,`position`,`metadata`,`inventory`,`phone_number`) '
        .. 'VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
        {
            citizenid, license, cid, data.name,
            json.encode(data.money), json.encode(data.charinfo),
            json.encode(data.job), json.encode(data.gang),
            json.encode(data.position), json.encode(data.metadata),
            json.encode(data.items or {}), data.phone,
        }
    )
    if ok == nil and err then return false, err end
    return true
end

-- Load a character's PlayerData from the DB by citizenid. Yields. Returns the
-- decoded blob or (nil, err).
---@param citizenid string
---@return table|nil, string|nil
function Core.persistence._load(citizenid)
    local row, err = QB.sql.single('SELECT * FROM `players` WHERE `citizenid` = ? AND `deleted_at` IS NULL', { citizenid })
    if not row then return nil, err or 'not found' end
    local function dec(s, fallback) local ok, v = pcall(json.decode, s or ''); return ok and v or fallback end

    -- PlayerData.items is a NUMERIC slot-keyed map (see modules/inventory/
    -- AGENTS.md); every write is setPath(src, {'items', slot}, record) with a
    -- numeric slot. But a sparse slot map serialises to a JSON *object*, and
    -- json.decode hands those keys back as STRINGS -- so a character restored
    -- from the database came back with items['1'] where every reader looks up
    -- items[1]. The inventory still rendered (the UI iterates pairs and reads
    -- item.slot), but any lookup by slot missed, which surfaced as
    -- "invalid item amount" on the first attempt to move an item after a
    -- relog. Re-key on load, preferring the slot recorded inside the item.
    local function decodeItems(s)
        local raw = dec(s, {})
        if type(raw) ~= 'table' then return {} end
        local out = {}
        for rawSlot, item in pairs(raw) do
            if type(item) == 'table' then
                local slot = math.floor(tonumber(item.slot) or tonumber(rawSlot) or 0)
                if slot > 0 then
                    item.slot = slot
                    out[slot] = item
                end
            end
        end
        return out
    end
    return {
        citizenid = row.citizenid,
        license = row.license,
        cid = row.cid,
        name = row.name,
        money = dec(row.money, {}),
        charinfo = dec(row.charinfo, {}),
        job = dec(row.job, {}),
        gang = dec(row.gang, {}),
        position = dec(row.position, { x = 0, y = 0, z = 70, h = 0 }),
        metadata = dec(row.metadata, {}),
        items = decodeItems(row.inventory),
        phone = row.phone_number,
    }
end

-- List a license's characters (multichar select). Yields.
---@param license string
---@return table[]
function Core.persistence._listCharacters(license)
    return QB.sql.query(
        'SELECT `citizenid`,`cid`,`name`,`charinfo`,`money`,`job` FROM `players` WHERE `license` = ? AND `deleted_at` IS NULL ORDER BY `cid`',
        { license }
    ) or {}
end

-- Soft-delete a character. Yields.
---@param citizenid string
---@return boolean
function Core.persistence._deleteCharacterRow(citizenid)
    local r = QB.sql.execute('UPDATE `players` SET `deleted_at` = NOW() WHERE `citizenid` = ?', { citizenid })
    return r ~= nil
end

-- --- the flush loop + shutdown hooks ---

CreateThread(function()
    local base = Config.persistence.interval
    local jitter = Config.persistence.intervalJitter or 0
    while true do
        local wait = base
        if jitter > 0 then
            wait = math.floor(base * (1.0 + (math.random() * 2 - 1) * jitter))
        end
        Wait(wait)
        local flushed = Core.persistence.flushAll()
        if flushed > 0 then
            -- Nudge qbsql to drain promptly rather than waiting its own interval.
            QB.sql.flush('players')
        end
    end
end)

-- txAdmin shutdown / scheduled restart: flush everyone immediately.
local function flushEveryoneNow()
    for _, player in pairs(PI.bySource) do Core.persistence.saveNow(player) end
    QB.sql.flush('players')
end

AddEventHandler('txAdmin:events:serverShuttingDown', flushEveryoneNow)
AddEventHandler('txAdmin:events:scheduledRestart', function(payload)
    if payload and payload.secondsRemaining and payload.secondsRemaining <= 60 then
        flushEveryoneNow()
    end
end)

-- Resource stop: best-effort final drain with a hard deadline. FXServer gives no
-- guarantee this yield completes, so this BOUNDS worst-case loss to one interval
-- rather than eliminating it (documented in AGENTS.md).
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, player in pairs(PI.bySource) do Core.persistence.saveNow(player) end
    QB.sql.flush('players')
end)
