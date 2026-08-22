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
}

Config.jobs = {
    defaultJob = 'unemployed',       -- job assigned to a fresh character
    defaultGrade = 1,                -- one-based grade for the default job
    defaultDuty = true,              -- on-duty state for the default job
}

Config.compat = {
    fireLegacyPlayerDataEvent = true,     -- fire QBCore:Player:SetPlayerData client-side from the mirror
    jobUpdateEventSource = 'client',      -- 'client' | 'server' | 'both' -- who emits QBCore:Client:OnJobUpdate
    coreObjectExport = true,              -- register exports['qb-core']:GetCoreObject()
    warnOnUnknownRoot = true,             -- warn when SetPlayerData targets an unmapped root key
}

Config.replication = {
    resyncRateLimit = 5000,          -- ms; a client may request at most one resync per this window
}
