-- Core.identity -- identifier extraction and citizenid generation. Server only.
-- The primary identifier (Config.identity.primaryIdentifier, default 'license')
-- keys a player across characters; a citizenid keys a single character.

local RI_PREFIX = Config.identity.citizenIdPrefix or ''

-- Extract all of a player's identifiers into a flat table. FiveM exposes them
-- as 'license:xxxx', 'discord:123', etc. via GetPlayerIdentifiers.
---@param src integer
---@return table<string,string>
function Core.identity.getIdentifiers(src)
    local out = {}
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        if id then
            local kind, value = id:match('^(%w+):(.+)$')
            if kind then
                -- 'license' and 'license2' are distinct; keep the first of each.
                out[kind] = out[kind] or value
            end
        end
    end
    -- Endpoint / IP is not an identifier entry; fetch it separately.
    out.ip = out.ip or GetPlayerEndpoint(src)
    return out
end

---The primary identifier value for a source (nil if not connected).
---@param src integer
---@return string|nil
function Core.identity.primary(src)
    local ids = Core.identity.getIdentifiers(src)
    return ids[Config.identity.primaryIdentifier]
end

-- Generate a candidate citizenid. Uniqueness is enforced by the DB UNIQUE index;
-- this is a retry loop the persistence layer uses on an insert collision, not a
-- guarantee on its own.
---@return string
function Core.identity.generateCitizenId()
    return RI_PREFIX .. Core.util.randomAlnum(Config.identity.citizenIdLength)
end

-- Record a character's identifiers into player_identifiers (fire-and-forget
-- upsert through the coalescing queue -- one row per (citizenid, kind)).
---@param citizenid string
---@param ids table<string,string>
function Core.identity.recordIdentifiers(citizenid, ids)
    local rows = {}
    for kind, value in pairs(ids) do
        if value then
            rows[#rows + 1] = {
                pk = { citizenid, kind },
                cols = { value = tostring(value) },
            }
        end
    end
    if #rows > 0 then
        Kora.sql.enqueueMany('player_identifiers', { 'citizenid', 'kind' }, rows, { mode = 'assign' })
    end
end

-- Look up citizenids that have ever used a given identifier (for ban/alt
-- detection). Yields.
---@param kind string
---@param value string
---@return string[]
function Core.identity.findByIdentifier(kind, value)
    local rows = Kora.sql.query(
        'SELECT `citizenid` FROM `player_identifiers` WHERE `kind` = ? AND `value` = ?',
        { kind, value }
    ) or {}
    local out = {}
    for i = 1, #rows do out[i] = rows[i].citizenid end
    return out
end
