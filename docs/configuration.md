---
title: Configuration
sidebar_position: 2
---

# Configuration

All options live in `config.lua` (loaded as a shared script, so both realms read the
same values). When kora_lib's `Kora.config` is available the file finishes with
`Kora.config.adopt(Config)`, and a few options carry editor metadata (label,
description, scope); their values and defaults are the ones listed here.

Times are milliseconds unless stated otherwise.

## Config.server

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `name` | string | `'Roleplay Server Name'` | Client-side: replaces the pause-menu header text (`FE_THDR_GTAO`). Empty or non-string leaves the stock title. |

## Config.identity

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `primaryIdentifier` | string | `'license'` | Identifier kind that owns characters (`players.license`, `users.license`), used for ownership checks and runtime permission principals. |
| `citizenIdLength` | integer | `8` | Length of the random alphanumeric part of a generated citizen ID. |
| `citizenIdPrefix` | string | `''` | Prefix prepended to every generated citizen ID. |
| `maxCharacters` | integer | `5` | Default character-slot cap per license. A `users.max_characters` value overrides it per license. |
| `saveDiscord` | boolean | `true` | Store the player's Discord ID on their `users` row when characters are listed or created. |

## Config.persistence

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `interval` | integer | `60000` | Periodic flush interval for dirty player rows. |
| `intervalJitter` | number | `0.10` | Random fraction (plus or minus) applied to each interval so saves do not align. |
| `positionEpsilon` | number | `2.0` | Metres a player must move before the sampled position is saved again. |
| `positionMaxAge` | integer | `300000` | Re-save the position after this long even if the player has not moved. |
| `volatileMetadataKeys` | map | `{}` | Declared (with editor metadata) but not read by the current code. |
| `generatedColumns` | boolean | `false` | Adds virtual `cash`, `bank` and `job_name` columns plus indexes to `players` at boot. See [Database](./database.md#generated-columns). |
| `saveOnDrop` | boolean | `true` | Declared but not read by the current code; a drop always triggers an immediate save. |

## Config.money

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `types` | string array | `{ 'cash', 'bank', 'crypto' }` | Valid account names. Any other account is refused with `invalid account`. |
| `default` | map | `{ cash = 500, bank = 5000, crypto = 0 }` | Starting balances for new characters (also `QBCore.Config.Money.MoneyTypes`). |
| `cashType` | string | `'cash'` | Account paid by paychecks and the only account an inventory provider may register as physical cash. |
| `allowNegative` | map | `{}` | Accounts (`[account] = true`) allowed to go below zero, down to `minusLimit`. Empty means no overdraft on any account. |
| `minusLimit` | number | `-50000` | Lowest balance for accounts listed in `allowNegative`. |
| `tax` | table | see below | Optional transaction tax. |

### Config.money.tax

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

How the tax is applied is described on the [Money](./features/money.md#transaction-tax) page.

## Config.inventory

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

## Config.jobs

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `defaultJob` | string | `'unemployed'` | Job given to new characters. `QBCore:ToggleDuty` is refused for players holding this job. |
| `defaultGrade` | integer | `1` | One-based grade given with `defaultJob`. |
| `defaultDuty` | boolean | `true` | Declared but not read; initial duty comes from each job's `defaultDuty` field. |
| `paycheckInterval` | integer | `300000` | Paycheck tick interval (also returned by `QBCore.Functions.PaycheckInterval()`). |

## Config.dispatch

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `legacyEvents` | boolean | `true` | `alert` also fires `police:server:policeAlert`, `police:client:policeAlert` and `hospital:client:ambulanceAlert` for `police`, `ambulance` and `ems` alerts. |

## Config.needs

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `tickInterval` | integer | `60000` | Hunger/thirst decay interval. |
| `hungerDecay` | number | `1` | Hunger removed per tick (clamped to 0..100). |
| `thirstDecay` | number | `1` | Thirst removed per tick (clamped to 0..100). |
| `hungerDamage` | number | `5` | Client ped damage applied whenever a replicated hunger update is 0. `0` disables it. |
| `thirstDamage` | number | `5` | Client ped damage applied whenever a replicated thirst update is 0. `0` disables it. |

## Config.development

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `walkSpeed` | number | `1.75` | Ped move-rate override while development mode is active. Must be positive (asserted on the client). |

## Config.jail

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `deferToResources` | string array | `{ 'xt-prison', 'qbx_prison' }` | If any of these is started, `jailPlayer` fires `kora_core:server:onJailRequest` instead of jailing. |
| `coords` | vector4 | `vector4(1651.86, 2570.13, 45.56, 22.0)` | Built-in jail teleport point and centre of the 30 m containment sphere. |

## Config.garage

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `defaultFuel` | number | `100` | Fuel for `createVehicle` when `extra.fuel` is not given. |
| `defaultEngineHealth` | number | `1000` | Engine health default for `createVehicle`. |
| `defaultBodyHealth` | number | `1000` | Body health default for `createVehicle`. |
| `spawnNetworkIdTimeout` | integer | `1000` | How long `spawnVehicle` waits for a network ID before deleting the entity and failing. |

## Config.consumables

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `enabled` | boolean | `true` | Register the kora_inventory `usingItem` hook that applies item `effect` tables. |

## Config.compat

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
| `qbxFacade` | boolean | `false` | Enable the qbx_core/qbx_vehicles export facade. The convar `kora:qbxFacade` also enables it. See [qbx facade](./qbx-facade.md). |
| `defaultCommands` | boolean | `true` | Register the 20 stock qb-core commands. See [Default commands](./default-commands.md). |
| `vehicleSpawnCallbacks` | string | `'limited'` | `'off'`, `'admin'` or `'limited'` mode for `QBCore:Server:SpawnVehicle`/`CreateVehicle`. See [Vehicle spawn](./vehicle-spawn.md). |
| `vehicleSpawn` | table | see below | Limits for the vehicle-spawn callbacks. |
| `deferClientPlayerLoaded` | boolean | `false` | Send `QBCore:Client:OnPlayerLoaded` only when the client fires `QBCore:Server:OnPlayerLoaded` (stock timing) instead of at login. Do not enable if any login path skips that event. |
| `stress` | table | see below | Settings for `hud:server:GainStress`/`RelieveStress`. |
| `fireSharedUpdateAtLogin` | boolean | `false` | Send `QBCore:Client:SharedUpdate` with `QBCore.Shared` to each player at login. |

### Config.compat.vehicleSpawn

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `maxDistance` | number | `75.0` | `limited` mode: maximum distance between the caller and the spawn point. |
| `cooldownMs` | integer | `2000` | `limited` mode: minimum time between two requests from one player. |
| `maxLive` | integer | `2` | `limited` mode: callback-spawned vehicles kept per player; the oldest is deleted. |
| `allowModels` | string array | `{}` | `limited` mode: extra model names allowed besides the vehicles registry. |
| `grantKeys` | boolean | `true` | Give keys through `kora_vehiclekeys` when it is started. |
| `deleteOnDrop` | boolean | `true` | Delete a player's tracked callback-spawned vehicles when they disconnect. |

### Config.compat.stress

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `disabled` | boolean | `false` | Ignore the stress events entirely. |
| `whitelistedJobs` | map | `{ leo = true, ambulance = true }` | Job names or job types that never gain or lose stress through these events. |
| `cooldownMs` | integer | `250` | Per-player cooldown between stress events. |

The stress events are also ignored while a real `qb-hud` resource is started.

## Config.locales

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `defaultKey` | string | `'F10'` | Default key for the "Open language selector" key mapping. Empty means no default key; `/language` still works. |

## Config.vehicleAirControl

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `disable` | boolean | `true` | Block steering, pitch and roll controls (controls 59 to 64) for the driver of a non-exempt vehicle while it is airborne. Grounded vehicles are never affected. |
| `exemptClasses` | integer array | `{ 8, 13, 14, 15, 16, 21 }` | GTA vehicle classes that keep air control (motorcycles, cycles, boats, helicopters, planes, trains). |

Both values are read when the driver enters a vehicle, so a change applies from the next entry.

## Config.replication

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `resyncRateLimit` | integer | `5000` | Minimum time between two full PlayerData snapshots sent to one player on resync requests. |
| `snapshotCoalesceMs` | integer | `250` | After a registry snapshot is sent to a player, further `kora_core:registry:requestSnapshot` requests within this window collapse into one follow-up snapshot. `0` disables coalescing. |

## Config.dependencySupervisor

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

## Convars

| Convar | Read by | Description |
| --- | --- | --- |
| `kora:qbxFacade` | server | `true` enables the qbx facade like `Config.compat.qbxFacade`. |
| `kora:vehicleIdStateBag` | server | `0` disables the server-only `vehicleid` entity state bag set by `tagVehicle` (default `1`). |
| `kora_discord` | shared | Value of `QBCore.Config.Server.Discord`, appended to legacy kick messages. |
| `kora_locale` | shared | Default language for the legacy `Locale` class (`shared/locale.lua`) when kora_lib cannot supply one. |
| `mysql_connection_string` | server | Parsed (never logged) by `QBCore.Functions.GetDatabaseInfo`. |
| `kora_lib_log_webhook`, `kora_core_log_webhook` | server (kora_lib) | Discord webhook for `logEvent`; the kora_core name is a fallback read by kora_lib. |

Language choices for the `/language` selector come from kora_lib's locale settings.
