QBCore = QBCore or {}
QBCore.Functions = QBCore.Functions or {}
QBCore.Player = QBCore.Player or {}
QBCore.Players = QBCore.Players or {}
QBCore.PlayersByCitizenId = QBCore.PlayersByCitizenId or {}
QBCore.Shared = QBCore.Shared or {}
QBCore.ClientCallbacks = QBCore.ClientCallbacks or {}
QBCore.ServerCallbacks = QBCore.ServerCallbacks or {}
QBCore.Commands = QBCore.Commands or {}
QBCore.Config = QBCore.Config or {}
QBCore.PlayerData = QBCore.PlayerData or {}

QBCore.Shared.Round     = function(v, p) return Core.util.round(v, p) end
QBCore.Shared.Trim      = function(v) return Core.util.trim(v) end
QBCore.Shared.SplitStr  = function(s, d) return Core.util.splitStr(s, d) end
QBCore.Shared.RandomStr = function(n) return Core.util.randomStr(n) end
QBCore.Shared.RandomInt = function(n) return Core.util.randomInt(n) end

---Capitalizes the first letter of a string (real qb-core shared/functions.lua).
---@param value string
function QBCore.Shared.FirstToUpper(value)
    if not value then return nil end
    return (value:gsub('^%l', string.upper))
end

function QBCore.Shared.IsFunction(value)
    if type(value) == 'function' then return true end
    if type(value) == 'table' then
        if type(rawget(value, '__cfx_functionReference')) == 'string' then return true end
        local mt = getmetatable(value)
        return mt ~= nil and type(mt.__call) == 'function'
    end
    return false
end

QBCore.Shared.StarterItems = {
    phone = { amount = 1, item = 'phone' },
    id_card = { amount = 1, item = 'id_card' },
    driver_license = { amount = 1, item = 'driver_license' },
}

QBCore.Shared.MaleNoGloves = {
    [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true,
    [6] = true, [7] = true, [8] = true, [9] = true, [10] = true, [11] = true,
    [12] = true, [13] = true, [14] = true, [15] = true, [18] = true, [26] = true,
    [52] = true, [53] = true, [54] = true, [55] = true, [56] = true, [57] = true,
    [58] = true, [59] = true, [60] = true, [61] = true, [62] = true, [112] = true,
    [113] = true, [114] = true, [118] = true, [125] = true, [132] = true,
}

QBCore.Shared.FemaleNoGloves = {
    [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true,
    [6] = true, [7] = true, [8] = true, [9] = true, [10] = true, [11] = true,
    [12] = true, [13] = true, [14] = true, [15] = true, [19] = true, [59] = true,
    [60] = true, [61] = true, [62] = true, [63] = true, [64] = true, [65] = true,
    [66] = true, [67] = true, [68] = true, [69] = true, [70] = true, [71] = true,
    [129] = true, [130] = true, [131] = true, [135] = true, [142] = true,
    [149] = true, [153] = true, [157] = true, [161] = true, [165] = true,
}

QBCore.Shared.ForceJobDefaultDutyAtLogin = true

if not IsDuplicityVersion() then
    ---Toggle a single vehicle extra on/off, verifying the change took (a vehicle
    ---extra can silently refuse to toggle e.g. mid-animation) and retrying once.
    ---@param vehicle number
    ---@param extra number
    ---@param enable boolean
    function QBCore.Shared.ChangeVehicleExtra(vehicle, extra, enable)
        if DoesExtraExist(vehicle, extra) then
            if enable then
                SetVehicleExtra(vehicle, extra, false)
                if not IsVehicleExtraTurnedOn(vehicle, extra) then
                    QBCore.Shared.ChangeVehicleExtra(vehicle, extra, enable)
                end
            else
                SetVehicleExtra(vehicle, extra, true)
                if IsVehicleExtraTurnedOn(vehicle, extra) then
                    QBCore.Shared.ChangeVehicleExtra(vehicle, extra, enable)
                end
            end
        end
    end

    ---Turn every extra off, then apply the given config's on/off overrides.
    ---@param vehicle number
    ---@param config table<string|number, boolean>
    function QBCore.Shared.SetDefaultVehicleExtras(vehicle, config)
        for i = 1, 20 do
            if DoesExtraExist(vehicle, i) then
                SetVehicleExtra(vehicle, i, true)
            end
        end

        for id, enabled in pairs(config) do
            if type(enabled) ~= 'boolean' then enabled = true end
            QBCore.Shared.ChangeVehicleExtra(vehicle, tonumber(id), enabled)
        end
    end
end

local function toLegacyGrades(gradesArray)
    local legacy = {}
    if gradesArray then
        for i = 1, #gradesArray do
            legacy[tostring(i - 1)] = gradesArray[i]
        end
    end
    return legacy
end

local function toLegacyRecord(record)
    local view = {}
    for k, v in pairs(record) do view[k] = v end
    view.grades = toLegacyGrades(record.grades)
    return view
end

local function buildLegacyView(regName, transform)
    local view = {}

    local function refresh()
        for k in pairs(view) do view[k] = nil end
        for _, record in ipairs(Core.registry.allShared(regName)) do
            local keyField = CoreInternal.registry.registries[regName].keyField
            view[record[keyField]] = transform and transform(record) or record
        end
    end

    refresh()
    if Core.registry.onSharedChange then
        Core.registry.onSharedChange(regName, refresh)
    end
    AddEventHandler('qbcore:registry:synced', refresh)

    return view
end

local function buildLegacyGradeView(regName)
    return buildLegacyView(regName, toLegacyRecord)
end

local function buildVehicleHashesView()
    local view = {}

    local function refresh()
        for k in pairs(view) do view[k] = nil end
        for _, record in ipairs(Core.registry.allShared('vehicles')) do
            view[joaat(record.model)] = record
        end
    end

    refresh()
    if Core.registry.onSharedChange then
        Core.registry.onSharedChange('vehicles', refresh)
    end
    AddEventHandler('qbcore:registry:synced', refresh)

    return view
end

local function buildLegacyItemsView()
    local view = {}
    local function refresh()
        for key in pairs(view) do view[key] = nil end
        for _, registry in ipairs({ 'weapons', 'items' }) do
            for _, record in ipairs(Core.registry.allShared(registry)) do
                view[record.name] = record
            end
        end
    end
    refresh()
    if Core.registry.onSharedChange then
        Core.registry.onSharedChange('items', refresh)
        Core.registry.onSharedChange('weapons', refresh)
    end
    AddEventHandler('qbcore:registry:synced', refresh)
    return view
end

local function buildLegacyWeaponsView()
    local view = {}
    local metadata = QBCoreSeed.legacyWeaponMetadata or {}
    local function refresh()
        for key in pairs(view) do view[key] = nil end
        for name, record in pairs(metadata) do
            local copy = {}
            for key, value in pairs(record) do copy[key] = value end
            view[joaat(name)] = copy
        end
        for _, record in ipairs(Core.registry.allShared('weapons')) do
            local copy = {}
            for key, value in pairs(metadata[record.name] or {}) do copy[key] = value end
            for key, value in pairs(record) do copy[key] = value end
            copy.damagereason = copy.damagereason or 'Died'
            view[joaat(record.name)] = copy
        end
    end
    refresh()
    if Core.registry.onSharedChange then
        Core.registry.onSharedChange('weapons', refresh)
    end
    AddEventHandler('qbcore:registry:synced', refresh)
    return view
end

setmetatable(QBCore.Shared, getmetatable(QBCore.Shared) or {
    __index = function(t, k)
        local legacyGradeRegistries = { Jobs = 'jobs', Gangs = 'gangs' }
        local gradeRegName = legacyGradeRegistries[k]
        if gradeRegName and CoreInternal and CoreInternal.registry and CoreInternal.registry.registries[gradeRegName] then
            local view = buildLegacyGradeView(gradeRegName)
            rawset(t, k, view)
            return view
        end

        if k == 'VehicleHashes' and CoreInternal and CoreInternal.registry and CoreInternal.registry.registries.vehicles then
            local view = buildVehicleHashesView()
            rawset(t, k, view)
            return view
        end

        if (k == 'Items' or k == 'Weapons') and CoreInternal and CoreInternal.registry
            and CoreInternal.registry.registries.items and CoreInternal.registry.registries.weapons then
            local view = k == 'Items' and buildLegacyItemsView() or buildLegacyWeaponsView()
            rawset(t, k, view)
            return view
        end

        local map = { Vehicles = 'vehicles', Locations = 'locations' }
        local regName = map[k]
        if regName and CoreInternal and CoreInternal.registry and CoreInternal.registry.registries[regName] then
            local view = buildLegacyView(regName)
            rawset(t, k, view)
            return view
        end
        return nil
    end,
})

local function toLegacyGradeLevel(level)
    return math.max((tonumber(level) or 1) - 1, 0)
end

local function fromLegacyGradeLevel(level)
    return math.max(math.floor(tonumber(level) or 0), 0) + 1
end

local function gradeDefinition(kind, record)
    local def = Core.registry and Core.registry.getShared and Core.registry.getShared(kind, record.name)
    local index = type(record.grade) == 'table' and tonumber(record.grade.level) or nil
    return def and def.grades and index and (def.grades[index] or def.grades[1]) or nil
end

local function toLegacyJobOrGang(record, kind)
    if type(record) ~= 'table' then return record end
    local view = {}
    for k, v in pairs(record) do view[k] = v end
    if type(record.grade) == 'table' then
        local grade = {}
        for k, v in pairs(record.grade) do grade[k] = v end
        grade.level = toLegacyGradeLevel(record.grade.level)
        if grade.isboss == nil or (kind == 'jobs' and grade.payment == nil) then
            local def = (record.isboss == nil or (kind == 'jobs' and record.payment == nil))
                and kind and gradeDefinition(kind, record) or nil
            if grade.isboss == nil then
                if record.isboss ~= nil then grade.isboss = record.isboss and true or false
                else grade.isboss = def and def.isboss or false end
            end
            if kind == 'jobs' and grade.payment == nil then
                if record.payment ~= nil then grade.payment = record.payment
                else grade.payment = def and def.payment or 0 end
            end
        end
        view.grade = grade
    end
    return view
end

local function citizenHash(citizenid, salt)
    local hash = 7
    local text = tostring(citizenid or '') .. ':' .. salt
    for i = 1, #text do hash = (hash * 31 + text:byte(i)) % 2147483629 end
    return hash
end

local function derivedStream(citizenid, salt)
    local state = citizenHash(citizenid, salt)
    return function(maximum)
        state = (state * 48271) % 2147483647
        return state % maximum
    end
end

local LETTERS = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'

local function derivedDigits(next, length)
    local out = {}
    for i = 1, length do out[i] = tostring(next(10)) end
    return table.concat(out)
end

local function derivedLetters(next, length)
    local out = {}
    for i = 1, length do local at = next(#LETTERS) + 1; out[i] = LETTERS:sub(at, at) end
    return table.concat(out)
end

local DERIVED = {
    SerialNumber = function(citizenid) return derivedDigits(derivedStream(citizenid, 'serial'), 9) end,
    bloodtype = function(citizenid)
        local types = QBCore.Config.Player and QBCore.Config.Player.Bloodtypes or { 'O+' }
        return types[derivedStream(citizenid, 'blood')(#types) + 1]
    end,
    fingerprint = function(citizenid)
        local next = derivedStream(citizenid, 'finger')
        return derivedLetters(next, 2) .. derivedDigits(next, 3) .. derivedLetters(next, 1)
            .. derivedDigits(next, 2) .. derivedLetters(next, 3) .. derivedDigits(next, 4)
    end,
    walletid = function(citizenid) return 'QB-' .. derivedDigits(derivedStream(citizenid, 'wallet'), 8) end,
    account = function(citizenid)
        local next = derivedStream(citizenid, 'account')
        return 'US0' .. (next(9) + 1) .. 'QBCore' .. derivedDigits(next, 8) .. derivedDigits(next, 2)
    end,
    phone = function(citizenid)
        local next = derivedStream(citizenid, 'phone')
        return tostring(100 + next(900)) .. derivedDigits(next, 7)
    end,
}

local function fillTable(target, defaults, citizenid)
    for key, default in pairs(defaults) do
        if type(default) == 'function' then
            if DERIVED[key] and target[key] == nil then target[key] = DERIVED[key](citizenid) end
        elseif target[key] == nil then
            target[key] = type(default) == 'table' and fillTable({}, default, citizenid) or default
        elseif type(default) == 'table' and type(target[key]) == 'table' then
            local copy = {}
            for k, v in pairs(target[key]) do copy[k] = v end
            target[key] = fillTable(copy, default, citizenid)
        end
    end
    return target
end

local function needsFill(target, defaults)
    for key, default in pairs(defaults) do
        local current = target[key]
        if type(default) == 'function' then
            if DERIVED[key] and current == nil then return true end
        elseif current == nil then
            return true
        elseif type(default) == 'table' and type(current) == 'table' and needsFill(current, default) then
            return true
        end
    end
    return false
end

local function fillFromDefaults(value, key, citizenid)
    local defaults = QBCore and QBCore.Config and QBCore.Config.Player
        and QBCore.Config.Player.PlayerDefaults and QBCore.Config.Player.PlayerDefaults[key]
    if type(value) ~= 'table' or type(defaults) ~= 'table' then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = v end
    if not needsFill(copy, defaults) then return copy end
    return fillTable(copy, defaults, citizenid)
end

local function fillMetadataDefaults(metadata, citizenid) return fillFromDefaults(metadata, 'metadata', citizenid) end
local function fillCharinfoDefaults(charinfo, citizenid) return fillFromDefaults(charinfo, 'charinfo', citizenid) end

local function legacyPosition(position)
    if type(position) ~= 'table' then return position end
    local view = {}
    for k, v in pairs(position) do view[k] = v end
    if view.w == nil then view.w = view.h end
    if view.h == nil then view.h = view.w end
    return view
end

local function toLegacyPlayerData(playerData)
    if type(playerData) ~= 'table' then return playerData end
    local view = {}
    for k, v in pairs(playerData) do view[k] = v end
    view.job = toLegacyJobOrGang(playerData.job, 'jobs')
    view.gang = toLegacyJobOrGang(playerData.gang, 'gangs')
    view.metadata = fillMetadataDefaults(playerData.metadata, playerData.citizenid)
    view.charinfo = fillCharinfoDefaults(playerData.charinfo, playerData.citizenid)
    view.position = legacyPosition(playerData.position)
    if view.optin == nil then view.optin = true end
    return view
end

local function fromLegacyPlayerData(playerData)
    if type(playerData) ~= 'table' then return playerData end
    local internal = Core.util.deepClone(playerData)
    if type(internal.position) == 'table' then
        if internal.position.h == nil then internal.position.h = internal.position.w end
        internal.position.w = nil
    end
    for _, key in ipairs({ 'job', 'gang' }) do
        local value = internal[key]
        if type(value) == 'table' and type(value.grade) == 'table' then
            value.grade.level = fromLegacyGradeLevel(value.grade.level)
        end
    end
    return internal
end

local SHARED_NAMESPACE_ALIASES = {
    items = 'Items', vehicles = 'Vehicles', jobs = 'Jobs', gangs = 'Gangs',
    weapons = 'Weapons', locations = 'Locations', vehiclehashes = 'VehicleHashes',
    starteritems = 'StarterItems',
}

local function canonicalSharedNamespace(namespace)
    if type(namespace) ~= 'string' then return namespace end
    return SHARED_NAMESPACE_ALIASES[namespace:lower()]
end

Core.compat = Core.compat or {}
Core.compat.toLegacyGradeLevel = toLegacyGradeLevel
Core.compat.fromLegacyGradeLevel = fromLegacyGradeLevel
Core.compat.toLegacyJobOrGang = toLegacyJobOrGang
Core.compat.toLegacyPlayerData = toLegacyPlayerData
Core.compat.fillMetadataDefaults = fillMetadataDefaults
Core.compat.fillCharinfoDefaults = fillCharinfoDefaults
Core.compat.legacyPosition = legacyPosition
Core.compat.fromLegacyPlayerData = fromLegacyPlayerData
Core.compat.canonicalSharedNamespace = canonicalSharedNamespace

function Core.compat.populateLegacyConfig()
    local defaultSpawn = vector4(-1035.71, -2731.87, 12.86, 0.0)
    local dontAllowMinus = {}
    for _, moneyType in ipairs(Config.money.types or {}) do
        if not Config.money.allowNegative[moneyType] then dontAllowMinus[#dontAllowMinus + 1] = moneyType end
    end

    QBCore.Config.MaxPlayers = GetConvarInt('sv_maxclients', 48)
    QBCore.Config.DefaultSpawn = defaultSpawn
    QBCore.Config.UpdateInterval = 5
    QBCore.Config.StatusInterval = 5000
    QBCore.Config.Money = {
        MoneyTypes = Config.money.default,
        DontAllowMinus = dontAllowMinus,
        MinusLimit = Config.money.minusLimit,
        PayCheckTimeOut = 10,
        PayCheckSociety = false,
    }

    local bloodtypes = { 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-' }
    QBCore.Config.Player = {
        HungerRate = 4.2,
        ThirstRate = 3.8,
        Bloodtypes = bloodtypes,
        MaxWeight = Config.inventory.maxWeight,
        MaxInvSlots = Config.inventory.slots,
    }
    QBCore.Config.Player.PlayerDefaults = {
        citizenid = function() return QBCore.Player.CreateCitizenId() end,
        cid = 1,
        money = function() return Core.util.deepClone(QBCore.Config.Money.MoneyTypes) end,
        optin = true,
        charinfo = {
            firstname = 'Firstname', lastname = 'Lastname', birthdate = '00-00-0000', gender = 0,
            nationality = 'USA',
            phone = function() return QBCore.Functions.CreatePhoneNumber() end,
            account = function() return QBCore.Functions.CreateAccountNumber() end,
        },
        job = {
            name = 'unemployed', label = 'Civilian', payment = 10, type = 'none', onduty = false,
            isboss = false, grade = { name = 'Freelancer', level = 0 },
        },
        gang = {
            name = 'none', label = 'No Gang Affiliation', isboss = false,
            grade = { name = 'none', level = 0 },
        },
        metadata = {
            hunger = 100, thirst = 100, stress = 0, isdead = false, inlaststand = false, armor = 0,
            ishandcuffed = false, tracker = false, injail = 0, jailitems = {}, status = {}, phone = {},
            rep = {}, callsign = 'NO CALLSIGN',
            bloodtype = function() return bloodtypes[math.random(1, #bloodtypes)] end,
            fingerprint = function() return QBCore.Player.CreateFingerId() end,
            walletid = function() return QBCore.Player.CreateWalletId() end,
            criminalrecord = { hasRecord = false },
            licences = { driver = true, business = false, weapon = false },
            inside = { apartment = {} },
            phonedata = {
                SerialNumber = function() return QBCore.Player.CreateSerialNumber() end,
                InstalledApps = {},
            },
        },
        position = defaultSpawn,
        items = {},
    }

    QBCore.Config.Server = {
        Closed = false, ClosedReason = 'Server Closed', Uptime = 0, Whitelist = false,
        WhitelistPermission = 'admin', PVP = true, Discord = GetConvar('qb_discord', ''),
        CheckDuplicateLicense = true, Permissions = { 'god', 'admin', 'mod' },
    }
    QBCore.Config.Commands = { OOCColor = { 255, 151, 133 } }
    QBCore.Config.Notify = {
        NotificationStyling = { group = false, position = 'right', progress = true },
        VariantDefinitions = {
            success = { classes = 'success', icon = 'check_circle' },
            primary = { classes = 'primary', icon = 'notifications' },
            warning = { classes = 'warning', icon = 'warning' },
            error = { classes = 'error', icon = 'error' },
            police = { classes = 'police', icon = 'local_police' },
            ambulance = { classes = 'ambulance', icon = 'fas fa-ambulance' },
        },
    }
end

function QBCore.Debug(tbl, indent)
    indent = indent or 0
    local pad = string.rep('  ', indent)
    if type(tbl) ~= 'table' then print(pad .. tostring(tbl)); return end
    for k, v in pairs(tbl) do
        if type(v) == 'table' then
            print(('%s%s:'):format(pad, tostring(k)))
            QBCore.Debug(v, indent + 1)
        else
            print(('%s%s: %s'):format(pad, tostring(k), tostring(v)))
        end
    end
end

function QBCore.ShowError(res, msg) print(('^1[%s] %s^7'):format(res or 'qbcore', msg or '')) end
function QBCore.ShowSuccess(res, msg) print(('^2[%s] %s^7'):format(res or 'qbcore', msg or '')) end
