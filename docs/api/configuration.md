---
title: "Configuration"
sidebar_position: 15
---


# Configuration

## Server

`config.lua` defines one global `Config` table, loaded as a shared script, so the same file is read by the server and by every client. Edit the file and restart `kora_core`. Keys are plain Lua, not convars. Several keys are only read by `compat/` code (marked below). Keys documented as "Not read by any code" are accepted by the file and by the config registry but nothing in this resource reads them, so changing them has no effect. The last block of the file registers some keys with kora_lib's `Kora.config` (types, labels, live edit flags) without changing the public `Config` table shape.

Namespace: `Config` · Source: `config.lua (shared_scripts, loaded in both realms)`

### Config groups and who reads them

Group, what it controls, and the module that reads it.

| Group | What it controls | Read by |
| --- | --- | --- |
| `Config.server` | Pause menu title. | modules/pausemenu (client) |
| `Config.identity` | Primary identifier, citizenid format, character slots, Discord id storage. | modules/identity, modules/users, modules/permissions, compat |
| `Config.persistence` | Save interval, position write thresholds, generated SQL columns, volatile metadata (unused). | modules/persistence |
| `Config.money` | Accounts, defaults, negative balances, transaction tax. | modules/money, modules/player/shared.lua, modules/paycheck |
| `Config.replication` | Resync rate limit. | modules/replication |
| `Config.inventory` | Weight and slots, stack rule, provider, ground drop expiry. | modules/inventory, modules/money, modules/persistence |
| `Config.jobs` | Default job and grade, paycheck interval. | modules/player/shared.lua, modules/paycheck |
| `Config.dispatch` | Legacy dispatch events. | modules/dispatch |
| `Config.needs` | Hunger and thirst decay and damage. | modules/needs (server and client) |
| `Config.development` | Dev mode walk speed. | modules/development (client) |
| `Config.jail` | External prison resources and jail cell location. | modules/jail |
| `Config.garage` | Default vehicle condition and network id timeout. | modules/garage |
| `Config.consumables` | Item effect bridge switch. | modules/consumables |
| `Config.compat` | Legacy qb-core behaviour switches and limits. | modules/replication, modules/player, modules/jobs, compat/ |
| `Config.locales` | Language selector default key. | modules/locales (client) |
| `Config.vehicleAirControl` | Airborne vehicle control lock. | modules/vehicleAirControl (client) |
| `Config.dependencySupervisor` | Restart dependents when a provider starts. | modules/dependencySupervisor |
| Adoption block | Registers selected keys with `Kora.config`. | kora_lib (end of config.lua) |

### How it works

All values are read at the moment named in each description; most are read on use, a few once at start (`Config.locales.defaultKey`, `Config.identity.citizenIdPrefix`, `Config.development.walkSpeed`, the vehicle air control settings are read on each vehicle entry). Because config is a shared script, any value in it is visible to clients: never put secrets in `Config`.

### Changing a setting

1. **Find the group** — Use the index table to see which module reads the group.
2. **Edit config.lua** — Change the value in place. Keep the type (milliseconds are integers, rates are fractions).
3. **Restart the resource** — Run `restart kora_core` (or the single-resource restart you normally use). Keys marked live in the adoption block apply on the next read without a restart.

### Terms used on this page

| Term | Meaning |
| --- | --- |
| Config group | A sub-table such as `Config.money`. Each group is read by one module, plus `compat/` for legacy keys. |
| Adoption block | The final `if Kora and Kora.config and Kora.config.adopt` block of config.lua. It wraps selected keys with type and label metadata for kora_lib and returns the adopted `Config`. |
| Compat-only key | A key read only by code under `compat/`. It has no effect if the compat layer does not load that file. |

### Config keys

Every key with its default and unit. "Not read by any code" means no Lua file in this resource reads the key.

#### Config.server

Read by modules/pausemenu/client.lua when the client starts.

| Option | Type | Description |
| --- | --- | --- |
| `Config.server.name` | string | Default `'Roleplay Server Name'`. Title in the GTA pause menu via the `FE_THDR_GTAO` text entry. An empty string (or a non-string) leaves the FiveM default title. Read once at client start. |

#### Config.identity

Read by modules/identity, modules/users and modules/permissions (server), and by compat.

| Option | Type | Description |
| --- | --- | --- |
| `Config.identity.primaryIdentifier` | string | Default `'license'`. Identifier type that keys a player across characters. Also used to build the ACE principal in `addPermission` and `removePermission`. |
| `Config.identity.citizenIdLength` | integer | Default `8`. Characters in a generated citizenid, not counting the prefix. Random alphanumeric. |
| `Config.identity.citizenIdPrefix` | string | Default `''` (none). Prefix added to every generated citizenid, for example `QB`. Read once when the identity module loads. |
| `Config.identity.maxCharacters` | integer | Default `5`. Character slots per identity. A row in the `users` table can override it per license. |
| `Config.identity.saveDiscord` | boolean | Default `true`. Store the player's Discord id on their `users` row. Needs Discord running when the player connects. |

#### Config.persistence

Read by modules/persistence (server) and its schema and boot files.

| Option | Type | Description |
| --- | --- | --- |
| `Config.persistence.interval` | integer (ms) | Default `60000`. Time between coalesced save flushes; the worst-case loss on a crash. |
| `Config.persistence.intervalJitter` | number (fraction) | Default `0.10`. The wait is randomised by plus or minus this fraction so saves do not all fire together. 0 disables jitter. |
| `Config.persistence.positionEpsilon` | number (metres) | Default `2.0`. Distance a player must move before the position is saved again. |
| `Config.persistence.positionMaxAge` | integer (ms) | Default `300000`. Age after which the position is saved even if the player did not move. |
| `Config.persistence.volatileMetadataKeys` | table | Default `{}`. Not read by any code: it is only declared in config.lua and registered in the adoption block, no persistence module reads it. Metadata keys are not routed to a separate column. |
| `Config.persistence.generatedColumns` | boolean | Default `false`. When true, schema boot adds VIRTUAL cash, bank and job columns for SQL-side queries. |
| `Config.persistence.saveOnDrop` | boolean | Default `true`. Not read by any code. A disconnect always saves immediately (`Core.persistence.saveNow` in `dropPlayer`), whatever this value is. |

#### Config.money

Read by modules/money, modules/player/shared.lua and modules/paycheck.

| Option | Type | Description |
| --- | --- | --- |
| `Config.money.types` | string[] | Default `{ 'cash', 'bank', 'crypto' }`. Valid account names. The first is the walking cash account. Each name gets a `kora_core:money:<account>` state bag. |
| `Config.money.default` | table | Default `{ cash = 500, bank = 5000, crypto = 0 }`. Starting balances for a new character. A type missing here starts at 0. |
| `Config.money.cashType` | string | Default `'cash'`. Account the physical cash item and the paycheck use. The inventory provider may register only this account as physical. |
| `Config.money.allowNegative` | table | Default `{ bank = true }`. Accounts allowed to go below zero. |
| `Config.money.minusLimit` | number | Default `-50000`. Lowest balance for accounts in `allowNegative`. Other accounts floor at 0. |
| `Config.money.tax.enabled` | boolean | Default `false`. Master switch for the transaction tax. Off keeps an existing economy unchanged. |
| `Config.money.tax.rate` | number (fraction) | Default `0.05` (5%). Share of each taxable transaction carved out and deposited to the banking account. Values above 1 are treated as 1; the tax is floored. |
| `Config.money.tax.account` | string | Default `'government'`. Banking account that receives the tax. |
| `Config.money.tax.provider` | string | Default `'qb-banking'`. Resource holding that account. While it is not started, transactions go through untaxed. |
| `Config.money.tax.autoCreateAccount` | boolean | Default `true`. Create the account through the provider the first time tax is collected. False fails the deposit if the account does not exist. |
| `Config.money.tax.exports` | table | Default `{ add = 'AddMoney', get = 'GetAccount', create = 'CreateJobAccount' }`. Provider export names, so another bank can be used. |
| `Config.money.tax.accounts` | table | Default `{ cash = true, bank = true, crypto = false }`. Taxable accounts. A missing account is never taxed. |
| `Config.money.tax.actions` | table | Default `{ add = true, remove = true, transfer = true }`. Taxable operations. `setMoney` is never taxed. |

#### Config.replication

Read by modules/replication/server.lua.

| Option | Type | Description |
| --- | --- | --- |
| `Config.replication.resyncRateLimit` | integer (ms) | Default `5000`. A client may get at most one snapshot resync per this window; extra `kora_core:rep:resync` requests are dropped. |

#### Config.inventory

Read by modules/inventory (server, shared), modules/money and modules/persistence.

| Option | Type | Description |
| --- | --- | --- |
| `Config.inventory.maxWeight` | integer (grams) | Default `120000`. Carry limit per player. |
| `Config.inventory.slots` | integer | Default `41`. Inventory slots per player. |
| `Config.inventory.matchInfoOnStack` | boolean | Default `false`. When true, items stack only if their `info` matches. |
| `Config.inventory.warnOnUnhandledOpen` | boolean | Default `true`. Print a warning when `stashOpen` finds no UI that handled `kora_core:inventory:open`. |
| `Config.inventory.provider` | string | Default `'kora_inventory'`. Resource that owns operational inventory calls and the physical cash account. Only this resource may register physical cash. |
| `Config.inventory.allowLegacyFallback` | boolean | Default `true`. Staged-rollout fallback to the built-in inventory when the provider is unavailable. False requires the provider. |
| `Config.inventory.dropTTL` | integer (ms) | Default `1800000` (30 minutes). Lifetime of an uncollected ground drop. |
| `Config.inventory.dropSweepInterval` | integer (ms) | Default `300000` (5 minutes). Time between sweeps that expire old drops. |

#### Config.jobs

Read by modules/player/shared.lua and modules/paycheck.

| Option | Type | Description |
| --- | --- | --- |
| `Config.jobs.defaultJob` | string | Default `'unemployed'`. Job given to a new character. |
| `Config.jobs.defaultGrade` | integer | Default `1`. One-based grade for the default job. |
| `Config.jobs.defaultDuty` | boolean | Default `true`. Not read by any code: the login duty state comes from each job definition's `defaultDuty` field (true unless a job sets it to false), not from this key. Only a comment in compat/shared/coreobject.lua mentions it. |
| `Config.jobs.paycheckInterval` | integer (ms) | Default `300000` (5 minutes). Time between paycheck ticks. |

#### Config.dispatch

Read by modules/dispatch/server.lua.

| Option | Type | Description |
| --- | --- | --- |
| `Config.dispatch.legacyEvents` | boolean | Default `true`. Also fire `police:server:policeAlert`, `police:client:policeAlert` and `hospital:client:ambulanceAlert` from `Core.dispatch.alert`. |

#### Config.needs

Server keys are read by modules/needs/server.lua, damage keys by modules/needs/client.lua.

| Option | Type | Description |
| --- | --- | --- |
| `Config.needs.tickInterval` | integer (ms) | Default `60000`. Time between server hunger and thirst decay ticks. |
| `Config.needs.hungerDecay` | number | Default `1`. Hunger lost per tick. |
| `Config.needs.thirstDecay` | number | Default `1`. Thirst lost per tick. |
| `Config.needs.hungerDamage` | number | Default `5`. Client ped damage applied on each server update while hunger is zero. |
| `Config.needs.thirstDamage` | number | Default `5`. Client ped damage applied while thirst is zero; stacks with hunger damage. |

#### Config.development

Read by modules/development/client.lua.

| Option | Type | Description |
| --- | --- | --- |
| `Config.development.walkSpeed` | number | Default `1.75`. Per-frame move rate override while development mode is active. Must be a positive number or the module raises an error at client start. |

#### Config.jail

Read by modules/jail/server.lua.

| Option | Type | Description |
| --- | --- | --- |
| `Config.jail.deferToResources` | string[] | Default `{ 'xt-prison', 'qbx_prison' }`. Resources checked in order with `GetResourceState`. If one is started, `jailPlayer` raises `kora_core:server:onJailRequest` and does nothing else. |
| `Config.jail.coords` | vector4 | Default `vector4(1651.86, 2570.13, 45.56, 22.0)` (Bolingbroke yard). Cell location for native jailing. The containment radius is fixed at 30 m in code. |

#### Config.garage

Read by modules/garage/server.lua.

| Option | Type | Description |
| --- | --- | --- |
| `Config.garage.defaultFuel` | number | Default `100`. Fuel level for new vehicle records. |
| `Config.garage.defaultEngineHealth` | number | Default `1000`. Engine health for new vehicle records. |
| `Config.garage.defaultBodyHealth` | number | Default `1000`. Body health for new vehicle records. |
| `Config.garage.spawnNetworkIdTimeout` | integer (ms) | Default `1000`. Time to wait for a positive network id before durable state is changed. |

#### Config.consumables

Read by modules/consumables/server.lua.

| Option | Type | Description |
| --- | --- | --- |
| `Config.consumables.enabled` | boolean | Default `true`. Bridge kora_inventory's `usingItem` hook into `Kora.status` and `Kora.fx` for items that have a shared `effect` table. |

#### Config.compat

Legacy qb-core behaviour. Keys marked "compat only" are read only by files under compat/ and are documented further in the Compatibility module.

| Option | Type | Description |
| --- | --- | --- |
| `Config.compat.fireLegacyPlayerDataEvent` | boolean | Default `true`. Fire `QBCore:Player:SetPlayerData` client-side from the mirror (modules/replication/client.lua). |
| `Config.compat.inventoryPlayerDataEventInterval` | integer (ms) | Default `250`. Coalesce inventory-only legacy notifications into one per window. 0 fires on every delta. |
| `Config.compat.jobUpdateEventSource` | string | Default `'client'`. Who emits `QBCore:Client:OnJobUpdate`, `OnGangUpdate` and `OnPlayerUpdated`: `'client'` (from the mirror), `'server'` (sent by the server) or `'both'`. Adopted as an enum in the adoption block. |
| `Config.compat.coreObjectExport` | boolean | Default `true`. Compat only. Register `exports['qb-core']:GetCoreObject()`. |
| `Config.compat.warnOnUnknownRoot` | boolean | Default `true`. Compat only. Warn when `SetPlayerData` targets an unmapped root key. |
| `Config.compat.clientMetadataKeys` | table | Default `{ hunger = true, thirst = true, stress = true }`. Compat only. Allow-list of metadata keys a client may write through the legacy `QBCore:Server:SetMetaData` event (numeric, clamped 0 to 100 on the server). Never add money, jail, isdead, inlaststand, licences, criminalrecord or callsign. |
| `Config.compat.toggleDutyEvent` | boolean | Default `true`. Compat only. Register the stock client-inbound `QBCore:ToggleDuty` (flips the caller's own duty, needs a non-default job, 2 s per-player cooldown). |
| `Config.compat.callbackTimeoutMs` | integer (ms) | Default `5000`. Compat only. How long a legacy callback waits for its responder before resolving empty. |
| `Config.compat.qbxFacade` | boolean | Default `false`. Compat only. Publish the qbx_core and qbx_vehicles export and event surface for stock ox_inventory. Also enabled by convar `kora:qbxFacade` set to `true`. Stays off if a real qbx_core exists. |
| `Config.compat.defaultCommands` | boolean | Default `true`. Compat only. Register the 20 stock qb-core commands; a name another resource already registered is kept. |
| `Config.compat.vehicleSpawnCallbacks` | string | Default `'limited'`. Compat only. Stock vehicle spawn callbacks: `'off'`, `'admin'` (admin permission only) or `'limited'` (any loaded player, validated). |
| `Config.compat.vehicleSpawn.maxDistance` | number (metres) | Default `75.0`. Compat only. Requested spawn coords must be within this distance of the caller's ped (limited mode). |
| `Config.compat.vehicleSpawn.cooldownMs` | integer (ms) | Default `2000`. Compat only. Minimum time between spawn requests per player. |
| `Config.compat.vehicleSpawn.maxLive` | integer | Default `2`. Compat only. Live compat-spawned vehicles per player; the oldest is deleted to make room (minimum 1). |
| `Config.compat.vehicleSpawn.allowModels` | string[] | Default `{}`. Compat only. Extra model names accepted besides `QBCore.Shared.Vehicles`. |
| `Config.compat.vehicleSpawn.grantKeys` | boolean | Default `true`. Compat only. Give the requester keys through kora_vehiclekeys when it is started. |
| `Config.compat.vehicleSpawn.deleteOnDrop` | boolean | Default `true`. Compat only. Delete a player's compat-spawned vehicles when they leave. |
| `Config.compat.deferClientPlayerLoaded` | boolean | Default `false`. False sends `QBCore:Client:OnPlayerLoaded` at login. True waits for the client's `QBCore:Server:OnPlayerLoaded` after spawn (stock timing). Read in modules/player/server.lua and compat. |
| `Config.compat.stress.disabled` | boolean | Default `false`. Compat only. True ignores `hud:server:GainStress` and `RelieveStress`. |
| `Config.compat.stress.whitelistedJobs` | table | Default `{ leo = true, ambulance = true }`. Compat only. Job names or job types that never gain or lose stress. |
| `Config.compat.stress.cooldownMs` | integer (ms) | Default `250`. Compat only. Minimum time between accepted stress events per player. |
| `Config.compat.fireSharedUpdateAtLogin` | boolean | Default `false`. Compat only. Also fire `QBCore:Client:SharedUpdate` at login; off because the registry snapshot already covers it. |

#### Config.locales

Read by modules/locales/client.lua.

| Option | Type | Description |
| --- | --- | --- |
| `Config.locales.defaultKey` | string | Default `'F10'`. Default key for the "Open language selector" key mapping. Players can rebind it in Settings, Key Bindings, FiveM. An empty string means no default key (the `/language` command still works). Read when the resource starts. |

#### Config.vehicleAirControl

Read by modules/vehicleAirControl/client.lua each time the driver enters a vehicle.

| Option | Type | Description |
| --- | --- | --- |
| `Config.vehicleAirControl.disable` | boolean | Default `true`. The driver cannot steer, pitch or roll an airborne vehicle. False restores stock GTA air control. Never blocks controls on the ground. |
| `Config.vehicleAirControl.exemptClasses` | integer[] | Default `{ 8, 13, 14, 15, 16, 21 }` (motorcycles, cycles, boats, helicopters, planes, trains). Vehicle classes (`GetVehicleClass`) that keep air control. Adopted as a list of integers from 0 to 22. |

#### Config.dependencySupervisor

Read by modules/dependencySupervisor/server.lua on every `onResourceStart`. Off by default.

| Option | Type | Description |
| --- | --- | --- |
| `Config.dependencySupervisor.enabled` | boolean | Default `false`. When true, starting a provider restarts its dependents with `restart <name>`. Review ensure order and restart impact first. |
| `Config.dependencySupervisor.map` | table | Default `{ kora_inventory = { 'qb-banking' }, kora_target = { 'qb-banking' }, PolyZone = {}, kora_core = { 'qb-banking' } }`. Provider resource to list of resources restarted after it starts. Only started dependents are restarted. |
| `Config.dependencySupervisor.cooldownMs` | integer (ms) | Default `15000`. A dependent is not restarted again within this time of its own last restart. |

#### Kora.config adoption block

End of config.lua. Runs only if `Kora.config.adopt` exists. It wraps these keys with type and label metadata and then calls `Config = Kora.config.adopt(Config)`. It does not add keys.

| Option | Type | Description |
| --- | --- | --- |
| `Config.compat.jobUpdateEventSource` | enum | Adopted as an enum with options `client`, `server`, `both`, labelled "Legacy job-update event source". |
| `Config.persistence.volatileMetadataKeys` | map of boolean (server scope) | Adopted as a boolean map, labelled "Volatile metadata keys". Not read by any code (see the persistence group). |
| `Config.compat.clientMetadataKeys` | map of boolean (server scope) | Adopted as a boolean map, labelled "Client-writable legacy metadata keys". |
| `Config.dependencySupervisor.map` | map of string lists (server scope) | Adopted as a map of lists of non-empty strings, labelled "Dependency restart map". |
| `Config.vehicleAirControl.disable` | boolean (client scope, live) | Adopted as a live boolean, labelled "Disable vehicle air control". |
| `Config.vehicleAirControl.exemptClasses` | integer list 0 to 22 (client scope, live) | Adopted as a live list of integers, labelled "Air-control exempt vehicle classes". |
| `Config.locales.defaultKey` | string (client scope) | Adopted as a string, labelled "Language selector default key". |

### ConVars read by kora_core

Native modules read two convars. `kora:vehicleIdStateBag` (integer, default 1): `Core.garage.tagVehicle` sets the non-replicated `vehicleid` entity state bag unless it is 0. `kora_locale` (string, default `'en'`): the server-side fallback language in `shared/locale.lua` (a client first asks kora_lib for its language). Files under `compat/` read four more: `kora:qbxFacade` (`'true'` enables the qbx facade, default `'false'`), `sv_maxclients` (integer, default 48, used as `QBCore.Config.MaxPlayers`), `kora_discord` (string, default empty, stock `Config.Server.Discord`) and `mysql_connection_string` (string, parsed to report the database name in `GetDatabaseInfo`). kora_core does not open a database connection from that convar; kora_sql does. The log webhook convars belong to kora_lib, not kora_core.

### ACE objects

Permissions use the `kora_core` prefix and the `group.` fallback. For each level in `god`, `admin`, `mod` (checked in that order, most privileged first) a player holds the level if `IsPlayerAceAllowed(src, 'kora_core.<level>')` or `IsPlayerAceAllowed(src, 'group.<level>')` is true. `user` always matches, so `getPermission` returns `'user'` when nothing else does. Grant them in server.cfg, for example `add_ace group.admin kora_core.admin allow` or `add_principal identifier.license:abc123 kora_core.admin`. `addPermission(src, level)` and `removePermission` run `add_principal` and `remove_principal` for `identifier.<primaryIdentifier>:<id>` against `kora_core.<level>` (the value is not validated, so pass only known levels). Native commands (for example `/jail`, `/unjail`) are gated by the same check with the level given when the command is registered. The `command.<name>` objects are only used by the compat layer: it adds `add_ace kora_core.<level> command.<name> allow` for legacy commands and checks `command.<name>` in the `QBCore:CallCommand` flow. kora_core passes no Discord role mapping, so Discord roles do not grant these levels.

### Reading config from other resources

The `Config` global is private to the kora_core VM. Other resources do not see it; they read values through exports (for example the registry and player exports) or through their own config. The only client-visible effect of config on other resources is through the replicated state bags and events documented in the Events module.

### Common use cases

- Turn on the transaction tax: set `Config.money.tax.enabled = true`, choose `rate` and make sure the provider resource is started.
- Let a custom prison handle jailing: add its resource name to `Config.jail.deferToResources`.
- Give VIP players more character slots by setting `max_characters` in their `users` row rather than raising `Config.identity.maxCharacters`.

### Limits and related APIs

- `Config.persistence.saveOnDrop`, `Config.persistence.volatileMetadataKeys` and `Config.jobs.defaultDuty` are never read. Disconnect saves are always immediate.
- Config is a shared script, so clients can read every value. Do not store secrets in it.
- There is no hot reload except for the keys marked live in the adoption block; restart kora_core otherwise.

### Related guides

- [Events, callbacks and state bags](./events.md)
- [Persistence](./persistence.md)
- [Money](./money.md)
- [Jobs](./jobs.md)
- [Permissions](./permissions.md)
- [Compatibility](./compatibility.md)

## Client

The client reads the same `config.lua` as the server, loaded as a shared script, so all keys and defaults are documented in the server realm of this module. This page lists only the keys that client code reads. Edit the file and restart `kora_core`; clients receive the new file at their next resource start. Do not put secrets in it.

Namespace: `Config` · Source: `config.lua (same shared file as the server realm)`

### Keys read on the client

Key, where it is read, and when.

| Key | Read by | When |
| --- | --- | --- |
| `Config.server.name` | modules/pausemenu/client.lua | Client start. |
| `Config.development.walkSpeed` | modules/development/client.lua | Client start; must be a positive number. |
| `Config.needs.hungerDamage`, `Config.needs.thirstDamage` | modules/needs/client.lua | Client start. |
| `Config.locales.defaultKey` | modules/locales/client.lua | Client start (key mapping). |
| `Config.vehicleAirControl.disable`, `exemptClasses` | modules/vehicleAirControl/client.lua | Each time the driver enters a vehicle. |
| `Config.compat.fireLegacyPlayerDataEvent`, `inventoryPlayerDataEventInterval`, `jobUpdateEventSource` | modules/replication/client.lua | On each snapshot or delta. |
| `Config.inventory.slots`, `Config.inventory.matchInfoOnStack`, `Config.money.types`, `Config.money.default`, `Config.jobs.defaultJob`, `Config.jobs.defaultGrade` | modules/inventory/shared.lua, modules/player/shared.lua | When shared helpers build item and player shapes. |

### Related guides

- [Events, callbacks and state bags](./events.md)

## Option tables and defaults (code-derived)

All options live in `config.lua` (loaded as a shared script, so both realms read the
same values). When kora_lib's `Kora.config` is available the file finishes with
`Kora.config.adopt(Config)`, and a few options carry editor metadata (label,
description, scope); their values and defaults are the ones listed here.

Times are milliseconds unless stated otherwise.

### Config.server

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `name` | string | `'Roleplay Server Name'` | Client-side: replaces the pause-menu header text (`FE_THDR_GTAO`). Empty or non-string leaves the stock title. |

### Config.identity

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `primaryIdentifier` | string | `'license'` | Identifier kind that owns characters (`players.license`, `users.license`), used for ownership checks and runtime permission principals. |
| `citizenIdLength` | integer | `8` | Length of the random alphanumeric part of a generated citizen ID. |
| `citizenIdPrefix` | string | `''` | Prefix prepended to every generated citizen ID. |
| `maxCharacters` | integer | `5` | Default character-slot cap per license. A `users.max_characters` value overrides it per license. |
| `saveDiscord` | boolean | `true` | Store the player's Discord ID on their `users` row when characters are listed or created. |

### Config.persistence

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `interval` | integer | `60000` | Periodic flush interval for dirty player rows. |
| `intervalJitter` | number | `0.10` | Random fraction (plus or minus) applied to each interval so saves do not align. |
| `positionEpsilon` | number | `2.0` | Metres a player must move before the sampled position is saved again. |
| `positionMaxAge` | integer | `300000` | Re-save the position after this long even if the player has not moved. |
| `volatileMetadataKeys` | map | `{}` | Declared (with editor metadata) but not read by the current code. |
| `generatedColumns` | boolean | `false` | Adds virtual `cash`, `bank` and `job_name` columns plus indexes to `players` at boot. See [Database](./persistence.md#generated-columns). |
| `saveOnDrop` | boolean | `true` | Declared but not read by the current code; a drop always triggers an immediate save. |

### Config.money

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `types` | string array | `{ 'cash', 'bank', 'crypto' }` | Valid account names. Any other account is refused with `invalid account`. |
| `default` | map | `{ cash = 500, bank = 5000, crypto = 0 }` | Starting balances for new characters (also `QBCore.Config.Money.MoneyTypes`). |
| `cashType` | string | `'cash'` | Account paid by paychecks and the only account an inventory provider may register as physical cash. |
| `allowNegative` | map | `{}` | Accounts (`[account] = true`) allowed to go below zero, down to `minusLimit`. Empty means no overdraft on any account. |
| `minusLimit` | number | `-50000` | Lowest balance for accounts listed in `allowNegative`. |
| `tax` | table | see below | Optional transaction tax. |

#### Config.money.tax

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `enabled` | boolean | `false` | Master switch. |
| `rate` | number | `0.05` | Fraction of each taxable amount (clamped to 0..1). Tax is floored. |
| `account` | string | `'government'` | Banking account that receives the tax. |
| `provider` | string | `'qb-banking'` | Resource that holds the account. If it is not started, money moves untaxed. |
| `autoCreateAccount` | boolean | `true` | Create `account` through the provider when it does not exist. |
| `exports` | table | `{ add = 'AddMoney', get = 'GetAccount', create = 'CreateJobAccount' }` | Export names called on the provider. |
| `accounts` | map | `{ cash = true, bank = true, crypto = false }` | Accounts that are taxed. If this is not a table, every account is taxed. |
| `actions` | map | `{ add = true, remove = true, transfer = true }` | Operations that are taxed. If this is not a table, every action is taxed. |

How the tax is applied is described on the [Money](./money.md#transaction-tax) page.

### Config.inventory

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `maxWeight` | integer | `120000` | Player carry weight (grams) used by the legacy fallback and reported as `QBCore.Config.Player.MaxWeight`. |
| `slots` | integer | `41` | Player slot count for the legacy fallback (`QBCore.Config.Player.MaxInvSlots`). |
| `matchInfoOnStack` | boolean | `false` | Legacy fallback: stack only when the `info` tables are equal. |
| `warnOnUnhandledOpen` | boolean | `true` | Print a warning when `stashOpen` emits `kora_core:inventory:open` and no UI marks it handled. |
| `provider` | string | `'kora_inventory'` | Resource that receives inventory calls, and the only resource allowed to register physical cash or use the durable inventory column operations. |
| `allowLegacyFallback` | boolean | `true` | When the provider is not started, use the built-in slot engine (with a one-time warning). `false` returns an error instead. |
| `dropTTL` | integer | `1800000` | Lifetime of a legacy in-memory ground drop. |
| `dropSweepInterval` | integer | `300000` | How often expired legacy ground drops are removed. |

### Config.jobs

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `defaultJob` | string | `'unemployed'` | Job given to new characters. `QBCore:ToggleDuty` is refused for players holding this job. |
| `defaultGrade` | integer | `1` | One-based grade given with `defaultJob`. |
| `defaultDuty` | boolean | `true` | Declared but not read; initial duty comes from each job's `defaultDuty` field. |
| `paycheckInterval` | integer | `300000` | Paycheck tick interval (also returned by `QBCore.Functions.PaycheckInterval()`). |

### Config.dispatch

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `legacyEvents` | boolean | `true` | `alert` also fires `police:server:policeAlert`, `police:client:policeAlert` and `hospital:client:ambulanceAlert` for `police`, `ambulance` and `ems` alerts. |

### Config.needs

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `tickInterval` | integer | `60000` | Hunger/thirst decay interval. |
| `hungerDecay` | number | `1` | Hunger removed per tick (clamped to 0..100). |
| `thirstDecay` | number | `1` | Thirst removed per tick (clamped to 0..100). |
| `hungerDamage` | number | `5` | Client ped damage applied whenever a replicated hunger update is 0. `0` disables it. |
| `thirstDamage` | number | `5` | Client ped damage applied whenever a replicated thirst update is 0. `0` disables it. |

### Config.development

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `walkSpeed` | number | `1.75` | Ped move-rate override while development mode is active. Must be positive (asserted on the client). |

### Config.jail

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `deferToResources` | string array | `{ 'xt-prison', 'qbx_prison' }` | If any of these is started, `jailPlayer` fires `kora_core:server:onJailRequest` instead of jailing. |
| `coords` | vector4 | `vector4(1651.86, 2570.13, 45.56, 22.0)` | Built-in jail teleport point and centre of the 30 m containment sphere. |

### Config.garage

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `defaultFuel` | number | `100` | Fuel for `createVehicle` when `extra.fuel` is not given. |
| `defaultEngineHealth` | number | `1000` | Engine health default for `createVehicle`. |
| `defaultBodyHealth` | number | `1000` | Body health default for `createVehicle`. |
| `spawnNetworkIdTimeout` | integer | `1000` | How long `spawnVehicle` waits for a network ID before deleting the entity and failing. |

### Config.consumables

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `enabled` | boolean | `true` | Register the kora_inventory `usingItem` hook that applies item `effect` tables. |

### Config.compat

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `fireLegacyPlayerDataEvent` | boolean | `true` | Client: re-fire `QBCore:Player:SetPlayerData` locally after snapshots and deltas. |
| `inventoryPlayerDataEventInterval` | integer | `250` | Client: delay for the legacy full-PlayerData event when a delta changed only `items`. `0` fires on every delta. |
| `jobUpdateEventSource` | enum | `'client'` | Which realm sends `QBCore:Client:OnJobUpdate`/`OnGangUpdate` and the job/gang `OnPlayerUpdated`: `'client'` (derived locally from the mirror), `'server'` (sent by the server), or `'both'` (duplicates possible). |
| `coreObjectExport` | boolean | `true` | Server: publish `GetCoreObject`, `GetShared*` and every `QBCore.Functions` entry as `qb-core` exports. |
| `warnOnUnknownRoot` | boolean | `true` | Warn when legacy `SetPlayerData` writes a root key that has no database column. |
| `clientMetadataKeys` | map | `{ hunger = true, thirst = true, stress = true }` | Allow-list for the client-triggerable `QBCore:Server:SetMetaData` event. hunger/thirst/stress must be finite numbers and are clamped to 0..100. Never add money, jail, death, licence or record keys. |
| `toggleDutyEvent` | boolean | `true` | Handle the client `QBCore:ToggleDuty` event (2 s per-player cooldown). |
| `callbackTimeoutMs` | integer | `5000` | Legacy callback timeout: unanswered await-style `TriggerCallback` calls resolve `nil`, and legacy handlers that never reply are answered empty. |
| `qbxFacade` | boolean | `false` | Enable the qbx_core/qbx_vehicles export facade. The convar `kora:qbxFacade` also enables it. See [qbx facade](../qbx-facade.md). |
| `defaultCommands` | boolean | `true` | Register the 20 stock qb-core commands. See [Default commands](../default-commands.md). |
| `vehicleSpawnCallbacks` | string | `'limited'` | `'off'`, `'admin'` or `'limited'` mode for `QBCore:Server:SpawnVehicle`/`CreateVehicle`. See [Vehicle spawn](../vehicle-spawn.md). |
| `vehicleSpawn` | table | see below | Limits for the vehicle-spawn callbacks. |
| `deferClientPlayerLoaded` | boolean | `false` | Send `QBCore:Client:OnPlayerLoaded` only when the client fires `QBCore:Server:OnPlayerLoaded` (stock timing) instead of at login. Do not enable if any login path skips that event. |
| `stress` | table | see below | Settings for `hud:server:GainStress`/`RelieveStress`. |
| `fireSharedUpdateAtLogin` | boolean | `false` | Send `QBCore:Client:SharedUpdate` with `QBCore.Shared` to each player at login. |

#### Config.compat.vehicleSpawn

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `maxDistance` | number | `75.0` | `limited` mode: maximum distance between the caller and the spawn point. |
| `cooldownMs` | integer | `2000` | `limited` mode: minimum time between two requests from one player. |
| `maxLive` | integer | `2` | `limited` mode: callback-spawned vehicles kept per player; the oldest is deleted. |
| `allowModels` | string array | `{}` | `limited` mode: extra model names allowed besides the vehicles registry. |
| `grantKeys` | boolean | `true` | Give keys through `kora_vehiclekeys` when it is started. |
| `deleteOnDrop` | boolean | `true` | Delete a player's tracked callback-spawned vehicles when they disconnect. |

#### Config.compat.stress

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `disabled` | boolean | `false` | Ignore the stress events entirely. |
| `whitelistedJobs` | map | `{ leo = true, ambulance = true }` | Job names or job types that never gain or lose stress through these events. |
| `cooldownMs` | integer | `250` | Per-player cooldown between stress events. |

The stress events are also ignored while a real `qb-hud` resource is started.

### Config.locales

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `defaultKey` | string | `'F10'` | Default key for the "Open language selector" key mapping. Empty means no default key; `/language` still works. |

### Config.vehicleAirControl

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `disable` | boolean | `true` | Block steering, pitch and roll controls (controls 59 to 64) for the driver of a non-exempt vehicle while it is airborne. Grounded vehicles are never affected. |
| `exemptClasses` | integer array | `{ 8, 13, 14, 15, 16, 21 }` | GTA vehicle classes that keep air control (motorcycles, cycles, boats, helicopters, planes, trains). |

Both values are read when the driver enters a vehicle, so a change applies from the next entry.

### Config.replication

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `resyncRateLimit` | integer | `5000` | Minimum time between two full PlayerData snapshots sent to one player on resync requests. |
| `snapshotCoalesceMs` | integer | `250` | After a registry snapshot is sent to a player, further `kora_core:registry:requestSnapshot` requests within this window collapse into one follow-up snapshot. `0` disables coalescing. |

### Config.dependencySupervisor

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `enabled` | boolean | `false` | Restart dependent resources when a provider resource (re)starts. |
| `map` | map of string arrays | `{ kora_inventory = { 'qb-banking' }, kora_target = { 'qb-banking' }, PolyZone = {}, kora_core = { 'qb-banking' } }` | Provider resource name to the dependents to `restart`. |
| `cooldownMs` | integer | `15000` | Minimum time between two restarts of the same dependent. |

Only dependents that are already `started` are restarted, and a resource is never
restarted by its own start. Every restart or skip is printed.

```lua
Config.dependencySupervisor = {
    enabled = true,
    map = {
        kora_inventory = { 'qb-banking' },
    },
    cooldownMs = 15000,
}
```

### Convars

| Convar | Read by | Description |
| --- | --- | --- |
| `kora:qbxFacade` | server | `true` enables the qbx facade like `Config.compat.qbxFacade`. |
| `kora:vehicleIdStateBag` | server | `0` disables the server-only `vehicleid` entity state bag set by `tagVehicle` (default `1`). |
| `kora_discord` | shared | Value of `QBCore.Config.Server.Discord`, appended to legacy kick messages. |
| `kora_locale` | shared | Default language for the legacy `Locale` class (`shared/locale.lua`) when kora_lib cannot supply one. |
| `mysql_connection_string` | server | Parsed (never logged) by `QBCore.Functions.GetDatabaseInfo`. |
| `kora_lib_log_webhook`, `kora_core_log_webhook` | server (kora_lib) | Discord webhook for `logEvent`; the kora_core name is a fallback read by kora_lib. |

Language choices for the `/language` selector come from kora_lib's locale settings.
