-- compat/server/qb-multicharacter.lua -- full data-side compat for the real
-- qb-multicharacter resource (github.com/qbcore-framework/qb-multicharacter).
-- We do NOT `provide 'qb-multicharacter'` here (see fxmanifest.lua): hijacking
-- the name would silently disable a real character-select UI a server wants
-- to keep. The UI resource that DOES fully replace it (qb-multichar, merged
-- with qb-spawn) claims the name itself. This file just routes the legacy
-- wire protocol to Core.*, exactly as compat/server/qb-core.lua does for the
-- QBCore object.

QB.callback.register('qb-multicharacter:server:GetUserCharacters', function(src)
    -- Real signature: raw (undecoded) player rows by license -- distinct from
    -- setupCharacters below, which returns decoded summaries.
    local license = Core.identity.primary(src)
    if not license then return {} end
    return QB.sql.query('SELECT * FROM `players` WHERE `license` = ? AND `deleted_at` IS NULL', { license }) or {}
end)

-- GetServerLogs: deliberately NOT implemented -- no `server_logs` table
-- anywhere in this schema, nothing to honestly return.

QB.callback.register('qb-multicharacter:server:GetNumberOfCharacters', function(_src)
    -- Real signature: cb(numOfChars, Countries). Per-license overrides and a
    -- static Countries list aren't modeled in this codebase -- fall back to
    -- the single global cap and an empty list rather than guessing at data
    -- that doesn't exist here.
    return Config.identity.maxCharacters, {}
end)

QB.callback.register('qb-multicharacter:server:setupCharacters', function(src)
    -- Real qb-multicharacter uses this purely as a request/response callback
    -- (QBCore.Functions.CreateCallback), not a fire-and-forget event pair.
    return Core.multichar.getCharacters(src)
end)

QB.callback.register('qb-multicharacter:server:getSkin', function(_src, _citizenid)
    -- Real signature: cb(model, skin) from a `playerskins` table. No
    -- appearance/clothing module exists in this codebase -- honestly return
    -- nothing rather than guessing at a skin.
    return nil
end)

RegisterNetEvent('qb-multicharacter:server:disconnect', function(reason)
    -- Raw native, not Core.player.dropPlayer: that function is post-disconnect
    -- cleanup bookkeeping (evicts an already-adopted player from the caches)
    -- and would no-op here -- at this point (still on the char-select screen)
    -- the player has no active character session for it to find.
    DropPlayer(source, reason or 'Disconnected.')
end)

RegisterNetEvent('qb-multicharacter:server:loadUserData', function(cData)
    local src = source
    -- Real shape: cData is a TABLE with a .citizenid field, not a bare
    -- citizenid string.
    if type(cData) ~= 'table' or not cData.citizenid then return end

    local ok, err = Core.multichar.selectCharacter(src, cData.citizenid)
    if not ok then
        TriggerClientEvent('multichar:client:selectFailed', src, err)
        return
    end

    -- Real qb-multicharacter attaches the character's last position onto
    -- cData before handing off to qb-spawn.
    cData.position = Core.player.getPlayerData(src, { 'position' })

    -- Real branch checks GetResourceState('qb-apartments') and routes to
    -- apartments:client:setupSpawnUI instead -- no apartments module exists
    -- in this codebase, so that branch never fires here; left as a comment
    -- rather than dead code, forward-compatible if one is ever installed.
    TriggerClientEvent('qb-spawn:client:setupSpawns', src, cData, false, nil)
    TriggerClientEvent('qb-spawn:client:openUI', src, true)
end)

RegisterNetEvent('qb-multicharacter:server:createCharacter', function(data)
    local src = source
    data = data or {}
    local citizenid, err = Core.player.createCharacter(src, data, data.cid)
    if not citizenid then
        TriggerClientEvent('multichar:client:selectFailed', src, err)
        return
    end

    -- Real qb-multicharacter skips the spawn picker entirely for a
    -- brand-new character (goes straight to Config.defaultSpawn).
    TriggerClientEvent('qb-multicharacter:client:closeNUIdefault', src)
end)

RegisterNetEvent('qb-multicharacter:server:deleteCharacter', function(citizenid)
    Core.multichar.deleteCharacter(source, citizenid)
end)
