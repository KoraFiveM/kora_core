-- compat/server/qbx.lua -- opt-in `qbx_core` / `qbx_vehicles` export facade.
--
-- Purpose: stock ox_inventory with `setr inventory:framework "qbx"` reaches its
-- framework only through exports.qbx_core / exports.qbx_vehicles, the qbx_core
-- server/client events, and two state bags. This file publishes exactly that
-- surface on top of kora_core, so the unmodified ox_inventory bridge runs here.
--
-- Rules (same as the rest of compat/):
--   * The export identities are published with the `__cfx_export_` hijack
--     (Kora.compat.provideExport). There is NO resource named qbx_core and no
--     `provide 'qbx_core'`: a fake qbx_core would flip third-party framework
--     autodetection (`GetResourceState('qbx_core')`) onto qbx code paths.
--   * Everything calls Core.* / QBCore.Functions.* DIRECTLY, never
--     exports.kora_core:fn(), so GetInvokingResource() stays the real consumer.
--   * OFF by default. When disabled this file registers nothing at all (no
--     handlers, no exports), so behaviour is byte-for-byte unchanged.
--
-- Enable with `setr kora:qbxFacade true` (or Config.compat.qbxFacade = true).
-- Explicit opt-in rather than auto-detecting `inventory:framework == 'qbx'`:
-- that convar is replicated and may be set after kora_core starts, ox_inventory
-- may not exist yet, and a server running a REAL qbx_core must never have its
-- exports hijacked by a convar it set for ox_inventory. For the same reason the
-- facade refuses to start while a resource named qbx_core exists.

local PI = CoreInternal.player

local enabled = Config.compat.qbxFacade == true or GetConvar('kora:qbxFacade', 'false') == 'true'
if not enabled then return end

if GetResourceState('qbx_core') ~= 'missing' or GetResourceState('qbx_vehicles') ~= 'missing' then
    print('^1[qbcore:qbx-facade]^7 a real qbx_core/qbx_vehicles resource exists; the qbx facade stays OFF so it cannot hijack its exports.')
    return
end

local provideExport = Kora.compat.provideExport
local isCallable = Kora.util.isCallable

-- src -> { groups = {name -> qbx grade}|nil (nil until the session is ready) }
-- Doubles as the "facade has seen this character load" marker, so unload fires
-- the qbx logout event at most once per loaded session.
local sessions = {}

local READY_RETRY_MS, READY_MAX_ATTEMPTS = 50, 40

-- --- groups -------------------------------------------------------------------

-- qbx groups are `{ [name] = grade }` with qbx's ZERO-based grades, the same
-- numbering ox_inventory's shop/stash `groups` data is written against. kora's
-- internal grades are one-based, hence toLegacyGradeLevel.
-- Only the ACTIVE job counts: kora_multijob's inactive roster entries are not
-- groups (an off-roster police grade must not open a police stash).
local function computeGroups(src)
    local handle = PI.handle(src)
    if not handle then return nil end
    local groups = {}
    local job, gang = handle.PlayerData.job, handle.PlayerData.gang
    if job and job.name then
        groups[job.name] = Core.compat.toLegacyGradeLevel(job.grade and job.grade.level)
    end
    if gang and gang.name and gang.name ~= 'none' then
        groups[gang.name] = Core.compat.toLegacyGradeLevel(gang.grade and gang.grade.level)
    end
    return groups
end

local function copyMap(map)
    local out = {}
    for k, v in pairs(map) do out[k] = v end
    return out
end

local function emitGroupUpdate(src, name, grade)
    TriggerEvent('qbx_core:server:onGroupUpdate', src, name, grade)
    TriggerClientEvent('qbx_core:client:onGroupUpdate', src, name, grade)
end

-- Diff-based, so the several QBCore events one change can produce (OnJobUpdate,
-- plus OnPlayerUpdated('all') re-fans) re-emit qbx's event exactly once.
local function onRoleUpdate(src)
    local session = sessions[src]
    if not session or not session.groups then return end
    local now = computeGroups(src)
    if not now then return end
    local before = session.groups
    session.groups = now
    for name in pairs(before) do
        if now[name] == nil then emitGroupUpdate(src, name, nil) end
    end
    for name, grade in pairs(now) do
        if before[name] ~= grade then emitGroupUpdate(src, name, grade) end
    end
end

AddEventHandler('QBCore:Server:OnJobUpdate', onRoleUpdate)
AddEventHandler('QBCore:Server:OnGangUpdate', onRoleUpdate)

-- --- lifecycle + state bags -----------------------------------------------------

-- loadInventory is the trigger ox_inventory's bridge watches to build the
-- player's inventory, and its handler reads GetPlayer(src).PlayerData at once.
-- Set it only after Core.player.login has finished (isLoggedIn true, snapshot
-- sent): the playerLoaded event fires earlier, mid-adoption.
local function armReady(src, session, attempt)
    SetTimeout(attempt == 0 and 0 or READY_RETRY_MS, function()
        if sessions[src] ~= session then return end
        local bag = Player(src)
        local state = bag and bag.state
        if not (state and state.isLoggedIn == true) then
            if attempt < READY_MAX_ATTEMPTS then return armReady(src, session, attempt + 1) end
            print(('^3[qbcore:qbx-facade]^7 player %s never reached isLoggedIn; loadInventory not set'):format(tostring(src)))
            return
        end
        session.groups = computeGroups(src) or {}
        TriggerClientEvent('qbx_core:client:setGroups', src, copyMap(session.groups))
        state:set('loadInventory', true, true)
    end)
end

AddEventHandler('qbcore:server:playerLoaded', function(src)
    local handle = PI.handle(src)
    if not handle then return end
    -- ox_inventory indexes metadata.licences[...] unguarded; characters
    -- imported from older QB data may lack it. One-time {} write, only if absent.
    local metadata = handle.PlayerData.metadata
    if type(metadata) == 'table' and type(metadata.licences) ~= 'table' then
        Core.player.setPath(src, { 'metadata', 'licences' }, {})
    end
    local session = {}
    sessions[src] = session
    armReady(src, session, 0)
end)

-- QBCore:Server:OnPlayerUnload fires from BOTH logout and drop, once per
-- session (see Core.player.logout / dropPlayer); the sessions marker also makes
-- a stray manual trigger harmless.
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    local session = sessions[src]
    if not session then return end
    sessions[src] = nil
    -- isLoggedIn=false is already cleared by Core.player.logout. loadInventory is
    -- ours; Player(src) is nil once the connection is gone.
    local bag = Player(src)
    if bag and bag.state then bag.state:set('loadInventory', false, true) end
    TriggerEvent('qbx_core:server:playerLoggedOut', src)
end)

-- --- qbx_core exports -----------------------------------------------------------

-- Receiver-agnostic call: accepts player.Fn(args) and player:Fn(args), including
-- a msgpack copy of the player coming back across the export boundary.
local function receiverAware(fn)
    return function(first, ...)
        if type(first) == 'table' and type(first.PlayerData) == 'table' and first.Functions then
            return fn(...)
        end
        return fn(first, ...)
    end
end

-- A QB-shaped player whose PlayerData is the live legacy view, with two
-- ox_inventory-driven deviations from the plain QBCore player:
--   * SetPlayerData('items', t) only updates the in-memory mirror. In this
--     setup ox_inventory owns persistence of `players.inventory`; the funnel
--     write would mark that column dirty and kora would overwrite ox's blob,
--     and replicate every item delta to the client on every inventory change.
--   * SetMoney is idempotent: ox calls it whenever its `money` item and the
--     account differ; an equal balance is a no-op (no write, no OnMoneyChange),
--     which is also what keeps item<->account from ping-ponging.
local function getPlayer(src)
    src = tonumber(src)
    if not src then return nil end
    local orig = QBCore.Functions.GetPlayer(src)
    if not orig then return nil end

    local F = copyMap(orig.Functions)

    function F.SetPlayerData(key, value)
        if key == 'items' then
            local handle = PI.handle(src)
            if not handle then return false, 'no such player' end
            handle.PlayerData.items = value
            if Core.compat.onPlayerDataChanged then Core.compat.onPlayerDataChanged(src, { 'items' }, value) end
            return true
        end
        return orig.Functions.SetPlayerData(key, value)
    end

    function F.SetMoney(account, amount, reason)
        local wanted = tonumber(amount)
        if wanted and Core.money.getMoney(src, account) == wanted then return true end
        return orig.Functions.SetMoney(account, amount, reason)
    end

    local player = copyMap(orig)
    player.Functions = F
    for name, fn in pairs(F) do player[name] = receiverAware(fn) end
    return player
end

local function getPlayersData()
    local sources = {}
    for src in pairs(PI.bySource) do sources[#sources + 1] = src end
    table.sort(sources)
    local out = {}
    for _, src in ipairs(sources) do
        local player = QBCore.Functions.GetPlayer(src)
        if player then out[#out + 1] = Core.util.deepClone(player.PlayerData) end
    end
    return out
end

local function canUseItem(name)
    local record = Core.inventory.getUseable(name)
    local func = record and record.func
    if not isCallable(func) then return nil end
    return function(source, data) return func(source, data) end
end

local function getGroups(src)
    return computeGroups(tonumber(src))
end

-- `grade` is qbx's zero-based grade, like GetGroups.
local function isGradeBoss(group, grade)
    grade = tonumber(grade)
    if type(group) ~= 'string' or not grade then return false end
    local definition = Core.registry.getShared('jobs', group) or Core.registry.getShared('gangs', group)
    local entry = definition and definition.grades and definition.grades[math.floor(grade) + 1]
    return entry ~= nil and entry.isboss == true
end

provideExport('qbx_core', 'GetPlayer', getPlayer)
provideExport('qbx_core', 'GetPlayersData', getPlayersData)
provideExport('qbx_core', 'CanUseItem', canUseItem)
provideExport('qbx_core', 'GetGroups', getGroups)
provideExport('qbx_core', 'IsGradeBoss', isGradeBoss)

-- --- qbx_vehicles ---------------------------------------------------------------

-- ox_inventory keys trunk/glovebox on the returned id. kora's vehicle table is
-- `player_vehicles` (sql/005_vehicles.sql): integer `id`, UNIQUE `plate`,
-- soft-deleted via `deleted_at`. GetVehicleNumberPlateText pads plates with
-- spaces, so match the trimmed form too (the garage module stores them trimmed
-- and upper-cased); the column collation is case-insensitive.
local function getVehicleIdByPlate(plate)
    if type(plate) ~= 'string' then return nil end
    local trimmed = (plate:gsub('^%s+', ''):gsub('%s+$', ''))
    if trimmed == '' then return nil end
    local row = Kora.sql.single(
        'SELECT `id` FROM `player_vehicles` WHERE `plate` IN (?, ?) AND `deleted_at` IS NULL LIMIT 1',
        { plate, trimmed:upper() })
    return row and row.id or nil
end

provideExport('qbx_vehicles', 'GetVehicleIdByPlate', getVehicleIdByPlate)
