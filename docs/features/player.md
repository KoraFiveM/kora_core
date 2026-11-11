---
title: Player data and lifecycle
sidebar_position: 1
---

# Player data and lifecycle

The server keeps one authoritative record per logged-in character. Other resources
never receive the live record: every read returns a deep copy, and every write goes
through `setPath` (or a wrapper such as `addMoney`, `setJob`, `setMetaData`,
`addItem`).

## PlayerData shape

Native PlayerData (what `getPlayer` returns and what the client mirror holds):

| Key | Type | Persisted column | Notes |
| --- | --- | --- | --- |
| `source` | integer | no | Current server ID. |
| `citizenid` | string | `citizenid` | Character key. Immutable. |
| `license` | string | `license` | Owner's primary identifier. Immutable. |
| `cid` | integer | `cid` | Character slot (1-based). Immutable. |
| `name` | string | `name` | `firstname lastname`. |
| `money` | table | `money` | `[account] = number` for each `Config.money.types` entry. |
| `charinfo` | table | `charinfo` | `firstname`, `lastname`, `birthdate`, `gender`, `nationality`, `phone`. |
| `job` | table | `job` | `name`, `label`, `type`, `payment`, `onduty`, `isboss`, `grade` with `name` and one-based `level`. |
| `gang` | table | `gang` | `name`, `label`, `isboss`, `grade` with `name` and one-based `level`. |
| `position` | table | `position` | `x`, `y`, `z`, `h`; sampled server-side at save time. |
| `metadata` | table | `metadata` | hunger, thirst, stress, armor, isdead, inlaststand, ishandcuffed, jailed, injail, licences, phone, bloodtype, fingerprint, walletid, starterItems and any custom keys. |
| `items` | table | `inventory` | Slot-keyed item records (see [Inventory](./inventory.md)). |
| `phone` | string | `phone_number` | Phone number generated at creation. |

Only the roots in the persisted column list are saved. Grades are one-based in
native data; the legacy compatibility views convert them to stock zero-based levels.

A new character starts with `Config.money.default`, `Config.jobs.defaultJob` at
`Config.jobs.defaultGrade`, gang `none`, position Legion Square
(`195.17, -933.77, 30.69`), full hunger/thirst, and `metadata.starterItems` marking
the names in `QBCore.Shared.StarterItems` (`phone`, `id_card`, `driver_license`).
kora_core does not grant those items itself.

## Writing: the funnel

```lua
local ok, err = exports.kora_core:setPath(source, { 'metadata', 'stress' }, 20)
```

`setPath(src, path, value, opts)` writes `value` at the key array `path`, marks the
owning column dirty, queues a client delta (unless `opts.silent`), calls every
`onChange` subscriber whose prefix matches, and fires
`kora_core:server:inventoryChanged` when the root is `items`. `nil` deletes the path.

It returns `false` with one of these reasons:

- `no such player`
- `path must be a non-empty array`
- `player logout is in progress`
- `player data is busy` (a durable provider operation holds the column)
- `PlayerData field <key> is owned by <resource>` (a registered field, see below)
- `physical cash account is inventory-owned` (write the cash account through the money API)

Prefer the domain wrappers ([Money](./money.md), [Jobs](./jobs-gangs.md),
[Metadata](./metadata-needs.md), [Inventory](./inventory.md)); they validate input
and fire the legacy events.

## Reading

| Export (server) | Returns |
| --- | --- |
| `getPlayer(src)` | Deep copy of PlayerData, or `nil`. |
| `getPlayerByCitizenId(citizenid)` | Deep copy for an online character, or `nil`. |
| `getPlayerData(src, path)` | Value at `path` (tables are copied); the whole copy when `path` is `nil`. |
| `getPlayers()` | Array of online sources with a loaded character. |
| `getAllPlayers()` | Array of copies for every loaded character. |
| `isCoreReady()` | `true` once the first server frame after boot has run. |

## Subscribing to changes (server)

```lua
local id = exports.kora_core:onChange({ 'money' }, function(src, path, value)
    print(src, table.concat(path, '.'), value)
end)
exports.kora_core:offChange(id)
```

The handler receives `(src, path, value)`. A string prefix is wrapped into a
one-element array. Handlers are protected with `pcall` and are removed when the
registering resource stops.

## Resource-owned replicated fields

A resource can add its own root key to PlayerData that is replicated to the owner's
client but never saved by kora_core:

```lua
exports.kora_core:registerPlayerDataField('reputation', function(src, citizenid)
    return loadReputation(citizenid) -- value, or nil plus an error string
end)

exports.kora_core:setPlayerDataField(source, 'reputation', { level = 3 })
```

- Keys must match a lowercase identifier of at most 32 characters and must not be
  a core root (`source`, `citizenid`, `license`, `cid` or any persisted root).
- The provider runs for every online player on registration and before each
  player's initial snapshot.
- Only the registering resource can write the field (`setPlayerDataField` or
  `setPath`). When it stops, the field is removed from every player.
- Treat the client copy as a read model; authorize from your own server data.

## Character lifecycle

### Selecting and creating

kora_core ships no character-select UI. Without one, the client asks for the
player's characters about 500 ms after start, selects the first one, or creates a
default "John Doe" character in slot 1 when none exist.

A UI resource calls the client export `claimUI()` before that timer fires and then
drives selection itself through the exports or net events:

| Client export | Effect |
| --- | --- |
| `claimUI()` | Disable the built-in auto-select flow. |
| `request()` | Fire `kora_core:server:requestCharacters`; the list arrives in `kora_core:client:receiveCharacters`. |
| `select(citizenid)` | Fire `kora_core:server:selectCharacter`; the result arrives in `kora_core:client:characterSelected(ok, err)`. |
| `create(charinfo, cid)` | Fire `kora_core:server:createCharacter`. |

Server exports:

| Export | Description |
| --- | --- |
| `getCharacters(src)` | Yields. Summaries `citizenid, cid, name, charinfo, money, job, gang` for the source's license (deleted rows excluded). |
| `ownsCharacter(src, citizenid)` | Yields. Ownership check without logging in. |
| `selectCharacter(src, citizenid)` | Yields. Loads the row, checks ownership, logs in. Returns `true` or `false, err`. |
| `createCharacter(src, charinfo, cid)` | Yields. Returns the new citizen ID, or `nil, err`. |
| `deleteCharacter(src, citizenid)` | Yields. Ownership check, logs the character out first if it is online, then soft-deletes the row (`deleted_at`). |

`createCharacter` validates the input: first and last name 1 to 24 visible
characters, `birthdate` a real non-future `YYYY-MM-DD` (default `1990-01-01`),
`gender` 0 or 1, `nationality` 2 to 32 characters (default `USA`). The phone number
is generated server-side; other client-supplied fields are ignored. The slot cap is
`getMaxCharacters(license)` (see [Identity and utilities](./identity-utilities.md#users)).
An explicit `cid` is accepted only if it is a free slot within the cap; otherwise
the next free slot is used. Errors include `character limit reached`,
`requested character slot is unavailable`, `source already logged in` and
`character creation already in progress`.

### Login

`login(src, citizenid, data)` adopts already-loaded data. On success, in order:

1. `QBCore:Server:PlayerLoaded` (with the legacy player object) and
   `kora_core:server:playerLoaded(src, citizenid)` fire on the server.
2. The full snapshot is sent to the client (`kora_core:rep:snapshot`).
3. The state bags `kora_core:loggedIn` and `isLoggedIn` are set to `true`
   (replicated) and the `kora_core:money:<account>` bags are published.
4. `QBCore:Client:OnPlayerLoaded` is sent, unless
   `Config.compat.deferClientPlayerLoaded` is on.

For client UI visibility, watch `LocalPlayer.state['kora_core:loggedIn']`. The bare
`isLoggedIn` bag is kept for legacy resources.

### Logout

`logout(src, options)` keeps the connection and yields until kora_sql confirms a
save of every mutable column. Only then are both login state bags cleared,
`QBCore:Client:OnPlayerUnload` and `QBCore:Server:OnPlayerUnload` fired and the
character evicted. If the save fails or is uncertain, the character stays loaded
and the call returns `false, reason`; always check the result.

`options.position` (`x`, `y`, `z`, optional `h`) is accepted only from
`kora_housing` or kora_core itself and must be finite numbers. Never forward client
coordinates.

### Drop

On `playerDropped`, kora_core saves the player immediately, fires
`QBCore:Server:PlayerDropped(src, reason)` and `QBCore:Server:OnPlayerUnload(src)`
while the player can still be read, evicts the character and then fires
`kora_core:server:playerDropped(src, citizenid, reason)`. `dropPlayer(src, reason)`
is the same routine.

### Other helpers

| Export | Description |
| --- | --- |
| `savePlayer(src, requiredField)` | Queue an immediate save. With `requiredField`, refuses when that field's column is fenced. Returns `true` or `false, err`. |
| `setPlayerBucket(src, bucket)` | Sets the routing bucket, the replicated `instance` state bag and the legacy `QBCore.Player_Buckets` entry, and fires `kora_voice:server:bucketChanged`. |
| `getStarterItems()` | Copy of `QBCore.Shared.StarterItems`. |

## Client mirror

Each client holds a live copy of its own PlayerData, updated by deltas
(`{ p = path, v = value }` or `{ p = path, d = true }`) that the server coalesces
per player per frame. Each batch carries a sequence number; a gap or a delta before the first
snapshot makes the client request a resync (rate-limited by
`Config.replication.resyncRateLimit`).

```lua
-- client
local cash = exports.kora_core:getPlayerData({ 'money', 'cash' })

local id = exports.kora_core:onPlayerDataChange({ 'metadata', 'hunger' }, function(path, value)
    updateHungerBar(value)
end)
exports.kora_core:offPlayerDataChange(id)
```

| Client export | Description |
| --- | --- |
| `getPlayerData(path)` / `getData(path)` | Value at `path`, or the live mirror table when `path` is `nil` (`nil` before the first snapshot). Paths are key arrays. |
| `onPlayerDataChange(prefix, handler)` / `onChange(prefix, handler)` | Subscribe; `handler(path, value)` runs for every applied op under the prefix. |
| `offPlayerDataChange(id)` / `offChange(id)` | Unsubscribe. |
| `requestResync()` | Ask for a fresh snapshot. |
| `getStats()` | `seq`, `resyncs`, `opsApplied`, `lastDeltaAt`. |
| `reannounceFull()` | Re-fire the legacy `QBCore:Player:SetPlayerData` from the current mirror. Returns `false` before the first snapshot. |
| `isWearingGloves()` | `true` unless the arms drawable is in the stock no-glove lists. |

On every snapshot the client fires `kora_core:client:playerLoaded(mirror)`. Legacy
events (`QBCore:Player:SetPlayerData`, `QBCore:Client:OnJobUpdate`, ...) are fired
locally from the mirror; see [Compatibility](../compatibility.md#client-playerdata).

## Persistence

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

### Durable provider column operations

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
