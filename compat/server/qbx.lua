local PI = CoreInternal.player

local enabled = Config.compat.qbxFacade == true or GetConvar('kora:qbxFacade', 'false') == 'true'
if not enabled then return end

if GetResourceState('qbx_core') ~= 'missing' or GetResourceState('qbx_vehicles') ~= 'missing' then
    print('^1[qbcore:qbx-facade]^7 a real qbx_core/qbx_vehicles resource exists; the qbx facade stays OFF so it cannot hijack its exports.')
    return
end

local provideExport = Kora.compat.provideExport
local isCallable = Kora.util.isCallable

local sessions = {}

local READY_RETRY_MS, READY_MAX_ATTEMPTS = 50, 40

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
    local metadata = handle.PlayerData.metadata
    if type(metadata) == 'table' and type(metadata.licences) ~= 'table' then
        Core.player.setPath(src, { 'metadata', 'licences' }, {})
    end
    local session = {}
    sessions[src] = session
    armReady(src, session, 0)
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    local session = sessions[src]
    if not session then return end
    sessions[src] = nil
    local bag = Player(src)
    if bag and bag.state then bag.state:set('loadInventory', false, true) end
    TriggerEvent('qbx_core:server:playerLoggedOut', src)
end)

local function receiverAware(fn)
    return function(first, ...)
        if type(first) == 'table' and type(first.PlayerData) == 'table' and first.Functions then
            return fn(...)
        end
        return fn(first, ...)
    end
end

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
