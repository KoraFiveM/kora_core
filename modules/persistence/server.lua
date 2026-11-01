-- Core.persistence (server realm) -- dirty-column tracking, the two-gate
-- collectRows, position throttling, and the coalescing flush that feeds
-- kora_sql's enqueueMany. Loaded BEFORE player.lua because player.login/create call
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

local dirty = {}   -- citizenid -> true

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
        return player.PlayerData.phone and tostring(player.PlayerData.phone) or Kora.sql.NULL
    end
    local srcKey = COLUMN_SOURCE[column]
    return json.encode(player.PlayerData[srcKey] or (srcKey == 'inventory' and {} or {}))
end

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
local function samplePosition(player, logoutSample)
    if player._loggingOut and not logoutSample then return end
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

local function collectRows()
    local rows, n = {}, 0
    for cid in pairs(dirty) do
        local player = PI.byCitizenId[cid]
        if player then
            local cols, remaining = nil, {}
            for column in pairs(player._dirty) do
                -- Never persist license/cid (immutable; the two-unique-key
                -- corruption hazard). They are not in COLUMN_FOR, so a mutation
                -- can't mark them dirty -- this is a belt-and-braces skip.
                if Core.persistence._isColumnLocked and Core.persistence._isColumnLocked(cid, column) then
                    remaining[column] = true
                elseif column ~= 'license' and column ~= 'cid' then
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
            player._dirty = remaining
        end
    end
    for cid in pairs(dirty) do
        local player = PI.byCitizenId[cid]
        if not player or not next(player._dirty) then dirty[cid] = nil end
    end
    return rows
end

-- Flush all dirty players in one enqueueMany (one boundary crossing).
---@return integer players flushed
function Core.persistence.flushAll()
    for _, player in pairs(PI.bySource) do samplePosition(player) end
    local rows = collectRows()
    if #rows > 0 then
        -- The row already exists (from _load/_insertNew). A partial INSERT ... ON DUPLICATE KEY
        -- UPDATE is unsafe: MariaDB validates required immutable columns (license/cid) first.
        Kora.sql.enqueueMany('players', 'citizenid', rows, { mode = 'assign', writeMode = 'update' })
    end
    return #rows
end

-- Immediate save of one player (drop/logout path). Marks everything the player
-- has changed dirty (already tracked), samples position, then enqueues at
-- immediate priority so kora_sql flushes it out of band.
---@param player table
function Core.persistence.saveNow(player)
    samplePosition(player)
    local cols, remaining = nil, {}
    for column in pairs(player._dirty) do
        if Core.persistence._isColumnLocked and Core.persistence._isColumnLocked(player.citizenid, column) then
            remaining[column] = true
        elseif column ~= 'license' and column ~= 'cid' then
            local encoded = encodeColumn(player, column)
            if encoded ~= player._encoded[column] then
                cols = cols or {}
                cols[column] = encoded
                player._encoded[column] = encoded
            end
        end
    end
    player._dirty = remaining
    if not next(remaining) then dirty[player.citizenid] = nil end
    if cols then
        Kora.sql.enqueue('players', 'citizenid', { pk = player.citizenid, cols = cols }, {
            priority = 'immediate', mode = 'assign', writeMode = 'update',
        })
    end
end

-- Logout keeps its live handle until the asynchronous SQL queue confirms the
-- final write. Ped sampling must not replace a validated housing exterior.
function Core.persistence._saveForLogout(player, positionOverride)
    local called, saved, err = pcall(function()
        if not positionOverride then samplePosition(player, true) end
        -- The normal baseline records enqueue, not commit. An earlier queued
        -- save may already have exhausted retries, so logout must publish a
        -- fresh complete mutable snapshot before asking for acknowledgement.
        for _, column in pairs(COLUMN_FOR) do
            player._encoded[column] = nil
            Core.persistence._markDirty(player, column)
        end
        Core.persistence.saveNow(player)
        return Kora.sql.flush('players')
    end)
    if called and saved == true then return true end
    -- saveNow advances its enqueue baseline before SQL finishes. A rejected or
    -- thrown flush must leave every mutable column retryable, even if the SQL
    -- queue discarded a failed row; immutable account keys remain excluded.
    for _, column in pairs(COLUMN_FOR) do
        player._encoded[column] = nil
        Core.persistence._markDirty(player, column)
    end
    return false, tostring(err or saved or 'player save failed')
end

-- genuine (license,cid) or citizenid collision raises rather than silently
-- overwriting a different row. Yields.
---@return boolean, string|nil
function Core.persistence._insertNew(citizenid, license, cid, data)
    local ok, err = Kora.sql.execute(
        'INSERT INTO `players` (`citizenid`,`license`,`cid`,`name`,`money`,`charinfo`,`job`,`gang`,`position`,`metadata`,`inventory`,`phone_number`) '
        .. 'VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
        {
            citizenid, license, cid, data.name,
            json.encode(data.money), json.encode(data.charinfo),
            json.encode(data.job), json.encode(data.gang),
            json.encode(data.position), json.encode(data.metadata),
            json.encode(data.items or {}), data.phone or Kora.sql.NULL,
        }
    )
    if ok == nil and err then return false, err end
    return true
end

---@param citizenid string
---@return table|nil, string|nil
function Core.persistence._load(citizenid)
    if Core.persistence._hasColumnOperation and Core.persistence._hasColumnOperation(citizenid) then return nil, 'player data is busy' end
    if Core.persistence._persistentColumnsAvailable then
        local available, err = Core.persistence._persistentColumnsAvailable(citizenid)
        if not available then return nil, err end
    end
    local epoch = Core.persistence._columnEpoch and Core.persistence._columnEpoch(citizenid)
    local row, err = Kora.sql.single('SELECT * FROM `players` WHERE `citizenid` = ? AND `deleted_at` IS NULL', { citizenid })
    if epoch and (Core.persistence._hasColumnOperation(citizenid) or epoch ~= Core.persistence._columnEpoch(citizenid)) then return nil, 'player data changed while loading' end
    if not row then return nil, err or 'not found' end
    local function dec(s, fallback) local ok, v = pcall(json.decode, s or ''); return ok and v or fallback end
    local charinfo = dec(row.charinfo, {})

    -- PlayerData.items is a NUMERIC slot-keyed map, but a sparse map serialises to a JSON
    -- object and json.decode returns the keys as STRINGS. Re-key on load, preferring the
    -- slot recorded inside the item, or slot lookups miss after a relog.
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
    -- Rows written before buildJob added `job.type` lack it and the job blob is restored
    -- verbatim, so backfill from the registry. A job no longer registered falls back to 'none'.
    local function decodeJob(s)
        local job = dec(s, {})
        if type(job) ~= 'table' then return {} end
        if job.type == nil and job.name then
            local def = Core.registry.getShared('jobs', job.name)
            job.type = (def and def.type) or 'none'
        end
        return job
    end

    return {
        citizenid = row.citizenid,
        license = row.license,
        cid = row.cid,
        name = row.name,
        money = dec(row.money, {}),
        charinfo = charinfo,
        job = decodeJob(row.job),
        gang = dec(row.gang, {}),
        position = dec(row.position, { x = 0, y = 0, z = 70, h = 0 }),
        metadata = dec(row.metadata, {}),
        items = decodeItems(row.inventory),
        -- Legacy qb-core stored the phone only inside charinfo. Migration v6
        -- adds the scalar column without rewriting existing character rows,
        -- so retain their number until a later normal player update persists it.
        phone = row.phone_number or charinfo.phone,
    }
end

---Reads a character without creating a legacy Player object. Yields.
---@param citizenid string
---@return table|nil, string|nil
function Core.persistence.getOfflinePlayerData(citizenid)
    if type(citizenid) ~= 'string' or citizenid == '' then return nil, 'invalid citizenid' end
    return Core.persistence._load(citizenid)
end

---Writes only the requested mutable columns of an offline character. Yields.
---@param data table
---@param fields string[]
---@return boolean, string|nil
function Core.persistence.saveOfflinePlayer(data, fields)
    if type(data) ~= 'table' or type(data.citizenid) ~= 'string' then return false, 'invalid player data' end
    if type(fields) ~= 'table' or #fields == 0 then return false, 'fields are required' end
    if CoreInternal.player.byCitizenId[data.citizenid] then return false, 'player is online' end
    if Core.persistence._hasColumnOperation and Core.persistence._hasColumnOperation(data.citizenid) then return false, 'player data is busy' end
    if Core.persistence._persistentColumnsAvailable then
        local available, err = Core.persistence._persistentColumnsAvailable(data.citizenid)
        if not available then return false, err end
    end
    if CoreInternal.player.byCitizenId[data.citizenid] then return false, 'player is online' end
    local assignments, params = {}, {}
    for _, field in ipairs(fields) do
        local column = COLUMN_FOR[field]
        if not column then return false, 'invalid player field' end
        assignments[#assignments + 1] = '`' .. column .. '` = ?'
        params[#params + 1] = encodeColumn({ PlayerData = data }, column)
    end
    params[#params + 1] = data.citizenid
    if Core.persistence._beginOfflineWrite and not Core.persistence._beginOfflineWrite(data.citizenid) then return false, 'player data is busy' end
    local called, result, err = pcall(Kora.sql.update, 'UPDATE `players` SET ' .. table.concat(assignments, ', ')
        .. ' WHERE `citizenid` = ? AND `deleted_at` IS NULL', params)
    if Core.persistence._endOfflineWrite then Core.persistence._endOfflineWrite(data.citizenid) end
    if not called then return false, 'could not save offline player' end
    if result == nil then return false, err or 'could not save offline player' end
    if result == 0 then
        local row = Kora.sql.single('SELECT `citizenid` FROM `players` WHERE `citizenid` = ? AND `deleted_at` IS NULL', { data.citizenid })
        if not row then return false, 'player not found' end
    end
    return true
end

---@param license string
---@return table[]
function Core.persistence._listCharacters(license)
    return Kora.sql.query(
        'SELECT `citizenid`,`cid`,`name`,`charinfo`,`money`,`job`,`gang` FROM `players` WHERE `license` = ? AND `deleted_at` IS NULL ORDER BY `cid`',
        { license }
    ) or {}
end

---@param citizenid string
---@return boolean
function Core.persistence._deleteCharacterRow(citizenid)
    if PI.byCitizenId[citizenid] then return false, 'player is online' end
    if Core.persistence._hasColumnOperation and Core.persistence._hasColumnOperation(citizenid) then return false end
    if Core.persistence._persistentColumnsAvailable and not Core.persistence._persistentColumnsAvailable(citizenid) then return false end
    if PI.byCitizenId[citizenid] then return false, 'player is online' end
    if Core.persistence._beginOfflineWrite and not Core.persistence._beginOfflineWrite(citizenid) then return false end
    local called, r = pcall(Kora.sql.execute, 'UPDATE `players` SET `deleted_at` = NOW() WHERE `citizenid` = ?', { citizenid })
    if Core.persistence._endOfflineWrite then Core.persistence._endOfflineWrite(citizenid) end
    return called and r ~= nil
end

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
            -- Nudge kora_sql to drain promptly rather than waiting its own interval.
            Kora.sql.flush('players')
        end
    end
end)

-- txAdmin shutdown / scheduled restart: flush everyone immediately.
local function flushEveryoneNow()
    for _, player in pairs(PI.bySource) do Core.persistence.saveNow(player) end
    Kora.sql.flush('players')
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
    Kora.sql.flush('players')
end)
