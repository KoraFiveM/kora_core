
Config = Config or {}

Config.server = {
    name = 'Roleplay Server Name',   -- shown as the title in GTA's standard pause menu; set an empty string to leave FiveM's default title intact
}

Config.identity = {
    primaryIdentifier = 'license',   -- which identifier keys a player across characters
    citizenIdLength = 8,             -- length of a generated citizenid (excluding the type prefix)
    citizenIdPrefix = '',            -- optional prefix, e.g. 'QB' -> 'QBAB12CD34'
    maxCharacters = 5,               -- default multichar slots per identity; a `users` row can override this per-license (see Core.users.setMaxCharacters)
}

Config.persistence = {
    interval = 60000,                -- ms between coalescing save flushes (worst-case crash loss)
    intervalJitter = 0.10,           -- +/- fraction of jitter so saves don't thundering-herd
    positionEpsilon = 2.0,           -- metres a player must move before position is re-persisted
    positionMaxAge = 300000,         -- ms after which position persists even if the player is parked
    volatileMetadataKeys = {},       -- metadata keys routed to a separate column (OFF by default; see AGENTS.md)
    generatedColumns = false,        -- run sql/003 to add VIRTUAL cash/bank/job columns for SQL-side queries
    legacyVehicleState = false,      -- convert a stock INT player_vehicles.state to kora's ENUM (opt-in; see docs/vehicles-compat.md)
    saveOnDrop = true,               -- immediate flush when a player disconnects
}

Config.money = {
    types = { 'cash', 'bank', 'crypto' },  -- account names; the first is the "walking" cash account
    default = { cash = 500, bank = 5000, crypto = 0 },  -- starting balances for a new character
    cashType = 'cash',               -- which account the physical `cash` item / paycheck touches
    allowNegative = { bank = true }, -- accounts permitted to go below zero
    minusLimit = -50000,             -- floor for accounts that allow negative balances

    -- Transaction tax. A percentage of every taxable transaction is carved out
    -- of the amount and deposited into a banking account (the "government"),
    -- never added on top -- see modules/money/AGENTS.md for the exact model and
    -- why that direction was chosen. Pass `ignoreTax = true` as the last
    -- argument to addMoney/removeMoney/transferMoney to exempt one call.
    tax = {
        enabled = false,             -- master switch; OFF so an existing economy is unchanged until a server opts in
        rate = 0.05,                 -- fraction of each taxable transaction diverted to the government (0.05 = 5%)
        account = 'government',      -- banking account name the collected tax is deposited into
        provider = 'qb-banking',     -- resource holding that account; while it is not running transactions go through UNTAXED (money is never destroyed)
        autoCreateAccount = true,    -- create `account` through the provider the first time tax is collected
        exports = { add = 'AddMoney', get = 'GetAccount', create = 'CreateJobAccount' }, -- provider export names, so a non-qb-banking bank can be pointed at
        accounts = { cash = true, bank = true, crypto = false }, -- which Config.money.types are taxable; an account absent here is never taxed
        actions = { add = true, remove = true, transfer = true }, -- taxable operations; setMoney is NEVER taxed (absolute assignment, not a transaction)
    },
}

Config.inventory = {
    maxWeight = 120000,              -- grams
    slots = 41,                      -- inventory slots per player
    matchInfoOnStack = false,        -- if true, items only stack when their `info` matches (stricter than legacy)
    warnOnUnhandledOpen = true,      -- print when stashOpen has no UI resource listening
    provider = 'kora_inventory',        -- headless inventory authority kora_core delegates operational calls to
    allowLegacyFallback = true,      -- temporary staged-rollout fallback; set false to require kora_inventory
    dropTTL = 1800000,               -- ms a ground drop survives uncollected before the sweep removes it
    dropSweepInterval = 300000,      -- ms between sweeps that expire old ground drops
}

Config.jobs = {
    defaultJob = 'unemployed',       -- job assigned to a fresh character
    defaultGrade = 1,                -- one-based grade for the default job
    defaultDuty = true,              -- on-duty state for the default job
    paycheckInterval = 300000,       -- ms between Core.paycheck ticks
}

Config.dispatch = {
    legacyEvents = true,             -- also fire police:client:policeAlert / hospital:client:ambulanceAlert compat events
}

Config.needs = {
    tickInterval = 60000,            -- ms between server-authoritative hunger/thirst decay ticks
    hungerDecay = 1,                 -- hunger lost per tick
    thirstDecay = 1,                 -- thirst lost per tick
    hungerDamage = 5,                -- client ped damage on each server update while hunger is zero
    thirstDamage = 5,                -- client ped damage on each server update while thirst is zero (stacks with hunger damage)
}

Config.development = {
    walkSpeed = 1.75,                -- per-frame SetPedMoveRateOverride value while a player's development mode is active
}

Config.jail = {
    -- Resources checked (in order) via GetResourceState before Core.jail
    -- applies its own teleport/timer -- if one of these is running, Core.jail
    -- fires 'qbcore:server:onJailRequest' and steps aside entirely, same
    -- deference pattern qbx_police uses for xt-prison/qbx_prison.
    deferToResources = { 'xt-prison', 'qbx_prison' },
    coords = vector4(1651.86, 2570.13, 45.56, 22.0), -- Bolingbroke Penitentiary yard, used when nothing else configures a location
}

Config.garage = {
    defaultFuel = 100,
    defaultEngineHealth = 1000,
    defaultBodyHealth = 1000,
    spawnNetworkIdTimeout = 1000, -- ms to wait for a positive entity network ID before changing durable state
}

Config.consumables = {
    enabled = true,                  -- bridge kora_inventory's 'usingItem' hook into Kora.status/Kora.fx for any item with a shared `effect` table
}

Config.compat = {
    fireLegacyPlayerDataEvent = true,     -- fire QBCore:Player:SetPlayerData client-side from the mirror
    inventoryPlayerDataEventInterval = 250, -- ms; coalesce inventory-only legacy notifications; 0 fires every delta
    jobUpdateEventSource = 'client',      -- 'client' | 'server' | 'both' -- who emits QBCore:Client:OnJobUpdate
    coreObjectExport = true,              -- register exports['qb-core']:GetCoreObject()
    warnOnUnknownRoot = true,             -- warn when SetPlayerData targets an unmapped root key
    clientMetadataKeys = {                -- explicit allow-list for legacy QBCore:Server:SetMetaData client writes.
        hunger = true,                    -- defaults = the keys stock qb-core accepts from clients: numeric only, clamped to 0..100 server-side
        thirst = true,                    -- (rules live in compat/server/qb-core-events.lua). Every other key is rejected; do NOT add money,
        stress = true,                    -- jail, isdead, inlaststand, licences, criminalrecord or callsign -- a client could forge them.
    },
    toggleDutyEvent = true,               -- register the stock client-inbound QBCore:ToggleDuty (flips the caller's own duty flag; needs a non-default job, 2s per-player cooldown). false = job resources must own duty transitions
    callbackTimeoutMs = 5000,              -- CreateCallback/CreateClientCallback: how long to wait for the legacy handler to call its responder before resolving empty
    qbxFacade = false,                    -- publish the qbx_core/qbx_vehicles export+event surface for stock ox_inventory (`inventory:framework qbx`); also enabled by `setr kora:qbxFacade true`. See compat/server/qbx.lua
    defaultCommands = true,               -- register the 20 stock qb-core commands (tp, tpm, togglepvp, addpermission, removepermission, openserver, closeserver, car, dv, dvall, dvp, dvo, givemoney, setmoney, job, setjob, gang, setgang, ooc, me); a name another resource already registered is kept. See docs/default-commands.md
    vehicleSpawnCallbacks = 'limited',    -- stock server callbacks QBCore:Server:SpawnVehicle / CreateVehicle: 'off' | 'admin' (kora admin permission only) | 'limited' (any loaded player, validated; see vehicleSpawn). Also backs the networked client QBCore.Functions.SpawnVehicle. See docs/vehicle-spawn.md
    vehicleSpawn = {
        maxDistance = 75.0,               -- requested coords must be within this many metres of the caller's ped (limited mode)
        cooldownMs = 2000,                -- per-player minimum time between spawn requests
        maxLive = 2,                      -- live compat-spawned vehicles per player; the oldest is deleted to make room
        allowModels = {},                 -- extra model names accepted besides QBCore.Shared.Vehicles, e.g. { 'adder' }
        grantKeys = true,                 -- give the requester keys through kora_vehiclekeys when it is started
        deleteOnDrop = true,              -- delete a player's compat-spawned vehicles when they leave
    },
    deferClientPlayerLoaded = false,      -- false: QBCore:Client:OnPlayerLoaded fires at login (kora consumers rely on it). true: stock timing, fired when the client sends QBCore:Server:OnPlayerLoaded after spawn (kora_multichar and stock qb-spawn/qb-multicharacter send it). See docs/index.md
    stress = {                            -- stock hud:server:GainStress / RelieveStress (ignored while a real qb-hud is started)
        disabled = false,                 -- true = ignore both events
        whitelistedJobs = { leo = true, ambulance = true }, -- job names or job types that never gain or lose stress
        cooldownMs = 250,                 -- per-player minimum time between accepted events
    },
    fireSharedUpdateAtLogin = false,      -- also fire QBCore:Client:SharedUpdate(QBCore.Shared) at login; OFF because the registry snapshot already covers this
}

Config.replication = {
    resyncRateLimit = 5000,          -- ms; a client may request at most one resync per this window
}

Config.dependencySupervisor = {
    -- OFF by default -- new behavior with no existing convention; opt in
    -- per-server once server.cfg's ensure order and restart blast radius have
    -- been reviewed. See modules/dependencySupervisor/AGENTS.md.
    enabled = false,
    -- provider resource name -> list of resources to restart once the
    -- provider (re)starts. Exists for legacy scripts that can't re-register
    -- themselves against a dependency that restarted mid-session.
    map = {
        kora_inventory = { 'qb-banking' },
        kora_target = { 'qb-banking' },
        PolyZone = { },
        kora_core = { 'qb-banking' },
    },
    cooldownMs = 15000,               -- a resource won't be restarted again within this many ms of its own last restart
}

-- Registers this resource-owned configuration with kora_lib without changing its public Config table.
if Kora and Kora.config and Kora.config.adopt then
    Config.compat.jobUpdateEventSource = Kora.config.enum(Config.compat.jobUpdateEventSource, {
        label = 'Legacy job-update event source',
        description = 'Selects which realm emits the legacy QBCore:Client:OnJobUpdate compatibility event. Client matches traditional behaviour, server supports server-originated integrations, and both should be used only when consumers safely tolerate duplicate notifications.',
        options = {
            { value = 'client', label = 'Client' },
            { value = 'server', label = 'Server' },
            { value = 'both', label = 'Client and server' },
        },
    })
    Config.persistence.volatileMetadataKeys = Kora.config.map(Config.persistence.volatileMetadataKeys,
        Kora.config.boolean(false), {
            scope = 'server',
            label = 'Volatile metadata keys',
            description = 'Defines metadata keys that persistence routes to the separate volatile metadata column. Use the exact metadata key as each row key and true as its value; leave the map empty unless the database schema and migration policy explicitly use volatile metadata.',
        })
    Config.compat.clientMetadataKeys = Kora.config.map(Config.compat.clientMetadataKeys,
        Kora.config.boolean(false), {
            scope = 'server',
            label = 'Client-writable legacy metadata keys',
            description = 'Allow-lists metadata keys accepted by the legacy QBCore:Server:SetMetaData compatibility event. Use the exact metadata key with true to permit it. The default enables only hunger, thirst and stress (numeric, clamped to 0-100 on the server) as stock qb-core does. Every enabled key lets a client request changes to that metadata field, so never enable money, jail, isdead, inlaststand, licences, criminalrecord or callsign.',
        })
    Config.dependencySupervisor.map = Kora.config.map(Config.dependencySupervisor.map,
        Kora.config.list({}, Kora.config.string('', { minLength = 1 })), {
            scope = 'server',
            label = 'Dependency restart map',
            description = 'Maps a provider resource name to the ordered list of dependent resources restarted after that provider starts. Empty lists are valid. This supervisor remains inactive unless Dependency supervisor enabled is also turned on; review restart ordering and player impact before enabling it.',
        })
    Config = Kora.config.adopt(Config)
end
