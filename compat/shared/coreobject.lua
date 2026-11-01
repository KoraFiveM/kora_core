-- compat/shared/coreobject.lua -- assembles the QBCore table skeleton and the
-- QBCore.Shared.* helper functions once, for BOTH realms. The realm-specific
-- sections (Functions, Player, per-player method tables, event wiring) are
-- filled in by compat/{server,client}/qb-core.lua, which load after this.
--
-- QBCore is a plain global in kora_core's own VM. It is handed to other resources
-- verbatim via exports['qb-core']:GetCoreObject() (server/client qb-core.lua),
-- so its shape must match legacy qb-core exactly.

QBCore = QBCore or {}
QBCore.Functions = QBCore.Functions or {}
QBCore.Player = QBCore.Player or {}
QBCore.Players = QBCore.Players or {}        -- src -> QBPlayer (kept in sync by the server compat)
QBCore.PlayersByCitizenId = QBCore.PlayersByCitizenId or {}
QBCore.Shared = QBCore.Shared or {}
QBCore.Commands = QBCore.Commands or {}
QBCore.Config = QBCore.Config or {}
-- Client-realm only in practice (kept server-maintained too before the
-- replication mirror is refreshed, so it is never nil for a script written
-- against real qb-core, which always has SOME value here even pre-login).
QBCore.PlayerData = QBCore.PlayerData or {}

-- Shared string/number helpers, delegated to Core.util so there is one
-- implementation. Legacy names (PascalCase) preserved.
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

-- Broader than upstream's IsFunction: also accepts callable-via-metatable tables (export funcrefs / identity proxies), matching the local isCallable convention.
function QBCore.Shared.IsFunction(value)
    if type(value) == 'function' then return true end
    if type(value) == 'table' then
        if type(rawget(value, '__cfx_functionReference')) == 'string' then return true end
        local mt = getmetatable(value)
        return mt ~= nil and type(mt.__call) == 'function'
    end
    return false
end

-- Starter items granted to a fresh character (real qb-core shared/functions.lua).
QBCore.Shared.StarterItems = {
    phone = { amount = 1, item = 'phone' },
    id_card = { amount = 1, item = 'id_card' },
    driver_license = { amount = 1, item = 'driver_license' },
}

-- Ped component-3 (arms/gloves) drawable indices that mean "no gloves" for the
-- default freemode models -- verbatim from real qb-core shared/functions.lua.
-- Shaped as a number-keyed SET (index -> true), as compat/client/qb-core.lua's F.IsWearingGloves indexes it.
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

-- Current qb-core forces a job's configured default duty state on login.
-- Expose the same switch for scripts that inspect it directly; kora_core's own
-- internal login policy remains Config.jobs.defaultDuty.
QBCore.Shared.ForceJobDefaultDutyAtLogin = true

-- Client-only vehicle-extra helpers (real qb-core shared/functions.lua). Ported
-- near-verbatim -- these touch client-only natives (SetVehicleExtra etc), so
-- they're defined ONLY in the client realm even though this file is shared_script
-- in both. Everything else added in this file is realm-agnostic data/pure
-- functions and does not need this guard.
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

-- Grades are stored INTERNALLY as a one-based array; real qb-core keys `grades` by the stringified ZERO-BASED level ('0', '1', ...), which legacy scripts read directly. This reshapes ONLY the exposed QBCore.Shared view.
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

-- Legacy indexed maps are rebuilt from the getter-backed registry. They are
-- deliberately confined to QBCore compatibility: modern code must call
-- getShared/allShared (or Kora.shared.get/all) when it needs current data.
-- Keeping each compatibility table stable still protects unchanged legacy
-- resources that captured QBCore.Shared.* once at startup.
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
    -- onSharedChange only fires on DELTAS (RI.dispatch). The client's initial
    -- full snapshot goes through RI.reseed, which deliberately does not
    -- dispatch -- so a view built before that snapshot lands would stay empty
    -- until an unrelated delta arrived. The snapshot handler's own
    -- 'qbcore:registry:synced' local event covers that gap; it is never fired
    -- server-side, so this handler is inert there.
    AddEventHandler('qbcore:registry:synced', refresh)

    return view
end

local function buildLegacyGradeView(regName)
    return buildLegacyView(regName, toLegacyRecord)
end

-- QBCore.Shared.VehicleHashes: Vehicles keyed a second way, by joaat(model), for callers holding only GetEntityModel's hash. Same refresh-on-change wiring as buildLegacyGradeView, else the cached view goes stale.
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

-- Upstream Items includes inventory weapons. Native registries keep weapons
-- separate; merge their current records here with explicit item overrides first
-- in precedence, including after either registry changes or a snapshot arrives.
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

-- Weapons is indexed by the native hash returned by GetSelectedPedWeapon and
-- GetPedCauseOfDeath. String aliases would duplicate entries in legacy pairs()
-- loops. Upstream's damage catalog is independent of Items: removing inventory
-- stock must not erase medical history for that weapon. Environmental damage
-- causes remain metadata only, never grantable inventory records.
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
            -- Newer/custom native weapons have no entry in the pinned catalog.
            -- Legacy medical logging still requires a textual death reason.
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

-- QBCore.Shared data maps are compatibility-only views. A metatable here makes
-- an early read build the live view once its registry exists, then caches that
-- stable view for legacy scripts which captured it at startup.
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

-- Job/gang grade LEVELS are stored internally as one-based (see the
-- toLegacyGrades comment above -- same design choice, applied to the
-- PLAYER side of the same data instead of just the Shared.Jobs/Gangs view).
-- Real qb-core's grade.level is ZERO-based. Only the legacy QBCore.* surface
-- and QBCore:* event payloads are translated; kora_core's own modern surface
-- (exports.kora_core:*, qbcore:* events, the replication mirror, persistence)
-- is untouched -- this is a VIEW, never a renumbering of the internal model.
local function toLegacyGradeLevel(level)
    return math.max((tonumber(level) or 1) - 1, 0)
end

local function fromLegacyGradeLevel(level)
    return math.max(math.floor(tonumber(level) or 0), 0) + 1
end

-- Stock qb-core keeps `payment` and `isboss` ON the grade table
-- (job.grade.payment / job.grade.isboss, gang.grade.isboss). Kora's native job
-- keeps them at the root, composed from the job definition by buildJob; they
-- are mirrored into the legacy grade view, falling back to the live registry
-- definition for rows persisted before they were composed. Values already
-- present on the grade are never overwritten.
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

-- Stock CheckPlayerData metadata defaults (config.lua PlayerDefaults.metadata),
-- filled into the legacy VIEW only: existing values are never overwritten and
-- nothing here is persisted, so a native character gains `criminalrecord`,
-- `phonedata`, `inside`, ... for resources that index them unguarded.
-- Function defaults are random per call (bloodtype, fingerprint, walletid) and
-- would differ on every read, so they are skipped (new characters are seeded
-- with them natively); phonedata.SerialNumber is derived from the citizenid so
-- it is stable instead.
local function stableSerial(citizenid)
    local hash = 7
    for i = 1, #tostring(citizenid or '') do hash = (hash * 31 + tostring(citizenid):byte(i)) % 1000000007 end
    return ('%09d'):format(hash)
end

local function fillTable(target, defaults, citizenid)
    for key, default in pairs(defaults) do
        if type(default) == 'function' then
            if key == 'SerialNumber' and target[key] == nil then target[key] = stableSerial(citizenid) end
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

-- Allocation-free probe: true when anything in `defaults` is missing from
-- `target`. Almost every read after the first finds a complete table, so the
-- common case skips building nested copies.
local function needsFill(target, defaults)
    for key, default in pairs(defaults) do
        local current = target[key]
        if type(default) == 'function' then
            if key == 'SerialNumber' and current == nil then return true end
        elseif current == nil then
            return true
        elseif type(default) == 'table' and type(current) == 'table' and needsFill(current, default) then
            return true
        end
    end
    return false
end

local function fillMetadataDefaults(metadata, citizenid)
    local defaults = QBCore and QBCore.Config and QBCore.Config.Player
        and QBCore.Config.Player.PlayerDefaults and QBCore.Config.Player.PlayerDefaults.metadata
    if type(metadata) ~= 'table' or type(defaults) ~= 'table' then return metadata end
    local copy = {}
    for k, v in pairs(metadata) do copy[k] = v end
    if not needsFill(copy, defaults) then return copy end
    return fillTable(copy, defaults, citizenid)
end

-- A legacy-shaped PlayerData table: every root key copied by reference
-- EXCEPT job/gang, which get a translated COPY. Must be a real, raw-keyed
-- table (not a metatable proxy) -- it crosses the export boundary to
-- third-party resources, and FXServer's msgpack marshaling walks a table's
-- own raw keys, never invoking __index. Kept incrementally in sync by
-- Core.compat.onPlayerDataChanged below, NOT rebuilt wholesale on every
-- read -- job/gang are wholesale-REPLACED (not field-mutated) by
-- Core.jobs.setJob/setGang, so a one-shot copy at login would go stale the
-- first time either changes.
local function toLegacyPlayerData(playerData)
    if type(playerData) ~= 'table' then return playerData end
    local view = {}
    for k, v in pairs(playerData) do view[k] = v end
    view.job = toLegacyJobOrGang(playerData.job, 'jobs')
    view.gang = toLegacyJobOrGang(playerData.gang, 'gangs')
    view.metadata = fillMetadataDefaults(playerData.metadata, playerData.citizenid)
    return view
end

local function fromLegacyPlayerData(playerData)
    if type(playerData) ~= 'table' then return playerData end
    local internal = Core.util.deepClone(playerData)
    for _, key in ipairs({ 'job', 'gang' }) do
        local value = internal[key]
        if type(value) == 'table' and type(value.grade) == 'table' then
            value.grade.level = fromLegacyGradeLevel(value.grade.level)
        end
    end
    return internal
end

-- GetShared's namespace is case-sensitive (PascalCase) but legacy scripts call e.g. GetShared('items') (qb-recyclejob); a plain lookup returns nil and the error only surfaces much later, so both realms' GetShared fall back to this canonical-casing lookup.
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
Core.compat.fromLegacyPlayerData = fromLegacyPlayerData
Core.compat.canonicalSharedNamespace = canonicalSharedNamespace

-- Materialise the complete public qb-core configuration shape in both realms.
-- Values that drive this framework use the local Config equivalents; display-
-- only/UI defaults match upstream so legacy resources never encounter a
-- missing intermediate table or field.
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
