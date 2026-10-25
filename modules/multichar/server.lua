-- Core.multichar (server realm) -- the character-select lifecycle. No NUI is
-- shipped; a character-select UI resource (or the qb-multicharacter compat
-- events) drives this via net events / exports. On a bare server the client
-- module auto-selects slot 1 so a player still spawns.

local PI = CoreInternal.player

---List a source's characters (by their primary identifier). Yields.
---@param src integer
---@return table[]  -- decoded summaries {citizenid, cid, name, charinfo, money, job, gang}
function Core.multichar.getCharacters(src)
    local license = Core.identity.primary(src)
    if not license then return {} end
    local rows = Core.persistence._listCharacters(license)
    local function dec(s) local ok, v = pcall(json.decode, s or ''); return ok and v or {} end
    for _, row in ipairs(rows) do
        row.charinfo = dec(row.charinfo)
        row.money = dec(row.money)
        row.job = dec(row.job)
        row.gang = dec(row.gang)
    end
    return rows
end

---Whether a citizen belongs to the source's primary identifier. Yields.
---Kept as a dedicated public check for pre-login integrations such as a
---character selector fetching saved appearance without adopting the player.
---@param src integer
---@param citizenid string
---@return boolean
function Core.multichar.ownsCharacter(src, citizenid)
    if type(citizenid) ~= 'string' or citizenid == '' then return false end
    local license = Core.identity.primary(src)
    if not license then return false end
    local data = Core.persistence._load(citizenid)
    return data ~= nil and data.license == license
end

---Select (load + log in) an existing character. Yields. Returns (true) or (nil, err).
---@param src integer
---@param citizenid string
---@return boolean, string|nil
function Core.multichar.selectCharacter(src, citizenid)
    -- Verify ownership: the citizenid must belong to this source's identifier.
    local license = Core.identity.primary(src)
    local data, err = Core.persistence._load(citizenid)
    if not data then return false, err end
    if data.license ~= license then return false, 'character does not belong to this player' end
    return Core.player.login(src, citizenid, data)
end

---Create a new character in a slot. Yields. Returns (citizenid) or (nil, err).
---@param src integer
---@param charinfo table
---@param cid integer|nil
---@return string|nil, string|nil
-- (multichar.createCharacter removed: use Core.player.createCharacter, the
-- single public creator, to avoid a flat-export name collision.)

---Delete a character (soft-delete). Yields.
---@param src integer
---@param citizenid string
---@return boolean, string|nil
function Core.multichar.deleteCharacter(src, citizenid)
    local license = Core.identity.primary(src)
    local data = Core.persistence._load(citizenid)
    if not data then return false, 'character not found' end
    if Core.identity.primary(src) ~= license then return false, 'player session changed' end
    if data and data.license ~= license then return false, 'not your character' end
    -- If they're currently on this character, log them out first.
    local player = PI.byCitizenId[citizenid]
    if player then
        local loggedOut, err = Core.player.logout(player.source)
        if not loggedOut then return false, err or 'character logout failed' end
    end
    return Core.persistence._deleteCharacterRow(citizenid)
end

-- Net-event surface for a character-select UI.
RegisterNetEvent('qbcore:server:requestCharacters', function()
    local src = source
    TriggerClientEvent('qbcore:client:receiveCharacters', src, Core.multichar.getCharacters(src))
end)

RegisterNetEvent('qbcore:server:selectCharacter', function(citizenid)
    local src = source
    local ok, err = Core.multichar.selectCharacter(src, citizenid)
    TriggerClientEvent('qbcore:client:characterSelected', src, ok, err)
end)

RegisterNetEvent('qbcore:server:createCharacter', function(charinfo, cid)
    local src = source
    local citizenid, err = Core.player.createCharacter(src, charinfo, cid)
    if citizenid then
        TriggerClientEvent('qbcore:client:characterSelected', src, true)
    else
        TriggerClientEvent('qbcore:client:characterSelected', src, false, err)
    end
end)

RegisterNetEvent('qbcore:server:deleteCharacter', function(citizenid)
    local src = source
    Core.multichar.deleteCharacter(src, citizenid)
    TriggerClientEvent('qbcore:client:receiveCharacters', src, Core.multichar.getCharacters(src))
end)
