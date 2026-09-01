-- compat/shared/coreobject.lua -- assembles the QBCore table skeleton and the
-- QBCore.Shared.* helper functions once, for BOTH realms. The realm-specific
-- sections (Functions, Player, per-player method tables, event wiring) are
-- filled in by compat/{server,client}/qb-core.lua, which load after this.
--
-- QBCore is a plain global in qbcore's own VM. It is handed to other resources
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

-- Upstream's IsFunction is a plain `type(value) == 'function'` check with one
-- extra branch for a CFX export-boundary funcref table (`__cfx_functionReference`).
-- This codebase has a well-established local `isCallable` pattern for treating a
-- callable-via-metatable table (e.g. an export identity-hijack proxy) as callable
-- too (see compat/server/qb-core.lua, modules/registry/shared.lua's RI.isCallable,
-- modules/replication/client.lua) -- broader than upstream's own check. We follow
-- that established local convention here rather than upstream's narrower literal
-- body: a legacy script passing a funcref that crossed an export boundary (the
-- exact scenario IsFunction exists to detect) is the same shape our other
-- isCallable call sites already accept, so treating them differently here would
-- be an inconsistency, not a feature.
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
-- Shaped as a number-keyed SET (index -> true), matching how compat/client/
-- qb-core.lua's F.IsWearingGloves already indexes it: `(QBCore.Shared.
-- MaleNoGloves or {})[armIndex]`. That existing read was previously a dead
-- no-op (the table didn't exist); populating it here activates it.
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
-- Expose the same switch for scripts that inspect it directly; qbcore's own
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

-- Jobs/Gangs grades are stored INTERNALLY as a one-based array (see
-- shared/jobs.lua, shared/gangs.lua, and CoreInternal.player.buildJob/buildGang
-- in modules/player/shared.lua -- all three deliberately agree on that shape,
-- and test/smoke/registry.lua pins it). Real qb-core's QBCore.Shared.Jobs/Gangs
-- instead key `grades` by the STRINGIFIED ZERO-BASED grade level ('0', '1', ...),
-- which plenty of legacy scripts read directly (`Jobs[name].grades[tostring(lvl)]`,
-- `for lvl, grade in pairs(job.grades) do ...`). Rather than migrate the internal
-- one-based convention (and everything built on it) to match, this reshapes ONLY
-- the externally-exposed QBCore.Shared view -- the internal registry/player code
-- never sees it.
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

-- Rebuilt from scratch (not patched incrementally) on every registry change --
-- job/gang churn is rare (admin commands, not a hot path), so simplicity wins
-- over the bookkeeping an in-place patch would need. The returned table is a
-- real, plain table (not a metatable proxy) so `pairs()` over it -- and over
-- each record's `grades` -- works without relying on __pairs support.
local function buildLegacyGradeView(regName)
    local view = {}

    local function refresh()
        for k in pairs(view) do view[k] = nil end
        for _, record in ipairs(Core.registry.allShared(regName)) do
            view[record.name] = toLegacyRecord(record)
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

-- QBCore.Shared.VehicleHashes -- upstream keys the Vehicles records a SECOND
-- way, by GetHashKey(model) instead of by model string, for callers that only
-- have a spawned vehicle's model hash (GetEntityModel) rather than its name.
-- Unlike Items/Vehicles/Weapons (a direct read of a registry's materialised
-- table) this has to be BUILT, so it can't go through the `map` __index branch
-- below -- it gets its own branch. Built from the SAME materialised vehicles
-- registry Shared.Vehicles resolves to, and kept fresh with the identical
-- refresh-on-change wiring buildLegacyGradeView uses above (onSharedChange for
-- in-VM mutation, 'qbcore:registry:synced' for the client snapshot gap) --
-- otherwise this cached view would go stale the first time a vehicle is
-- added/updated/removed after the first read.
local function buildVehicleHashesView()
    local view = {}

    local function refresh()
        for k in pairs(view) do view[k] = nil end
        for _, record in ipairs(Core.registry.allShared('vehicles')) do
            view[GetHashKey(record.model)] = record
        end
    end

    refresh()
    if Core.registry.onSharedChange then
        Core.registry.onSharedChange('vehicles', refresh)
    end
    AddEventHandler('qbcore:registry:synced', refresh)

    return view
end

-- The Shared.* data tables (Items/Vehicles/Jobs/Gangs/Weapons/Locations) are the
-- MATERIALISED registry tables. They are wired in the realm files (after the
-- registries exist); a metatable here makes an early read return the live table
-- once it's available rather than nil, and keeps the reference stable.
setmetatable(QBCore.Shared, getmetatable(QBCore.Shared) or {
    __index = function(t, k)
        local legacyGradeRegistries = { Jobs = 'jobs', Gangs = 'gangs' }
        local gradeRegName = legacyGradeRegistries[k]
        if gradeRegName and CoreInternal and CoreInternal.registry and CoreInternal.registry.registries[gradeRegName] then
            local view = buildLegacyGradeView(gradeRegName)
            rawset(t, k, view)   -- cache the stable reference
            return view
        end

        if k == 'VehicleHashes' and CoreInternal and CoreInternal.registry and CoreInternal.registry.registries.vehicles then
            local view = buildVehicleHashesView()
            rawset(t, k, view)   -- cache the stable reference
            return view
        end

        local map = { Items = 'items', Vehicles = 'vehicles', Weapons = 'weapons', Locations = 'locations' }
        local regName = map[k]
        if regName and CoreInternal and CoreInternal.registry and CoreInternal.registry.registries[regName] then
            local mat = CoreInternal.registry.registries[regName].materialised
            rawset(t, k, mat)   -- cache the stable reference
            return mat
        end
        return nil
    end,
})

-- Legacy grade-level translation -------------------------------------------
-- Job/gang grade LEVELS are stored internally as one-based (see the
-- toLegacyGrades comment above -- same design choice, applied to the
-- PLAYER side of the same data instead of just the Shared.Jobs/Gangs view).
-- Real qb-core's grade.level is ZERO-based. Only the legacy QBCore.* surface
-- and QBCore:* event payloads are translated; qbcore's own modern surface
-- (exports.qbcore:*, qbcore:* events, the replication mirror, persistence)
-- is untouched -- this is a VIEW, never a renumbering of the internal model.
local function toLegacyGradeLevel(level)
    return math.max((tonumber(level) or 1) - 1, 0)
end

local function fromLegacyGradeLevel(level)
    return math.max(math.floor(tonumber(level) or 0), 0) + 1
end

local function toLegacyJobOrGang(record)
    if type(record) ~= 'table' then return record end
    local view = {}
    for k, v in pairs(record) do view[k] = v end
    if type(record.grade) == 'table' then
        local grade = {}
        for k, v in pairs(record.grade) do grade[k] = v end
        grade.level = toLegacyGradeLevel(record.grade.level)
        view.grade = grade
    end
    return view
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
    view.job = toLegacyJobOrGang(playerData.job)
    view.gang = toLegacyJobOrGang(playerData.gang)
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

-- GetShared's namespace parameter is a Lua table key -- case-sensitive by
-- construction, since QBCore.Shared.Items/.Vehicles/etc. are PascalCase.
-- Real-world legacy scripts don't reliably match that casing (e.g.
-- qb-recyclejob calls `GetShared('items')`, lowercase) -- a plain
-- QBCore.Shared[namespace] lookup silently returns nil for them, and since
-- GetShared's own callers almost always cache the result in a file-scope
-- local at resource start (`local sharedItems = exports['qb-core']:
-- GetShared('items')`), the nil doesn't surface until something LATER in
-- the file indexes it, with an error that gives no hint the real problem was
-- casing. Both compat/{server,client}/qb-core.lua's GetShared fall back to
-- this canonical-casing lookup before giving up.
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

-- Debug helper (legacy QBCore.Debug prints a table).
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
