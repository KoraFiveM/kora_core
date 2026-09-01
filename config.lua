-- Single flat Config table, per-module sub-tables, a trailing comment on every
-- value -- matching qblib's config.lua convention.

Config = Config or {}

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
    saveOnDrop = true,               -- immediate flush when a player disconnects
}

Config.money = {
    types = { 'cash', 'bank', 'crypto' },  -- account names; the first is the "walking" cash account
    default = { cash = 500, bank = 5000, crypto = 0 },  -- starting balances for a new character
    cashType = 'cash',               -- which account the physical `cash` item / paycheck touches
    allowNegative = { bank = true }, -- accounts permitted to go below zero
    minusLimit = -50000,             -- floor for accounts that allow negative balances
}

Config.inventory = {
    maxWeight = 120000,              -- grams
    slots = 41,                      -- inventory slots per player
    matchInfoOnStack = false,        -- if true, items only stack when their `info` matches (stricter than legacy)
    warnOnUnhandledOpen = true,      -- print when stashOpen has no UI resource listening
    provider = 'qbinventory',        -- headless inventory authority qbcore delegates operational calls to
    allowLegacyFallback = true,      -- temporary staged-rollout fallback; set false to require qbinventory
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
}

Config.consumables = {
    enabled = true,                  -- bridge qbinventory's 'usingItem' hook into QB.status/QB.fx for any item with a shared `effect` table
}

Config.compat = {
    fireLegacyPlayerDataEvent = true,     -- fire QBCore:Player:SetPlayerData client-side from the mirror
    jobUpdateEventSource = 'client',      -- 'client' | 'server' | 'both' -- who emits QBCore:Client:OnJobUpdate
    coreObjectExport = true,              -- register exports['qb-core']:GetCoreObject()
    warnOnUnknownRoot = true,             -- warn when SetPlayerData targets an unmapped root key
    clientMetadataKeys = {},              -- explicit allow-list for legacy QBCore:Server:SetMetaData client writes; empty is secure by default
    callbackTimeoutMs = 5000,              -- CreateCallback/CreateClientCallback: how long to wait for the legacy handler to call its responder before resolving empty
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
        qbinventory = { 'qb-banking' },
        qbtarget = { 'qb-banking', 'qb-recyclejob' },
        PolyZone = { 'qb-recyclejob' },
        qbcore = { 'qb-banking', 'qb-recyclejob' },
    },
    cooldownMs = 15000,               -- a resource won't be restarted again within this many ms of its own last restart
}
