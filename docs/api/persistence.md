---
title: "Persistence and schema"
sidebar_position: 12
---


# Persistence and schema

Saves player data through kora_sql, creates the database tables, and lets durable providers fence columns during multi-step operations. Saving is dirty-column based: a column is written only when it was touched and its encoded JSON differs from the last saved baseline.

Namespace: `exports.kora_core` · Source: `modules/persistence/server.lua, operations.lua, schema.lua, boot.lua`

## How it works

Writes go through kora_sql's queue as updates to the `players` row keyed by citizenid. Immutable `license` and `cid` are never part of a save. Logout and shutdown paths flush the queue and wait; the periodic flush does not.

## Terms used on this page

| Term | Meaning |
| --- | --- |
| Dirty column | A database column marked changed by `setPath` (through COLUMN_FOR). Only dirty columns are encoded and compared. |
| Baseline | The last encoded value per column. Seeded at login so unchanged data writes nothing; a column whose new encoding is byte-identical is dropped before it reaches the wire. |
| Column fence | A durable lock on `money`, `inventory` or `metadata` columns for specific characters, held by a provider resource while it commits a multi-row operation. Persisted in `kora_core_player_column_operations` so it survives a restart. |
| Provider | The only resources allowed to fence: `kora_banking` and the resource named in `Config.inventory.provider` (default `kora_inventory`). |

## Configuration (Config.persistence)

Keys read by this module. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `interval?` | integer | Milliseconds between autosave flushes. Default 60000. |
| `intervalJitter?` | number | Fraction of random jitter applied to each wait (wait = interval * (1 +/- jitter)). Default 0.10. |
| `positionEpsilon?` | number | Metres a player must move before position is persisted again. Default 2.0. |
| `positionMaxAge?` | integer | Milliseconds after which position is persisted even if the player has not moved. Default 300000. |
| `generatedColumns?` | boolean | When true, also creates the virtual columns `cash`, `bank`, `job_name` on `players` and indexes `idx_players_bank`, `idx_players_job_name`. Default false. |
| `saveOnDrop?` | boolean | Present in config.lua but not read by any code: a disconnect always saves. |
| `volatileMetadataKeys?` | table | Present and schema-validated in config.lua but not read by any persistence code in this version. |

## Autosave timer

A loop waits `Config.persistence.interval` ms (with jitter), then calls `flushAll`; if any row was enqueued it also asks kora_sql to flush the `players` queue immediately. Positions are sampled server-side from the player ped (GetPlayerPed / GetEntityCoords): a client cannot supply its saved position.

## Shutdown and restart flush

On `txAdmin:events:serverShuttingDown`, and on `txAdmin:events:scheduledRestart` when `payload.secondsRemaining` is 60 or less, every online player is saved immediately and the `players` queue is flushed. On `onResourceStop` of kora_core the same drain runs as a best effort (FXServer does not guarantee that a yield finishes, so worst-case loss is bounded by one interval).

## Tables created

Applied additively through `Kora.sql.ensureTables`: `players` (citizenid unique, phone_number unique, license plus generated active_cid unique, soft delete via deleted_at, JSON longtext columns money/charinfo/job/gang/position/metadata/inventory), `player_identifiers` (citizenid, kind, value), `inventories` (identifier, kind, items, slots, maxweight), `bans` (name, license, discord, ip, reason, expire, bannedby), `users` (license, max_characters, discord), `player_vehicles` (plate, model/vehicle, citizenid, state, garage_id, fuel, engine_health, body_health, mods and legacy columns), `kora_core_player_column_operations` (citizenid, column_name, resource, operation_key, fingerprint). Two triggers, `kora_core_player_vehicles_compat_insert` and `kora_core_player_vehicles_compat_update`, keep the legacy and kora vehicle columns in sync (kora columns win). Schema warnings print as `[kora_core:schema]`.

## Boot sequence and databaseReady

A thread waits (printing `still waiting for kora_sql; schema setup will resume automatically.`) until `Kora.sql.ready` succeeds, applies the schema, creates the vehicle triggers, prints `schema up to date.`, warms two prepared statements and fires local event `kora_core:server:databaseReady` (no arguments). If schema setup fails, an error is printed and the event is not fired. A trigger failure is printed but the event still fires. On a blank database, use `awaitSchema` before touching player tables.

## Fence rules

While a column is fenced for a character: `setPath` on that column returns `player data is busy`, `login`, `logout`, `getOfflinePlayerData` and `saveOfflinePlayer` refuse, and the autosave skips the column. Only the provider's own write token (used by `finishPlayerColumnOperation`) can write it. Fence state is also checked against kora_sql's active player operations.

## Functions

Persistence exports. `saveNow` and `flushAll` are low-level; prefer `savePlayer`. Fence functions are provider-only.

### `exports.kora_core:flushAll()`

Samples positions of every online player, collects all dirty columns that changed, and enqueues one batched update. Returns without waiting for the database. Called by the autosave timer.

**Parameters**



**Returns**

- **integer** — number of player rows enqueued (0 if nothing changed).

**Example**

```lua
local rows = exports.kora_core:flushAll()
print(('queued %d player rows'):format(rows))
```

**Representative console output**

```text
queued 3 player rows
```

### `exports.kora_core:saveNow(player)`

Immediate-priority save of one player Player handle. Internal helper: it reads `player.citizenid`, `player.source`, `player.PlayerData`, `player._dirty` and `player._encoded` and does not validate the table or check the caller. A table passed from another resource is a copy, so the live player is not updated. Use `savePlayer(src)` instead.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `player` | table | Player handle with `citizenid`, `source`, `PlayerData`, `_dirty`, `_encoded`. |

**Returns**

- **nil** — Returns nothing. Raises a Lua error if `_dirty` or `_encoded` are missing.

**Example**

```lua
-- prefer: exports.kora_core:savePlayer(src)
```

**Representative console output**

```text
No output.
```

### `exports.kora_core:getOfflinePlayerData(citizenid)`

Reads a character straight from the database into PlayerData shape without logging them in. Yields. Reads only active rows (`deleted_at IS NULL`) and reads the database, not live memory: for an online character the result can lag behind unsaved changes.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `citizenid` | string | Character id. |

**Returns**

- **table** — `{ citizenid, license, cid, name, money, charinfo, job, gang, position, metadata, items, phone }`; `items` is re-keyed by numeric slot, `position` falls back to `{ x = 0, y = 0, z = 70, h = 0 }`, `job.type` is backfilled from the registry.
- **nil, 'invalid citizenid'** — not a non-empty string.
- **nil, 'player data is busy'** — fenced.
- **nil** — second return value is the reason: 'player operation storage is unavailable'.
- **nil, 'player data changed while loading'** — a fence began during the read.
- **nil, 'not found' (or a SQL error string)** — no active row.

**Example**

```lua
local data, err = exports.kora_core:getOfflinePlayerData('AB12CD34')
if not data then return print('offline read failed: ' .. tostring(err)) end
print(data.charinfo.firstname, data.money.bank)
```

**Representative console output**

```text
Ada 5000
```

### `exports.kora_core:saveOfflinePlayer(data, fields)`

Writes only the listed columns of an offline character with a single UPDATE. Yields. No caller restriction. Refuses while the player is online or fenced. Values are taken from `data` and encoded exactly as a normal save would.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `data` | table | PlayerData-shaped table; `data.citizenid` selects the row. |
| `fields` | string[] | Non-empty array of PlayerData root keys from COLUMN_FOR: `charinfo`, `job`, `gang`, `money`, `metadata`, `items`, `position`, `name`, `phone`. |

**Returns**

- **true** — written.
- **false, 'invalid player data'** — `data` is not a table or `citizenid` is not a string.
- **false, 'fields are required'** — empty or non-table `fields`.
- **false, 'player is online'** — use the funnel exports for online players.
- **false, 'player data is busy' / 'player operation storage is unavailable'** — fenced or fence storage unreadable.
- **false, 'invalid player field'** — a field is not a COLUMN_FOR key.
- **false, 'could not save offline player' (or a SQL error string)** — the update failed.
- **false, 'player not found'** — no active row for that citizenid.

**Example**

```lua
local data = exports.kora_core:getOfflinePlayerData(citizenid)
data.money.bank = data.money.bank + 1000
local ok, err = exports.kora_core:saveOfflinePlayer(data, { 'money' })
```

**Representative console output**

```text
Returns true.
```

### `exports.kora_core:awaitSchema()`

Waits for the `players`, `player_vehicles` and `kora_core_player_column_operations` tables to exist, up to 60000 ms. Yields. The success is cached.

**Parameters**



**Returns**

- **true** — tables are ready.
- **false, &lt;error>** — timed out or the wait failed.

**Example**

```lua
local ready, err = exports.kora_core:awaitSchema()
if not ready then return print('schema not ready: ' .. tostring(err)) end
```

**Representative console output**

```text
Returns true.
```

### `exports.kora_core:beginPlayerColumnOperation(key, citizenids, columns)`

Provider-only. Fences columns for the given characters: flushes current values of online players, persists the fence rows, and blocks other writers until finished or aborted. Yields. Calling again with the same key and the same ids and columns resumes a persisted operation.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `key` | string | Operation key, 1-240 characters, unique per provider. The token is `<resource>:<key>`. |
| `citizenids` | string[] | Up to 128 character ids, each 1-50 characters. Duplicates are ignored. |
| `columns` | string[] | 1 to 3 distinct values from `money`, `inventory`, `metadata`. |

**Returns**

- **token** — string, operation prepared and fenced.
- **token, 'resumed'** — an identical persisted operation already exists.
- **nil, 'unavailable', &lt;message>** — schema not ready, or preparation failed with the database state known (fence released).
- **nil, 'rejected', 'Only configured durable providers may fence player data.'** — caller is not kora_banking or `Config.inventory.provider`.
- **nil, 'rejected', 'Invalid player operation.' / 'Invalid character ID.' / 'Invalid durable player column.'** — bad arguments.
- **nil, 'conflict', 'Operation key has different player columns.'** — key reused with different ids or columns.
- **nil, 'pending', 'Player operation is preparing.' / 'An offline player write is pending.' / 'Player data is busy.'** — retry later.
- **nil, 'indeterminate', &lt;message>** — the fence write may or may not have committed; call again with the same arguments to resume.

**Example**

```lua
-- kora_banking, transferring between two characters
local token, status, message = exports.kora_core:beginPlayerColumnOperation(
    'transfer:' .. transferId, { fromCid, toCid }, { 'money' })
if not token then return handleStatus(status, message) end
```

**Representative console output**

```text
Returns "kora_banking:transfer:1042".
```

### `exports.kora_core:finishPlayerColumnOperation(token, committed)`

Provider-only. Applies the committed values to online players through `setPath` (with the operation's write token), re-baselines persistence, removes the fence rows and releases the fence. Yields. Not atomic across players: if applying one fails, earlier players are already updated and the fence stays.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `token` | string | Token from `beginPlayerColumnOperation`. |
| `committed` | table | `committed[citizenid][column]` table for every character and column in the operation, where `column` is `money`, `inventory` or `metadata`. |

**Returns**

- **true** — applied and released.
- **false, 'Unknown player operation.'** — unknown token or caller is not the owning provider.
- **false, 'Player operation is not ready.'** — still preparing, or `committed` is not a table.
- **false, 'Committed player values are required.'** — a required entry is missing or not a table.
- **false, &lt;error>** — a `setPath` error, or 'Could not release the committed player operation.' / SQL error when deleting the fence rows.

**Example**

```lua
local ok, err = exports.kora_core:finishPlayerColumnOperation(token, {
    [fromCid] = { money = fromMoney },
    [toCid] = { money = toMoney },
})
```

**Representative console output**

```text
Returns true.
```

### `exports.kora_core:abortPlayerColumnOperation(token)`

Provider-only. Rolls back an operation: deletes the fence rows and releases the fence without changing player data. Yields.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `token` | string | Token from `beginPlayerColumnOperation`. |

**Returns**

- **true** — released.
- **false, 'Unknown player operation.'** — unknown token, not the owner, or still preparing.
- **false** — second return value is the reason: 'Could not release the rolled-back player operation.' (or a SQL error string).

**Example**

```lua
local ok, err = exports.kora_core:abortPlayerColumnOperation(token)
```

**Representative console output**

```text
Returns true.
```

### `exports.kora_core:getPlayerColumnOperations()`

Provider-only. Lists the caller's operations, rebuilding in-memory fences from the database after a restart so a provider can finish or abort them. Yields. Callers that are not providers get an empty array.

**Parameters**



**Returns**

- **table[]** — each `{ token, operationKey, citizenids, columns, preparing }`; empty for a non-provider.
- **error** — Raises a Lua error when the schema or fence storage is unavailable.

**Example**

```lua
for _, operation in ipairs(exports.kora_core:getPlayerColumnOperations()) do
    resolveOperation(operation.token, operation.operationKey)
end
```

**Representative console output**

```text
{ { token = "kora_banking:transfer:1042", operationKey = "transfer:1042", citizenids = { "AB12CD34" }, columns = { "money" }, preparing = false } }
```

## Common use cases

- Edit an offline character's money or job from an admin tool with `getOfflinePlayerData` and `saveOfflinePlayer`.
- Wait for tables before a resource queries `players` on a blank database with `awaitSchema` or the `kora_core:server:databaseReady` event.
- A banking or inventory provider commits a multi-character transfer atomically using the fence functions.

## Limits and related APIs

Fence functions work only for kora_banking and `Config.inventory.provider`. A fence covers only `money`, `inventory` and `metadata`, at most 3 columns and 128 characters per operation. A hard crash loses at most the writes queued since the last flush (about one interval).

## Related guides

- [Player data and lifecycle](./player.md)
- [Money](./money.md)
- [Inventory](./inventory.md)
- [Configuration](./configuration.md)
- [Garage](./garage.md)

## Persistence behaviour (code-derived)

### Persistence

- A column is written only when it is dirty and its JSON encoding differs from the
  last saved value, so a write of the current value costs nothing.
- Every `Config.persistence.interval` (with jitter) all dirty rows are sent to
  kora_sql in one `enqueueMany` batch, then kora_sql is asked to flush.
- Position is sampled from the ped at save time and stored only after moving
  `positionEpsilon` metres or after `positionMaxAge`.
- Immediate saves: drop, logout (awaited), `QBCore:UpdatePlayer`, legacy `Save`,
  txAdmin `serverShuttingDown`, txAdmin `scheduledRestart` within 60 seconds, and
  kora_core's own stop.
- `license` and `cid` are never part of a save.

| Export | Description |
| --- | --- |
| `flushAll()` | Run a periodic flush now. Returns the number of players enqueued. |
| `saveNow(player)` | Internal handle only; use `savePlayer(src)` instead. |
| `awaitSchema()` | Yields until `players`, `player_vehicles` and the operations table exist (60 s timeout). |
| `getOfflinePlayerData(citizenid)` | Yields. Decoded data for a stored, non-deleted character, or `nil, err`. |
| `saveOfflinePlayer(data, fields)` | Yields. Writes only the named roots (for example `{ 'job' }`) of an offline character. Refuses online characters, immutable fields and missing rows. |

#### Durable provider column operations

Only `kora_banking` and the configured `Config.inventory.provider` may call these
server exports; they let a provider change the `money`, `inventory` or `metadata`
columns of several characters atomically in its own SQL transaction.

| Export | Description |
| --- | --- |
| `beginPlayerColumnOperation(key, citizenids, columns)` | Fences up to 128 characters and 1 to 3 of `money`, `inventory`, `metadata`, drains pending saves and records the fence. Returns a token, `token, 'resumed'`, or `nil, code, message` with code `rejected`, `pending`, `conflict`, `unavailable` or `indeterminate` (outcome unknown; keep it pending until reconciled). |
| `finishPlayerColumnOperation(token, values)` | Publishes the committed values (`values[citizenid][column]` must be a table for every fenced pair) into live state and releases the fence. |
| `abortPlayerColumnOperation(token)` | Releases the fence after a confirmed rollback. |
| `getPlayerColumnOperations()` | Yields. The caller's pending operations, including fences recovered after a core restart. |

While a fence is held, ordinary writes to that column fail with
`player data is busy`, saves skip it, and login, offline writes and deletion of the character are
refused. These calls must never be exposed as client events.

## Database tables and columns (code-derived)

kora_core has no SQL file to import. At boot it waits for kora_sql, then applies the
declarative schema in `modules/persistence/schema.lua` with `Kora.sql.ensureTables`.
That call creates missing tables, columns and indexes but never drops or reshapes
existing ones. Schema warnings are printed with the prefix `[kora_core:schema]`.
When everything is in place it prints `schema up to date.`, warms two prepared
statements and fires `kora_core:server:databaseReady`.

All tables use the `utf8mb4_unicode_ci` collation except
`kora_core_player_column_operations`, which uses the database default.

### players

One row per character.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | int unsigned, auto increment | Primary key. |
| `citizenid` | varchar(50) | Unique (`uk_players_citizenid`). |
| `license` | varchar(60) | Owner's primary identifier. |
| `cid` | tinyint unsigned, default 1 | Character slot. |
| `name` | varchar(255), default `unknown` | |
| `money` | longtext | JSON. |
| `charinfo` | longtext | JSON. |
| `job` | longtext | JSON (one-based grade level). |
| `gang` | longtext | JSON (one-based grade level). |
| `position` | longtext | JSON `x, y, z, h`. |
| `metadata` | longtext | JSON. |
| `inventory` | longtext, nullable | JSON of `PlayerData.items`. |
| `phone_number` | varchar(20), nullable | Unique (`uk_players_phone`). |
| `created_at` | timestamp | |
| `last_updated` | timestamp | Updated on change. |
| `deleted_at` | timestamp, nullable | Soft delete. Deleted rows are ignored everywhere. |
| `active_cid` | tinyint unsigned, generated | `cid` while not deleted, otherwise `NULL`. |

Indexes: `idx_players_license_deleted (license, deleted_at)`,
`idx_players_last_updated (last_updated)`, and the unique
`uk_players_license_active_cid (license, active_cid)`, which keeps one active
character per slot while letting a deleted slot be reused.

Saves are column-level `UPDATE`s through kora_sql's queue; `license` and `cid` are
never written after creation.

#### Generated columns

With `Config.persistence.generatedColumns = true`, these virtual columns are added
to `players` so the data can be queried in SQL:

| Column | Expression |
| --- | --- |
| `cash` | `CAST(JSON_EXTRACT(money, '$.cash') AS SIGNED)` |
| `bank` | `CAST(JSON_EXTRACT(money, '$.bank') AS SIGNED)` |
| `job_name` | `JSON_UNQUOTE(JSON_EXTRACT(job, '$.name'))` |

with indexes `idx_players_bank` and `idx_players_job_name`. When the inventory
provider owns physical cash, the stored `cash` value is 0.

```sql
SELECT citizenid, name, bank FROM players WHERE job_name = 'police' ORDER BY bank DESC;
```

### player_identifiers

Identifiers seen per character, for alt and ban lookups.

| Column | Type | Notes |
| --- | --- | --- |
| `citizenid` | varchar(50) | Primary key part. |
| `kind` | varchar(20) | Primary key part (`license`, `discord`, `steam`, `ip`, ...). |
| `value` | varchar(128) | Without the `kind:` prefix. |
| `first_seen` | timestamp | |
| `last_seen` | timestamp | Updated on change. |

Index `idx_ident_lookup (kind, value)`.

### users

One row per license.

| Column | Type | Notes |
| --- | --- | --- |
| `license` | varchar(60) | Primary key. |
| `max_characters` | tinyint unsigned, nullable | Per-license slot override; `NULL` uses `Config.identity.maxCharacters`. |
| `discord` | varchar(50), nullable | Last Discord ID seen. Index `idx_users_discord`. |
| `created_at` | timestamp | |
| `last_seen` | timestamp | Updated on change. |

### inventories

Stash storage used by the fallback `stashGet`/`stashSet`.

| Column | Type | Notes |
| --- | --- | --- |
| `identifier` | varchar(64) | Primary key. |
| `kind` | varchar(20), default `stash` | |
| `items` | longtext | JSON. |
| `slots` | smallint unsigned, default 50 | |
| `maxweight` | int unsigned, default 100000 | |
| `updated_at` | timestamp | Updated on change. |

Index `idx_inventories_kind_updated (kind, updated_at)`.

### bans

Used by the legacy `QBCore.Functions.IsPlayerBanned` and `ExploitBan`. kora_core
does not check bans on connect by itself.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | int unsigned, auto increment | Primary key. |
| `name` | varchar(50), nullable | |
| `license` | varchar(60), nullable | With or without the `license:` prefix. |
| `discord` | varchar(50), nullable | |
| `ip` | varchar(50), nullable | |
| `reason` | text, nullable | |
| `expire` | int unsigned, nullable | UNIX time; `NULL` is permanent. |
| `bannedby` | varchar(255), default `LeBanhammer` | |

Indexes on `license`, `discord`, `ip` and `expire`.

### player_vehicles

Owned vehicles for `Core.garage` and garage/dealership resources.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | int unsigned, auto increment | Primary key; used for the `vehicleid` state bag. |
| `plate` | varchar(15) | Unique (`uk_vehicles_plate`). |
| `model` | varchar(60), nullable | Kora model name. Synced with `vehicle`. |
| `vehicle` | varchar(60), nullable | Stock column. |
| `citizenid` | varchar(50), nullable | Civilian owner. Index. |
| `job` | varchar(50), nullable | Fleet job. Index. |
| `state` | enum `out`, `garaged`, `impounded`, default `garaged` | Index. |
| `garage_id` | varchar(50), nullable | Synced with `garage`. |
| `fuel` | tinyint unsigned, default 100 | |
| `engine_health` | smallint unsigned, default 1000 | Synced with `engine`. |
| `body_health` | smallint unsigned, default 1000 | Synced with `body`. |
| `mods` | longtext, nullable | JSON vehicle properties. |
| `last_position` | longtext, nullable | JSON. |
| `impound_fee` | int unsigned, nullable | |
| `impound_lot` | varchar(50), nullable | |
| `impounded_at` | timestamp, nullable | |
| `created_at`, `last_updated` | timestamp | |
| `deleted_at` | timestamp, nullable | Soft delete. |
| `balance`, `paymentamount`, `paymentsleft`, `financetime` | int, default 0 | Finance columns shared with stock resources. |
| `license`, `hash`, `fakeplate`, `garage` | varchar(50), nullable | Stock columns. |
| `engine`, `body` | float, nullable | Stock columns. |
| `depotprice` | int, default 0 | Stock column. |
| `drivingdistance` | int, nullable | Stock column. |
| `status` | text, nullable | Stock column. |

Two triggers, `kora_core_player_vehicles_compat_insert` and
`kora_core_player_vehicles_compat_update`, keep the kora/stock column pairs in
sync. They are installed at boot only when missing. See
[`player_vehicles` compatibility](../vehicles-compat.md).

### kora_core_player_column_operations

Durable fences for provider column operations (see
[Player](./persistence.md#durable-provider-column-operations)).

| Column | Type | Notes |
| --- | --- | --- |
| `citizenid` | varchar(50) | Primary key part. |
| `column_name` | varchar(16) | Primary key part: `money`, `inventory` or `metadata`. |
| `resource` | varchar(64) | Owning provider. |
| `operation_key` | varchar(240) | |
| `fingerprint` | longtext | JSON of the fenced citizen IDs and columns. |
| `created_at` | timestamp | |

Index `idx_player_operation_owner (resource, operation_key)`.

### Requirements

The triggers and generated columns assume MariaDB 10.2 or later. kora_core reads
`information_schema.TRIGGERS` to detect existing triggers, so the database user
needs permission to create triggers.

## Durability (code-derived)

The periodic save bounds worst-case data loss on a hard crash to roughly one
`Config.persistence.interval` (60 seconds by default, with jitter). Player drop,
logout, txAdmin shutdown, a txAdmin scheduled restart within 60 seconds and the
resource stop all flush immediately, but FXServer does not guarantee that a yield
in `onResourceStop` completes, so this bounds loss rather than eliminating it.
