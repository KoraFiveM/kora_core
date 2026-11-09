Config = Config or {}

Config.server = {
    name = 'Roleplay Server Name',
}

Config.identity = {
    primaryIdentifier = 'license',
    citizenIdLength = 8,
    citizenIdPrefix = '',
    maxCharacters = 5,
    saveDiscord = true,
}

Config.persistence = {
    interval = 60000,
    intervalJitter = 0.10,
    positionEpsilon = 2.0,
    positionMaxAge = 300000,
    volatileMetadataKeys = {},
    generatedColumns = false,
    saveOnDrop = true,
}

Config.money = {
    types = { 'cash', 'bank', 'crypto' },
    default = { cash = 500, bank = 5000, crypto = 0 },
    cashType = 'cash',
    allowNegative = { bank = true },
    minusLimit = -50000,

    tax = {
        enabled = false,
        rate = 0.05,
        account = 'government',
        provider = 'qb-banking',
        autoCreateAccount = true,
        exports = { add = 'AddMoney', get = 'GetAccount', create = 'CreateJobAccount' },
        accounts = { cash = true, bank = true, crypto = false },
        actions = { add = true, remove = true, transfer = true },
    },
}

Config.inventory = {
    maxWeight = 120000,
    slots = 41,
    matchInfoOnStack = false,
    warnOnUnhandledOpen = true,
    provider = 'kora_inventory',
    allowLegacyFallback = true,
    dropTTL = 1800000,
    dropSweepInterval = 300000,
}

Config.jobs = {
    defaultJob = 'unemployed',
    defaultGrade = 1,
    defaultDuty = true,
    paycheckInterval = 300000,
}

Config.dispatch = {
    legacyEvents = true,
}

Config.needs = {
    tickInterval = 60000,
    hungerDecay = 1,
    thirstDecay = 1,
    hungerDamage = 5,
    thirstDamage = 5,
}

Config.development = {
    walkSpeed = 1.75,
}

Config.jail = {
    deferToResources = { 'xt-prison', 'qbx_prison' },
    coords = vector4(1651.86, 2570.13, 45.56, 22.0),
}

Config.garage = {
    defaultFuel = 100,
    defaultEngineHealth = 1000,
    defaultBodyHealth = 1000,
    spawnNetworkIdTimeout = 1000,
}

Config.consumables = {
    enabled = true,
}

Config.compat = {
    fireLegacyPlayerDataEvent = true,
    inventoryPlayerDataEventInterval = 250,
    jobUpdateEventSource = 'client',
    coreObjectExport = true,
    warnOnUnknownRoot = true,
    clientMetadataKeys = {
        hunger = true,
        thirst = true,
        stress = true,
    },
    toggleDutyEvent = true,
    callbackTimeoutMs = 5000,
    qbxFacade = false,
    defaultCommands = true,
    vehicleSpawnCallbacks = 'limited',
    vehicleSpawn = {
        maxDistance = 75.0,
        cooldownMs = 2000,
        maxLive = 2,
        allowModels = {},
        grantKeys = true,
        deleteOnDrop = true,
    },
    deferClientPlayerLoaded = false,
    stress = {
        disabled = false,
        whitelistedJobs = { leo = true, ambulance = true },
        cooldownMs = 250,
    },
    fireSharedUpdateAtLogin = false,
}

Config.locales = {
    defaultKey = 'F10',
}

Config.vehicleAirControl = {
    disable = true,
    exemptClasses = { 8, 13, 14, 15, 16, 21 },
}

Config.replication = {
    resyncRateLimit = 5000,
    snapshotCoalesceMs = 250,
}

Config.dependencySupervisor = {
    enabled = false,
    map = {
        kora_inventory = { 'qb-banking' },
        kora_target = { 'qb-banking' },
        PolyZone = { },
        kora_core = { 'qb-banking' },
    },
    cooldownMs = 15000,
}

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
    Config.vehicleAirControl.disable = Kora.config.boolean(Config.vehicleAirControl.disable, {
        scope = 'client',
        live = true,
        label = 'Disable vehicle air control',
        description = 'When on, the driver of a non-exempt vehicle cannot steer, pitch or roll it while it is airborne, which stops perfect landings. It never blocks controls while the vehicle is on the ground, even upside down. Read each time the driver enters a vehicle, so a change applies from the next entry.',
    })
    Config.vehicleAirControl.exemptClasses = Kora.config.list(Config.vehicleAirControl.exemptClasses,
        Kora.config.integer(0, { min = 0, max = 22 }), {
            scope = 'client',
            live = true,
            label = 'Air-control exempt vehicle classes',
            description = 'GTA vehicle class numbers that keep normal air control. The default 8, 13, 14, 15, 16, 21 covers motorcycles, cycles, boats, helicopters, planes and trains. Remove 8 to make motorcycles lose air control; remove any number to disable air control for that class. Read each time the driver enters a vehicle.',
        })
    Config.locales.defaultKey = Kora.config.string(Config.locales.defaultKey, {
        scope = 'client',
        label = 'Language selector default key',
        description = 'Default keyboard key (for example F10 or L) for the Open language selector keybind. Players can change it themselves in Settings > Key Bindings > FiveM. Leave empty for no default key; the /language command still works. Applies when the resource starts.',
    })
    Config = Kora.config.adopt(Config)
end
