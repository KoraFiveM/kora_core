---
title: "Compatibility helper exports"
sidebar_position: 17
---


# Compatibility helper exports

## Server

The compatibility layer stores its conversion helpers on `Core.compat`, and `build/finalise.lua` exports every public function it finds, so they are real `exports.kora_core` calls. They convert between the native model (one-based grades, heading `h`, sparse metadata) and the legacy qb-core model (zero-based grades, heading `w`, fully populated metadata), and they keep the legacy Player wrappers in sync. Most scripts never need them: use the native exports instead.

Namespace: `exports.kora_core` · Source: `compat/shared/coreobject.lua, compat/server/qb-core.lua`

### How it works

Everything here is a view over native data. Nothing is persisted and no helper changes a player, except that `createCallback` registers a callback. All helpers return copies, so the result is safe to keep and to pass across resources.

### Terms used on this page

| Term | Meaning |
| --- | --- |
| Legacy view | The qb-core shaped copy of a native table: zero-based `grade.level`, `position.w`, filled `metadata` and `charinfo`. |
| Derived defaults | `bloodtype`, `fingerprint`, `walletid`, `phonedata.SerialNumber`, `account` and `phone` computed from the citizenid so they are stable per character and never stored. |

### Functions

Server realm helpers. The conversion helpers also exist on the client with the same signatures.

#### `exports.kora_core:toLegacyGradeLevel(level)`

Converts a native one-based grade level to the zero-based number legacy qb-core scripts expect: `max((tonumber(level) or 1) - 1, 0)`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `level` | number \| string | Native grade level. A value that is not a number counts as 1. |

**Returns**

- **level** — integer, 0 or more.

**Example**

```lua
local legacyLevel = exports.kora_core:toLegacyGradeLevel(3)
print(legacyLevel)
```

**Representative console output**

```text
2
```

#### `exports.kora_core:fromLegacyGradeLevel(level)`

Converts a zero-based legacy grade level to the native one-based level: `max(floor(tonumber(level) or 0), 0) + 1`. Negative and non-numeric input counts as 0.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `level` | number \| string | Legacy grade level (zero-based). |

**Returns**

- **level** — integer, 1 or more.

**Example**

```lua
local nativeGrade = exports.kora_core:fromLegacyGradeLevel(0)
exports.kora_core:setJob(source, 'police', nativeGrade)
```

**Representative console output**

```text
setJob receives grade 1.
```

#### `exports.kora_core:toLegacyJobOrGang(record, kind?)`

Returns a copy of a native `PlayerData.job` or `PlayerData.gang` record in the legacy shape: `grade.level` becomes zero-based, and `grade.isboss` (and, for jobs, `grade.payment`) is mirrored onto the grade table, taken from the record or from the registry definition when the record lacks it. Existing values on the grade are never overwritten.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `record` | table | Native job or gang record. A value that is not a table is returned unchanged. |
| `kind?` | string | `'jobs'` or `'gangs'`. Selects the registry used to fill `grade.payment` / `grade.isboss` and whether payment is filled at all (jobs only). Without it only the level is converted. |

**Returns**

- **record** — a new table with the legacy grade; the input is not modified.
- **input** — returned as is when `record` is not a table.

**Example**

```lua
local job = exports.kora_core:getJob(source)
local legacyJob = exports.kora_core:toLegacyJobOrGang(job, 'jobs')
print(legacyJob.grade.level, legacyJob.grade.payment)
```

**Representative console output**

```text
1	450
```

#### `exports.kora_core:toLegacyPlayerData(playerData)`

Builds a legacy-shaped PlayerData table from a native one: job and gang through `toLegacyJobOrGang`, `metadata` and `charinfo` filled with the stock qb-core defaults, `position` given both `w` and `h`, and `optin` defaulting to `true`. The table is a plain raw-keyed copy so it crosses the export boundary intact. This is the export `kora_target` calls on the client for its job, gang and citizenid filters.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `playerData` | table | Native PlayerData (for example from `getPlayer`). A value that is not a table is returned unchanged. |

**Returns**

- **playerData** — the legacy-shaped copy. Nothing is persisted; the derived defaults exist only in this view.

**Example**

```lua
local nativeData = exports.kora_core:getPlayer(source)
local legacyData = exports.kora_core:toLegacyPlayerData(nativeData)
print(legacyData.job.grade.level, legacyData.metadata.bloodtype)
```

**Representative console output**

```text
0	O+
```

#### `exports.kora_core:fromLegacyPlayerData(playerData)`

Reverses the layout changes of `toLegacyPlayerData` on a deep copy: `position.w` is folded into `position.h` (and `w` removed), and `job.grade.level` / `gang.grade.level` become one-based again.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `playerData` | table | Legacy-shaped PlayerData. A value that is not a table is returned unchanged. |

**Returns**

- **playerData** — a deep copy in the native layout. It does not restore keys that were only added to the legacy view.

**Example**

```lua
local nativeData = exports.kora_core:fromLegacyPlayerData(legacyData)
print(nativeData.job.grade.level)
```

**Representative console output**

```text
1
```

#### `exports.kora_core:fillMetadataDefaults(metadata, citizenid)`

Returns a copy of a metadata table with every missing key filled from `QBCore.Config.Player.PlayerDefaults.metadata`. Existing values are never overwritten. Keys stock qb-core randomises (`bloodtype`, `fingerprint`, `walletid`, `phonedata.SerialNumber`) are derived deterministically from the citizenid, so they are stable per character and never written back.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `metadata` | table | Metadata to complete. A value that is not a table is returned unchanged. |
| `citizenid` | string | Seed for the derived identity values. |

**Returns**

- **metadata** — the completed copy.

**Example**

```lua
local filled = exports.kora_core:fillMetadataDefaults({ hunger = 80 }, 'ABC12345')
print(filled.hunger, filled.thirst, filled.walletid)
```

**Representative console output**

```text
80	100	QB-48201937
```

#### `exports.kora_core:fillCharinfoDefaults(charinfo, citizenid)`

Same as `fillMetadataDefaults` for `charinfo`, using `QBCore.Config.Player.PlayerDefaults.charinfo` (`firstname`, `lastname`, `birthdate`, `gender`, `nationality`, plus derived `phone` and `account`).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `charinfo` | table | Character info to complete. A value that is not a table is returned unchanged. |
| `citizenid` | string | Seed for the derived `phone` and `account`. |

**Returns**

- **charinfo** — the completed copy.

**Example**

```lua
local filled = exports.kora_core:fillCharinfoDefaults({ firstname = 'Ana' }, 'ABC12345')
print(filled.firstname, filled.nationality)
```

**Representative console output**

```text
Ana	USA
```

#### `exports.kora_core:legacyPosition(position)`

Returns a copy of a position table that carries both heading keys: Kora stores `h`, stock qb-core uses `w`. Whichever is missing is copied from the other.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `position` | table | `{ x, y, z, h }` or `{ x, y, z, w }`. A value that is not a table is returned unchanged. |

**Returns**

- **position** — the copy with `w` and `h` both set.

**Example**

```lua
local position = exports.kora_core:legacyPosition({ x = 195.17, y = -933.77, z = 30.69, h = 144.0 })
print(position.w)
```

**Representative console output**

```text
144.0
```

#### `exports.kora_core:canonicalSharedNamespace(namespace)`

Maps a case-insensitive shared namespace name to the PascalCase key used on `QBCore.Shared`. This is how `GetShared('items')` finds `Items`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `namespace` | string | One of `items`, `vehicles`, `jobs`, `gangs`, `weapons`, `locations`, `vehiclehashes`, `starteritems` in any letter case. A value that is not a string is returned unchanged. |

**Returns**

- **name** — `Items`, `Vehicles`, `Jobs`, `Gangs`, `Weapons`, `Locations`, `VehicleHashes` or `StarterItems`.
- **nil** — the string is not one of those names.

**Example**

```lua
print(exports.kora_core:canonicalSharedNamespace('vehiclehashes'))
print(exports.kora_core:canonicalSharedNamespace('houses'))
```

**Representative console output**

```text
VehicleHashes
nil
```

#### `exports.kora_core:populateLegacyConfig()`

Rebuilds the whole `QBCore.Config` table (`MaxPlayers`, `DefaultSpawn`, `Money`, `Player` with `PlayerDefaults`, `Server`, `Commands`, `Notify`) from `Config.*` and the `sv_maxclients` / `kora_discord` convars. It runs once at load in each realm. Calling it again resets runtime changes such as the closed flag set by `/closeserver`, so treat it as internal.

**Parameters**



**Returns**

- **No return value.**

**Example**

```lua
-- Normally never needed: kora_core runs it at load.
exports.kora_core:populateLegacyConfig()
```

**Representative console output**

```text
QBCore.Config is rebuilt; QBCore.Config.Server.Closed is false again.
```

#### `exports.kora_core:buildLoadedPlayer(src)`

Rebuilds the legacy Player wrapper for a logged-in player and stores it in `QBCore.Players[src]` and `QBCore.PlayersByCitizenId`, replacing any older wrapper. It runs automatically on `kora_core:server:playerLoaded`. The value you receive over the export boundary is a copy whose methods are function references.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |

**Returns**

- **player** — the wrapper `{ PlayerData, Functions, Offline = false }`.
- **nil** — the player is not logged in (the old wrapper is still forgotten).

**Example**

```lua
local player = exports.kora_core:buildLoadedPlayer(source)
if player then print(player.PlayerData.citizenid) end
```

**Representative console output**

```text
ABC12345
```

#### `exports.kora_core:buildOfflinePlayer(data)`

Builds the legacy wrapper for an offline character from a PlayerData snapshot (deep copied, then converted with `toLegacyPlayerData`). Its methods edit the local snapshot only, `Offline` is `true`, and `Save` writes through the offline-player path.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `data` | table | Native PlayerData, for example from `getOfflinePlayerData`. |

**Returns**

- **player** — the offline wrapper `{ PlayerData, Functions, Offline = true }`.

**Example**

```lua
local data = exports.kora_core:getOfflinePlayerData('ABC12345')
if data then
    local offlinePlayer = exports.kora_core:buildOfflinePlayer(data)
    print(offlinePlayer.Offline)
end
```

**Representative console output**

```text
true
```

#### `exports.kora_core:onPlayerDataChanged(src, path, value)`

Hook that `setPath` and the money module call after every successful write so `QBCore.Players[src].PlayerData` stays in sync. It writes `value` (deep copied and converted for job, gang, metadata, charinfo and position roots) into the legacy view at `path` and refreshes the mirrored cash balance. Calling it yourself changes only the legacy view, never the real data or the database.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `path` | table | Path array as passed to `setPath`, for example `{ 'job' }` or `{ 'money', 'bank' }`. |
| `value` | any | The new value at that path. |

**Returns**

- **nil** — No return value. Does nothing when there is no legacy wrapper for `src`.

**Example**

```lua
-- internal: called by setPath after a successful write
exports.kora_core:onPlayerDataChanged(source, { 'metadata', 'hunger' }, 90)
```

**Representative console output**

```text
QBCore.Players[source].PlayerData.metadata.hunger is 90 in the legacy view only.
```

#### `exports.kora_core:createCallback(name, handler)`

Registers a server callback in the legacy style. The handler receives `(src, cb, ...)` and answers by calling `cb(...)`; if it never does, the request resolves empty after `Config.compat.callbackTimeoutMs` (5000 ms). The callback is available both to `Kora.callback.trigger` and to the legacy `QBCore:Server:TriggerCallback` wire.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Callback name. Registering the same name again replaces the handler. |
| `handler` | function | `function(src, cb, ...)`. Call `cb` with the values to return. |

**Returns**

- **No return value.**

**Example**

```lua
exports.kora_core:createCallback('myshop:getPrices', function(src, cb)
    cb({ bread = 5, water = 3 })
end)
```

**Representative console output**

```text
The callback answers with the price table, or with no values after 5000 ms if cb is never called.
```

### Limits and related APIs

Use `getPlayer`, `setJob` and `registerShared` for new code. See the Compatibility module for every converted qb-core call.

### Related guides

- [Compatibility](./compatibility.md)
- [Jobs, gangs, duty, paycheck and dispatch](./jobs.md)
- [Player data and lifecycle](./player.md)

## Client

The conversion helpers are shared code, so the client realm exports the same ten functions with the same behaviour. `kora_target` uses `toLegacyPlayerData` for its job, gang and citizenid filters.

Namespace: `exports.kora_core` · Source: `compat/shared/coreobject.lua`

### Functions

Client realm helpers (identical to the server versions listed above).

#### `exports.kora_core:toLegacyGradeLevel(level)`

Converts a native one-based grade level to the zero-based number legacy qb-core scripts expect: `max((tonumber(level) or 1) - 1, 0)`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `level` | number \| string | Native grade level. A value that is not a number counts as 1. |

**Returns**

- **level** — integer, 0 or more.

**Example**

```lua
local legacyLevel = exports.kora_core:toLegacyGradeLevel(3)
print(legacyLevel)
```

**Representative console output**

```text
2
```

#### `exports.kora_core:fromLegacyGradeLevel(level)`

Converts a zero-based legacy grade level to the native one-based level: `max(floor(tonumber(level) or 0), 0) + 1`. Negative and non-numeric input counts as 0.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `level` | number \| string | Legacy grade level (zero-based). |

**Returns**

- **level** — integer, 1 or more.

**Example**

```lua
local nativeGrade = exports.kora_core:fromLegacyGradeLevel(0)
exports.kora_core:setJob(source, 'police', nativeGrade)
```

**Representative console output**

```text
setJob receives grade 1.
```

#### `exports.kora_core:toLegacyJobOrGang(record, kind?)`

Returns a copy of a native `PlayerData.job` or `PlayerData.gang` record in the legacy shape: `grade.level` becomes zero-based, and `grade.isboss` (and, for jobs, `grade.payment`) is mirrored onto the grade table, taken from the record or from the registry definition when the record lacks it. Existing values on the grade are never overwritten.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `record` | table | Native job or gang record. A value that is not a table is returned unchanged. |
| `kind?` | string | `'jobs'` or `'gangs'`. Selects the registry used to fill `grade.payment` / `grade.isboss` and whether payment is filled at all (jobs only). Without it only the level is converted. |

**Returns**

- **record** — a new table with the legacy grade; the input is not modified.
- **input** — returned as is when `record` is not a table.

**Example**

```lua
local job = exports.kora_core:getJob(source)
local legacyJob = exports.kora_core:toLegacyJobOrGang(job, 'jobs')
print(legacyJob.grade.level, legacyJob.grade.payment)
```

**Representative console output**

```text
1	450
```

#### `exports.kora_core:toLegacyPlayerData(playerData)`

Builds a legacy-shaped PlayerData table from a native one: job and gang through `toLegacyJobOrGang`, `metadata` and `charinfo` filled with the stock qb-core defaults, `position` given both `w` and `h`, and `optin` defaulting to `true`. The table is a plain raw-keyed copy so it crosses the export boundary intact. This is the export `kora_target` calls on the client for its job, gang and citizenid filters.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `playerData` | table | Native PlayerData (for example from `getPlayer`). A value that is not a table is returned unchanged. |

**Returns**

- **playerData** — the legacy-shaped copy. Nothing is persisted; the derived defaults exist only in this view.

**Example**

```lua
local nativeData = exports.kora_core:getPlayer(source)
local legacyData = exports.kora_core:toLegacyPlayerData(nativeData)
print(legacyData.job.grade.level, legacyData.metadata.bloodtype)
```

**Representative console output**

```text
0	O+
```

#### `exports.kora_core:fromLegacyPlayerData(playerData)`

Reverses the layout changes of `toLegacyPlayerData` on a deep copy: `position.w` is folded into `position.h` (and `w` removed), and `job.grade.level` / `gang.grade.level` become one-based again.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `playerData` | table | Legacy-shaped PlayerData. A value that is not a table is returned unchanged. |

**Returns**

- **playerData** — a deep copy in the native layout. It does not restore keys that were only added to the legacy view.

**Example**

```lua
local nativeData = exports.kora_core:fromLegacyPlayerData(legacyData)
print(nativeData.job.grade.level)
```

**Representative console output**

```text
1
```

#### `exports.kora_core:fillMetadataDefaults(metadata, citizenid)`

Returns a copy of a metadata table with every missing key filled from `QBCore.Config.Player.PlayerDefaults.metadata`. Existing values are never overwritten. Keys stock qb-core randomises (`bloodtype`, `fingerprint`, `walletid`, `phonedata.SerialNumber`) are derived deterministically from the citizenid, so they are stable per character and never written back.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `metadata` | table | Metadata to complete. A value that is not a table is returned unchanged. |
| `citizenid` | string | Seed for the derived identity values. |

**Returns**

- **metadata** — the completed copy.

**Example**

```lua
local filled = exports.kora_core:fillMetadataDefaults({ hunger = 80 }, 'ABC12345')
print(filled.hunger, filled.thirst, filled.walletid)
```

**Representative console output**

```text
80	100	QB-48201937
```

#### `exports.kora_core:fillCharinfoDefaults(charinfo, citizenid)`

Same as `fillMetadataDefaults` for `charinfo`, using `QBCore.Config.Player.PlayerDefaults.charinfo` (`firstname`, `lastname`, `birthdate`, `gender`, `nationality`, plus derived `phone` and `account`).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `charinfo` | table | Character info to complete. A value that is not a table is returned unchanged. |
| `citizenid` | string | Seed for the derived `phone` and `account`. |

**Returns**

- **charinfo** — the completed copy.

**Example**

```lua
local filled = exports.kora_core:fillCharinfoDefaults({ firstname = 'Ana' }, 'ABC12345')
print(filled.firstname, filled.nationality)
```

**Representative console output**

```text
Ana	USA
```

#### `exports.kora_core:legacyPosition(position)`

Returns a copy of a position table that carries both heading keys: Kora stores `h`, stock qb-core uses `w`. Whichever is missing is copied from the other.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `position` | table | `{ x, y, z, h }` or `{ x, y, z, w }`. A value that is not a table is returned unchanged. |

**Returns**

- **position** — the copy with `w` and `h` both set.

**Example**

```lua
local position = exports.kora_core:legacyPosition({ x = 195.17, y = -933.77, z = 30.69, h = 144.0 })
print(position.w)
```

**Representative console output**

```text
144.0
```

#### `exports.kora_core:canonicalSharedNamespace(namespace)`

Maps a case-insensitive shared namespace name to the PascalCase key used on `QBCore.Shared`. This is how `GetShared('items')` finds `Items`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `namespace` | string | One of `items`, `vehicles`, `jobs`, `gangs`, `weapons`, `locations`, `vehiclehashes`, `starteritems` in any letter case. A value that is not a string is returned unchanged. |

**Returns**

- **name** — `Items`, `Vehicles`, `Jobs`, `Gangs`, `Weapons`, `Locations`, `VehicleHashes` or `StarterItems`.
- **nil** — the string is not one of those names.

**Example**

```lua
print(exports.kora_core:canonicalSharedNamespace('vehiclehashes'))
print(exports.kora_core:canonicalSharedNamespace('houses'))
```

**Representative console output**

```text
VehicleHashes
nil
```

#### `exports.kora_core:populateLegacyConfig()`

Rebuilds the whole `QBCore.Config` table (`MaxPlayers`, `DefaultSpawn`, `Money`, `Player` with `PlayerDefaults`, `Server`, `Commands`, `Notify`) from `Config.*` and the `sv_maxclients` / `kora_discord` convars. It runs once at load in each realm. Calling it again resets runtime changes such as the closed flag set by `/closeserver`, so treat it as internal.

**Parameters**



**Returns**

- **No return value.**

**Example**

```lua
-- Normally never needed: kora_core runs it at load.
exports.kora_core:populateLegacyConfig()
```

**Representative console output**

```text
QBCore.Config is rebuilt; QBCore.Config.Server.Closed is false again.
```

### Related guides

- [Compatibility](./compatibility.md)
