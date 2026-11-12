---
title: "Player data and lifecycle"
sidebar_position: 2
---


# Player data and lifecycle

## Server

The authoritative player cache. Every online character is held in memory by source and by citizenid; reads never touch the database. `setPath` is the single mutation funnel: money, job, gang, metadata, inventory and position changes all go through it, so dirty-tracking, client delta replication and `onChange` subscribers are handled in one place. Nothing outside kora_core ever receives the live Player handle: every read export returns a deep-cloned snapshot. This realm also holds the identity helpers (identifier extraction, citizenid generation) and the per-license `users` rows (character-slot cap, Discord id).

Namespace: `exports.kora_core` · Source: `modules/player/server.lua, modules/player/shared.lua, modules/identity/server.lua, modules/users/server.lua`

### How it works

Login is two-step: a source picks or creates a character (`createCharacter`, or `login` with data loaded from the database by the character-select module), the player is adopted into both caches, persistence seeds its baseline, a full snapshot is sent to the client, and the logged-in state bags are set. Logout waits for the final save to be confirmed by the SQL queue before evicting the player. A disconnect always saves immediately and evicts without waiting.

### Login to logout

1. **Select or create** — The character-select module calls `login(src, citizenid, data)` for an existing character (after checking the license owns it) or `createCharacter(src, charinfo, cid?)` for a new one. `createCharacter` validates charinfo, computes a free slot server-side, inserts the `players` row and records identifiers.
2. **Adopt** — The player is added to the source and citizenid caches. Persistence seeds the per-column baseline so a login that changes nothing writes nothing. Replicated-only fields are hydrated by their providers. Physical cash is migrated if kora_inventory owns the cash account; a failure here aborts the login and removes the player from both caches.
3. **Announce** — Local events `QBCore:Server:PlayerLoaded` and `kora_core:server:playerLoaded` (src, citizenid) fire, then the full snapshot is sent (`kora_core:rep:snapshot`), then state bags `kora_core:loggedIn` and `isLoggedIn` become true. Unless `Config.compat.deferClientPlayerLoaded` is true, `QBCore:Client:OnPlayerLoaded` is sent to the client.
4. **Play** — All changes go through `setPath` and are coalesced into one `kora_core:rep:delta` per player per tick. The autosave flush persists dirty columns every `Config.persistence.interval` ms.
5. **Logout or drop** — `logout(src)` saves a complete snapshot, waits for the SQL flush to confirm, clears the state bags, sends `QBCore:Client:OnPlayerUnload` and fires `QBCore:Server:OnPlayerUnload`, then evicts. On disconnect `dropPlayer` saves with immediate priority, fires the drop events, then evicts.

### Terms used on this page

| Term | Meaning |
| --- | --- |
| citizenid | Identifier of one character: `Config.identity.citizenIdPrefix` (default empty) plus `Config.identity.citizenIdLength` (default 8) random characters from A-Z and 0-9. Unique in `players` through the `uk_players_citizenid` index. A license (primary identifier) owns several citizenids. |
| source | The FXServer player id. `PlayerData.source` is set on adoption. A source is bound to at most one character, and a character to at most one source, at a time. |
| PlayerData | The plain table returned by the read exports. Root keys: `citizenid`, `license`, `cid`, `name`, `money`, `charinfo`, `job`, `gang`, `position`, `metadata`, `items`, `phone`, plus any root registered with `registerPlayerDataField`. `source` is added on adoption. |
| setPath funnel | `setPath(src, path, value, opts?)` writes PlayerData at `path` (array of keys), marks the owning column dirty, queues a replication op for the client and calls matching `onChange` subscribers. A `nil` value deletes the key. Higher-level exports (money, jobs, metadata, inventory, jail) all end in this function. |
| COLUMN_FOR | Map of PlayerData root key to database column: `charinfo`->charinfo, `job`->job, `gang`->gang, `money`->money, `metadata`->metadata, `items`->inventory, `position`->position, `name`->name, `phone`->phone_number. A root key absent from this map is replicated but never persisted. `license` and `cid` are deliberately absent: they are immutable after creation and are never written by a save. |
| Replicated-only field | A root key registered by a resource with `registerPlayerDataField`. It is sent to the client inside PlayerData but is never persisted by kora_core, and only the registering resource can write it. |

### Session counters and state bags

A per-source session counter increments on `playerJoining` and on `playerDropped`. Logout captures the counter and aborts with `player session changed` if the source was reused or the player was replaced while the save yielded. On login the server sets `Player(src).state['kora_core:loggedIn']` and the legacy alias `Player(src).state['isLoggedIn']` to true (replicated); both are set to false at the start of the unload sequence on logout. Neither is cleared by `dropPlayer` because the player entity is going away. `setPlayerBucket` sets `Player(src).state.instance` to the bucket id (replicated).

### Trust: who can call what

Every export is callable by any resource; kora_core checks only `GetInvokingResource()` where noted. `login` does no ownership check and does not validate `data`: any resource can log any source in as any citizenid with any data table, so it must only be called by trusted server code. The character-select module checks that the character belongs to the source's primary identifier before calling it. `createCharacter` is safe to drive from client input: it validates every field, never trusts a client phone number, and computes the slot itself. `setPath` is unrestricted for ordinary roots, but a root registered through `registerPlayerDataField` can only be written by its owning resource, and `money.cash` style accounts are refused when inventory owns physical cash. `logout` accepts a position only from kora_housing. `dropPlayer` evicts a player from the cache without disconnecting them, so do not call it as a kick.

### Durable-operation fencing

While a durable provider (kora_banking or `Config.inventory.provider`) holds a column fence on a character, `setPath` on that column fails with `player data is busy`, and `login`, `logout` and `savePlayer(src, field)` refuse with the same reason. See the persistence module.

### Subscriber lifetime

`onChange` subscriptions and registered PlayerData fields belong to the invoking resource and are removed when that resource stops. Removing a registered field sets that root to nil on every online player.

### Functions

Player exports first, then identity and users exports. Functions marked as yielding wait on the database.

#### `exports.kora_core:setPath(src, path, value, opts?)`

The single mutation funnel. Writes `value` at `path` in the player's PlayerData, marks the column dirty, queues a client delta and notifies subscribers. Does not yield.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Source of an online, adopted player. |
| `path` | table | Non-empty array of keys, for example `{ 'money', 'cash' }` or `{ 'items', 3 }`. Intermediate tables are created. |
| `value` | any | New value. `nil` deletes the key and sends a delete op to the client. |
| `opts?` | table | Only `silent = true` is usable from another resource: it skips client replication (subscribers and persistence still run). Underscore-prefixed tokens are internal capabilities and cannot be forged across resources. |

**Returns**

- **true** — written.
- **false, 'no such player'** — `src` is not logged in.
- **false, 'player logout is in progress'** — the player is being logged out.
- **false, 'path must be a non-empty array'** — `path` is not a table or is empty.
- **false, 'player data is busy'** — the target column is fenced by a durable operation.
- **false, 'PlayerData field &lt;key> is owned by &lt;resource>'** — root was registered by another resource.
- **false, 'physical cash account is inventory-owned'** — `path[1] == 'money'` and `path[2]` is an account that kora_inventory holds as a cash item.

**Example**

```lua
local ok, err = exports.kora_core:setPath(src, { 'metadata', 'hunger' }, 80)
if not ok then
    print(('setPath failed for %s: %s'):format(src, err))
    return
end
```

**Representative console output**

```text
Returns true. The client receives { p = { "metadata", "hunger" }, v = 80 } in the next kora_core:rep:delta. Local event kora_core:server:inventoryChanged (src, path, value) additionally fires when path[1] is 'items'.
```

#### `exports.kora_core:getPlayer(src)`

Returns a deep-cloned snapshot of one player's full PlayerData.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Source of an online player. |

**Returns**

- **table** — PlayerData snapshot. Mutating it has no effect on the live player.
- **nil** — no such player.

**Example**

```lua
local data = exports.kora_core:getPlayer(src)
if not data then return end
print(data.citizenid, data.job.name, data.money.cash)
```

**Representative console output**

```text
AB12CD34 police 500
```

#### `exports.kora_core:setPlayerBucket(src, bucket)`

Moves a player into a routing bucket and records it. Sets the native routing bucket, `Player(src).state.instance` (replicated) and `QBCore.Player_Buckets[license]`, then fires local event `kora_voice:server:bucketChanged` (src). Does not require the player to be logged in or the bucket to exist.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player source. |
| `bucket` | integer | Routing bucket id. |

**Returns**

- **true** — applied.
- **false** — `src` or `bucket` is nil or false.

**Example**

```lua
exports.kora_core:setPlayerBucket(src, 50)
-- later
exports.kora_core:setPlayerBucket(src, 0)
```

**Representative console output**

```text
Returns true; Player(src).state.instance == 50.
```

#### `exports.kora_core:savePlayer(src, requiredField?)`

Enqueues an immediate-priority save of the player's dirty columns. The write is queued, not confirmed: it returns once the rows are handed to kora_sql. Use `requiredField` to refuse a save while a specific column is fenced.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Source of an online player. |
| `requiredField?` | string | A PlayerData root key from COLUMN_FOR (for example `'money'` or `'items'`). The save is refused if that column is fenced. |

**Returns**

- **true** — save enqueued.
- **false, 'no such player'** — `src` is not logged in.
- **false, 'invalid player field'** — `requiredField` is not a string or is not a COLUMN_FOR key.
- **false, 'player data is busy'** — the requested column is fenced.

**Example**

```lua
local ok, err = exports.kora_core:savePlayer(src, 'money')
if not ok then print('save refused: ' .. err) end
```

**Representative console output**

```text
Returns true.
```

#### `exports.kora_core:getStarterItems()`

Returns a deep clone of `QBCore.Shared.StarterItems`, the list granted to new characters.

**Parameters**



**Returns**

- **table** — array of starter item definitions (each with an `item` name).
- **nil** — no starter items are defined.

**Example**

```lua
local items = exports.kora_core:getStarterItems() or {}
for _, entry in ipairs(items) do print(entry.item, entry.amount) end
```

**Representative console output**

```text
phone 1
```

#### `exports.kora_core:getPlayerByCitizenId(citizenid)`

Returns a snapshot of an online player by character id. Offline characters are not loaded: use `getOfflinePlayerData` for those.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `citizenid` | string | Character id. |

**Returns**

- **table** — PlayerData snapshot.
- **nil** — that character is not online.

**Example**

```lua
local data = exports.kora_core:getPlayerByCitizenId('AB12CD34')
if data then print(data.source) end
```

**Representative console output**

```text
12
```

#### `exports.kora_core:getPlayerData(src, path?)`

Reads a sub-path of a player's data without cloning the whole blob. Table results are deep-cloned, scalars are returned directly.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Source of an online player. |
| `path?` | table | Array of keys such as `{ 'metadata', 'hunger' }`. Omit to get a full clone. |

**Returns**

- **any** — the value at `path`, or a full PlayerData clone when `path` is omitted.
- **nil** — no such player, or nothing at that path.

**Example**

```lua
local hunger = exports.kora_core:getPlayerData(src, { 'metadata', 'hunger' })
if hunger and hunger < 20 then print('hungry') end
```

**Representative console output**

```text
15
```

#### `exports.kora_core:getPlayers()`

Returns the sources of every logged-in player, in no defined order. Players still on character select are not included.

**Parameters**



**Returns**

- **integer[]** — array of sources (empty when nobody is logged in).

**Example**

```lua
for _, src in ipairs(exports.kora_core:getPlayers()) do print(src) end
```

**Representative console output**

```text
3
12
```

#### `exports.kora_core:getAllPlayers()`

Returns a PlayerData snapshot for every logged-in player. Clones every player: avoid calling it in hot loops.

**Parameters**



**Returns**

- **table[]** — array of PlayerData snapshots (empty when nobody is logged in).

**Example**

```lua
local onDuty = 0
for _, data in ipairs(exports.kora_core:getAllPlayers()) do
    if data.job.name == 'police' and data.job.onduty then onDuty = onDuty + 1 end
end
```

**Representative console output**

```text
onDuty == 2
```

#### `exports.kora_core:registerPlayerDataField(key, provider)`

Registers a resource-owned, replicated-only PlayerData root so client UI can read a domain's data from the mirror. The provider runs for every online player immediately and before every initial snapshot. Its value is never persisted by kora_core. Ownership is the invoking resource; the field is removed (set to nil for every player) when that resource stops.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `key` | string | Root name: lowercase letter first, then letters, digits or underscores, at most 32 characters. Must not be `source`, `citizenid`, `license`, `cid` or a COLUMN_FOR key (`charinfo`, `job`, `gang`, `money`, `metadata`, `items`, `position`, `name`, `phone`). |
| `provider` | function | Called as `provider(src, citizenid)`, returns `value` or `nil, errorString`. A thrown error or a returned error string is printed as a warning and the field is skipped for that player. The value is deep-cloned. |

**Returns**

- **true** — registered.
- **false, 'invalid or reserved PlayerData field'** — bad key.
- **false, 'provider must be callable'** — `provider` is not a function.
- **false, 'PlayerData field is already registered'** — this resource already owns the key.
- **false, 'PlayerData field is owned by &lt;resource>'** — another resource owns the key.

**Example**

```lua
exports.kora_core:registerPlayerDataField('housing', function(src, citizenid)
    local houses = getOwnedHouses(citizenid)
    return { owned = houses }
end)
```

**Representative console output**

```text
Returns true. Clients read it with exports.kora_core:getPlayerData({ 'housing' }).
```

#### `exports.kora_core:setPlayerDataField(src, key, value)`

Updates a replicated-only field registered by the calling resource and replicates it. Server authority must stay in the owning resource.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Source of an online player. |
| `key` | string | A key previously registered with `registerPlayerDataField`. |
| `value` | any | New value; `nil` clears it. |

**Returns**

- **true** — written.
- **false, 'PlayerData field is not registered'** — unknown key.
- **false, 'PlayerData field is owned by &lt;resource>'** — the caller is not the owner.
- **false, 'no such player' or 'player logout is in progress'** — from `setPath`.

**Example**

```lua
exports.kora_core:setPlayerDataField(src, 'housing', { owned = houses })
```

**Representative console output**

```text
Returns true.
```

#### `exports.kora_core:onChange(pathPrefix, handler)`

Subscribes to server-side PlayerData writes under a path prefix. The handler runs synchronously inside `setPath`, wrapped in pcall (errors are printed as `[kora_core:player] onChange handler errored`). It also fires for `silent` writes. The subscription is removed when the invoking resource stops.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `pathPrefix` | table | Key array such as `{ 'money' }` or `{ 'metadata', 'hunger' }`. A non-table value is wrapped as a single-key prefix. A write matches when its path starts with the prefix; a write to a shorter parent path (for example `{ 'money' }` against prefix `{ 'money', 'cash' }`) does not match. |
| `handler` | function | Called as `handler(src, path, value)`; `value` is nil for a delete. |

**Returns**

- **integer** — subscription id for `offChange`.
- **nil, 'handler must be callable'** — `handler` is not a function.

**Example**

```lua
local subId = exports.kora_core:onChange({ 'job' }, function(src, path, value)
    print(('job changed for %s at %s'):format(src, table.concat(path, '.')))
end)
```

**Representative console output**

```text
job changed for 12 at job
```

#### `exports.kora_core:offChange(id)`

Removes a subscription. There is no owner check: any resource can remove any id, so keep ids private.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | integer | Id returned by `onChange`. |

**Returns**

- **nothing** — unknown ids are ignored.

**Example**

```lua
exports.kora_core:offChange(subId)
```

**Representative console output**

```text
No output.
```

#### `exports.kora_core:login(src, citizenid, data)`

Logs a source in as an existing character using already-loaded data and adopts it. Yields (database checks). Trusted-caller only: there is no ownership check and `data` is not validated. `data.source` and `data.citizenid` are overwritten. Normal flows use the character-select module, which loads the row and checks the license.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Source to log in. |
| `citizenid` | string | Character id. |
| `data` | table | Decoded PlayerData (as returned by `getOfflinePlayerData`). |

**Returns**

- **true** — logged in and adopted.
- **false, 'source already logged in'** — the source has a character.
- **false, 'character already logged in'** — the character is online on another source (also re-checked after the database wait).
- **false, 'player data is busy'** — fenced by a durable operation.
- **false, 'player operation storage is unavailable'** — fence table could not be read.
- **false, 'player data changed while loading'** — the data was re-read after a fence and changed under the load.
- **false, 'not found' (or a SQL error string)** — re-read after a fence found no active row.
- **false, &lt;error>** — physical cash migration failed; the player is removed again (fail-closed).

**Example**

```lua
-- trusted server code only
local data, err = exports.kora_core:getOfflinePlayerData(citizenid)
if not data then return print('load failed: ' .. tostring(err)) end
if data.license ~= exports.kora_core:primary(src) then return end
local ok, loginErr = exports.kora_core:login(src, citizenid, data)
```

**Representative console output**

```text
Returns true. Sets state bags kora_core:loggedIn and isLoggedIn.
```

#### `exports.kora_core:createCharacter(src, charinfo, cid?)`

Creates and logs in a brand-new character. Yields. Safe to call with client input: charinfo is validated and normalised, the slot is computed server-side, the phone number is generated server-side. Grants starter-item eligibility in `metadata.starterItems`. Fresh data uses `Config.money.types`/`Config.money.default` for money (defaults cash 500, bank 5000, crypto 0), `Config.jobs.defaultJob` (default `unemployed`) at `Config.jobs.defaultGrade` (default 1), gang `none`, and spawn position (195.17, -933.77, 30.69, 144.0).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Source creating the character. |
| `charinfo` | table | `firstname` and `lastname` (required, trimmed, 1-24 characters, no control characters), `birthdate` (optional, `YYYY-MM-DD`, valid and not in the future, default `1990-01-01`), `gender` (optional, 0 or 1, default 0), `nationality` (optional, 2-32 characters, default `USA`). Any `phone` is ignored. |
| `cid?` | integer | Explicit slot (admin tools). Must be between 1 and the license's max characters and free. Omit to take the lowest free slot. Must be a number: a non-number raises a Lua error. |

**Returns**

- **citizenid** — string id of the new, logged-in character.
- **nil** — second return value is the reason: 'source already logged in'.
- **nil, 'character creation already in progress'** — a second call for the same source while one is running.
- **nil** — second return value is the reason: 'invalid first name' or 'first name must be between 1 and 24 characters'; same pattern for 'last name' (1-24) and 'nationality' (2-32).
- **nil** — second return value is the reason: 'birth date must be a valid non-future YYYY-MM-DD date'.
- **nil** — second return value is the reason: 'gender must be 0 or 1'.
- **nil, 'could not resolve primary identifier'** — no identifier of the configured kind.
- **nil, 'requested character slot is unavailable'** — `cid` out of range or taken.
- **nil, 'character limit reached'** — no free slot under the license cap.
- **nil, &lt;error>** — database insert failure (including a citizenid collision; there is no retry) or physical-cash migration failure.

**Example**

```lua
local citizenid, err = exports.kora_core:createCharacter(src, {
    firstname = 'Ada', lastname = 'Stone', birthdate = '1994-03-12', gender = 1,
})
if not citizenid then return print('create failed: ' .. err) end
```

**Representative console output**

```text
Returns "QX81ZK02". On failure: nil, "gender must be 0 or 1".
```

#### `exports.kora_core:logout(src, options?)`

Saves a complete snapshot, waits for the SQL queue to confirm it, then logs the character out and evicts it. Yields. If the save cannot be confirmed the player stays logged in and any temporary position change is rolled back. Sends client event `QBCore:Client:OnPlayerUnload` and fires local `QBCore:Server:OnPlayerUnload` (src).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Source of an online player. |
| `options?` | table | `{ position = { x, y, z, h? } }` sets the saved position. Restricted to the kora_housing resource (and kora_core itself); all values must be finite numbers, `h` defaults to 0.0. |

**Returns**

- **true** — logged out and evicted.
- **false** — no such player (no reason string).
- **false** — second return value is the reason: 'player logout is in progress'.
- **false, 'invalid logout options'** — `options` is not a table.
- **false, 'logout position is restricted to housing'** — position supplied by another resource.
- **false, 'invalid logout position'** — non-finite or missing coordinates.
- **false, 'player data is busy' or 'player operation storage is unavailable'** — fenced, or fence storage unreadable.
- **false, 'player session changed'** — the source or character was replaced while saving.
- **false, &lt;error>** — the save or SQL flush failed.

**Example**

```lua
local ok, err = exports.kora_core:logout(src)
if not ok then print('logout failed: ' .. tostring(err)) end
```

**Representative console output**

```text
Returns true; Player(src).state['kora_core:loggedIn'] is false afterwards.
```

#### `exports.kora_core:dropPlayer(src, reason?)`

Handles a disconnect: saves the player immediately (immediate-priority queue, unconditional: `Config.persistence.saveOnDrop` is not read), fires events, evicts from every cache. Called by kora_core on `playerDropped`. It does not disconnect the player, so it is not a kick; calling it for a connected player strips their character session.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Source. |
| `reason?` | string | Drop reason passed to the events. |

**Returns**

- **nothing** — silently returns when `src` is not logged in.

**Example**

```lua
-- done automatically on playerDropped; shown for completeness
exports.kora_core:dropPlayer(src, 'Exiting')
```

**Representative console output**

```text
Local events in order: QBCore:Server:PlayerDropped (src, reason), QBCore:Server:OnPlayerUnload (src), kora_core:server:playerDropped (src, citizenid, reason).
```

#### `exports.kora_core:isCoreReady()`

Readiness marker set one tick after the player module loads.

**Parameters**



**Returns**

- **boolean** — true once the core is up, false before.

**Example**

```lua
while not exports.kora_core:isCoreReady() do Wait(100) end
```

**Representative console output**

```text
true
```

#### `exports.kora_core:getIdentifiers(src)`

Collects a source's identifiers by kind with the `kind:` prefix removed. When a kind repeats (for example `license` and `license2` are distinct kinds) the first is kept. The endpoint is added as `ip` when no `ip:` identifier exists.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player source. |

**Returns**

- **table&lt;string,string>** — for example `{ license = '...', discord = '...', ip = '...' }`. Empty or ip-less when the source is not connected.

**Example**

```lua
local ids = exports.kora_core:getIdentifiers(src)
print(ids.license, ids.discord)
```

**Representative console output**

```text
a1b2c3... 123456789012345678
```

#### `exports.kora_core:primary(src)`

Returns the identifier value of kind `Config.identity.primaryIdentifier` (default `license`), the key that groups a player's characters.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player source. |

**Returns**

- **string** — the identifier value.
- **nil** — not connected or no identifier of that kind.

**Example**

```lua
local license = exports.kora_core:primary(src)
if not license then return end
```

**Representative console output**

```text
a1b2c3d4e5f6...
```

#### `exports.kora_core:generateCitizenId()`

Generates a candidate citizenid: `Config.identity.citizenIdPrefix` (default empty) plus `Config.identity.citizenIdLength` (default 8) random A-Z0-9 characters. Not checked for uniqueness: the database unique index rejects a collision on insert.

**Parameters**



**Returns**

- **string** — candidate id.

**Example**

```lua
local candidate = exports.kora_core:generateCitizenId()
```

**Representative console output**

```text
QX81ZK02
```

#### `exports.kora_core:recordIdentifiers(citizenid, ids)`

Queues an upsert of identifiers into `player_identifiers` (key: citizenid + kind, column `value`). Entries with a false or nil value are skipped. Batched write: returns before the database commits.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `citizenid` | string | Character id. |
| `ids` | table&lt;string,string> | Map of kind to value, as returned by `getIdentifiers`. |

**Returns**

- **nil** — Returns nothing.

**Example**

```lua
exports.kora_core:recordIdentifiers(citizenid, exports.kora_core:getIdentifiers(src))
```

**Representative console output**

```text
No output.
```

#### `exports.kora_core:findByIdentifier(kind, value)`

Finds every citizenid that has ever recorded an identifier, for ban and alt detection. Yields.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `kind` | string | Identifier kind, for example `license` or `discord`. |
| `value` | string | Identifier value without the prefix. |

**Returns**

- **string[]** — matching citizenids; empty when none match or the query failed (errors are swallowed).

**Example**

```lua
local ids = exports.kora_core:getIdentifiers(src)
local matches = exports.kora_core:findByIdentifier('discord', ids.discord)
print(#matches .. ' characters on this Discord account')
```

**Representative console output**

```text
3 characters on this Discord account
```

#### `exports.kora_core:recordDiscord(src)`

Stores the source's Discord id on its `users` row (keyed by the primary identifier). Yields. No-op when `Config.identity.saveDiscord` is false (default true), the player has no primary identifier or no Discord identifier, or the id equals the last value saved this session.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player source. |

**Returns**

- **nil** — Returns nothing.

**Example**

```lua
exports.kora_core:recordDiscord(src)
```

**Representative console output**

```text
No output.
```

#### `exports.kora_core:getDiscord(license)`

Reads the Discord id stored for a license. Yields.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `license` | string | Primary identifier value. |

**Returns**

- **string** — Discord id.
- **nil** — no row or no Discord id stored.

**Example**

```lua
local discord = exports.kora_core:getDiscord(license)
```

**Representative console output**

```text
123456789012345678
```

#### `exports.kora_core:getMaxCharacters(license)`

Returns the character-slot cap for a license: its `users.max_characters` override if set, otherwise `Config.identity.maxCharacters` (default 5). Creates the `users` row (INSERT IGNORE) if it does not exist. Yields.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `license` | string | Primary identifier value. |

**Returns**

- **integer** — slot cap.

**Example**

```lua
local slots = exports.kora_core:getMaxCharacters(license)
```

**Representative console output**

```text
5
```

#### `exports.kora_core:setMaxCharacters(license, maxCharacters?)`

Sets or clears a per-license slot override (for example a VIP allowance). Yields. No validation and no caller restriction: the column is an unsigned tinyint and database errors are not surfaced.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `license` | string | Primary identifier value. |
| `maxCharacters?` | integer | New cap; omit or nil to clear the override and fall back to the config default. |

**Returns**

- **nil** — Returns nothing.

**Example**

```lua
exports.kora_core:setMaxCharacters(license, 8)   -- VIP
exports.kora_core:setMaxCharacters(license)      -- back to default
```

**Representative console output**

```text
No output.
```

### Common use cases

- Read a player's job or money from a server script with `getPlayerData` instead of cloning the whole table.
- Run code whenever a player's job changes with `onChange({ 'job' }, handler)`.
- Expose a resource's own data (for example owned houses) to client UI with `registerPlayerDataField` and `setPlayerDataField`.
- Build a custom character selector that lists, creates and selects characters with `createCharacter` and the character-select module.

### Limits and related APIs

getPlayer, getPlayerByCitizenId and getAllPlayers deep-clone on every call. Cached snapshots go stale: re-read after changes. Replicated-only fields are not persisted. `login` and `logout` yield on the database; do not call them inside tight loops.

### Related guides

- [Persistence and schema](./persistence.md)
- [Replication and the client mirror](./replication.md)
- [Money](./money.md)
- [Jobs](./jobs.md)
- [Metadata](./metadata.md)
- [Characters](./characters.md)
- [Inventory](./inventory.md)

## Client

Client-side reads over the replicated PlayerData mirror kept by the replication module. The server is authoritative; the client holds a read-only copy that is nil until the first snapshot arrives and nil again after unload.

Namespace: `exports.kora_core` · Source: `modules/player/client.lua`

### Functions

Client player exports.

#### `exports.kora_core:getPlayerData(path?)`

Reads the local PlayerData mirror, or a value inside it. Inside kora_core the result is a live reference; across the export boundary it is a copy, so mutating it never changes the mirror.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `path?` | table | Array of keys such as `{ 'job', 'name' }`. Omit for the whole mirror. |

**Returns**

- **any** — the mirror or the value at `path`.
- **nil** — no snapshot received yet (or the character is unloaded), or nothing at that path.

**Example**

```lua
local job = exports.kora_core:getPlayerData({ 'job', 'name' })
if job == 'police' then showPoliceHud() end
```

**Representative console output**

```text
police
```

#### `exports.kora_core:isWearingGloves()`

Checks whether the local ped wears gloves, using the legacy drawable lists `QBCore.Shared.MaleNoGloves` / `FemaleNoGloves` against torso drawable 3. Uses the male list for model `mp_m_freemode_01`, the female list otherwise.

**Parameters**



**Returns**

- **boolean** — true when the current torso drawable is not in the no-gloves list.

**Example**

```lua
if not exports.kora_core:isWearingGloves() then
    print('fingerprints left behind')
end
```

**Representative console output**

```text
true
```

#### `exports.kora_core:onPlayerDataChange(pathPrefix, handler)`

Subscribes to local mirror changes under a path prefix; fires once per applied delta op. Removed automatically when the subscribing resource stops.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `pathPrefix` | table | Key array such as `{ 'money' }`. A non-table value is wrapped as one key. |
| `handler` | function | Called as `handler(path, value)`; `value` is nil for a delete. |

**Returns**

- **integer** — subscription id.
- **nil** — second return value is the reason: 'handler must be callable'.

**Example**

```lua
local subId = exports.kora_core:onPlayerDataChange({ 'money' }, function(path, value)
    updateCashDisplay(path[2], value)
end)
```

**Representative console output**

```text
Handler receives { "money", "cash" }, 450.
```

#### `exports.kora_core:offPlayerDataChange(id)`

Removes a subscription.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | integer | Id returned by `onPlayerDataChange`. |

**Returns**

- **nil** — Returns nothing.

**Example**

```lua
exports.kora_core:offPlayerDataChange(subId)
```

**Representative console output**

```text
No output.
```

### Related guides

- [Replication and the client mirror](./replication.md)

## Implementation notes and quick reference

The server keeps one authoritative record per logged-in character. Other resources
never receive the live record: every read returns a deep copy, and every write goes
through `setPath` (or a wrapper such as `addMoney`, `setJob`, `setMetaData`,
`addItem`).

### PlayerData shape

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

### Writing: the funnel

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

Prefer the domain wrappers ([Money](./money.md), [Jobs](./jobs.md),
[Metadata](./metadata.md), [Inventory](./inventory.md)); they validate input
and fire the legacy events.

### Reading

| Export (server) | Returns |
| --- | --- |
| `getPlayer(src)` | Deep copy of PlayerData, or `nil`. |
| `getPlayerByCitizenId(citizenid)` | Deep copy for an online character, or `nil`. |
| `getPlayerData(src, path)` | Value at `path` (tables are copied); the whole copy when `path` is `nil`. |
| `getPlayers()` | Array of online sources with a loaded character. |
| `getAllPlayers()` | Array of copies for every loaded character. |
| `isCoreReady()` | `true` once the first server frame after boot has run. |

### Subscribing to changes (server)

```lua
local id = exports.kora_core:onChange({ 'money' }, function(src, path, value)
    print(src, table.concat(path, '.'), value)
end)
exports.kora_core:offChange(id)
```

The handler receives `(src, path, value)`. A string prefix is wrapped into a
one-element array. Handlers are protected with `pcall` and are removed when the
registering resource stops.

### Resource-owned replicated fields

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

### Character lifecycle

#### Selecting and creating

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
`getMaxCharacters(license)` (see [Identity and utilities](./characters.md#users)).
An explicit `cid` is accepted only if it is a free slot within the cap; otherwise
the next free slot is used. Errors include `character limit reached`,
`requested character slot is unavailable`, `source already logged in` and
`character creation already in progress`.

#### Login

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

#### Logout

`logout(src, options)` keeps the connection and yields until kora_sql confirms a
save of every mutable column. Only then are both login state bags cleared,
`QBCore:Client:OnPlayerUnload` and `QBCore:Server:OnPlayerUnload` fired and the
character evicted. If the save fails or is uncertain, the character stays loaded
and the call returns `false, reason`; always check the result.

`options.position` (`x`, `y`, `z`, optional `h`) is accepted only from
`kora_housing` or kora_core itself and must be finite numbers. Never forward client
coordinates.

#### Drop

On `playerDropped`, kora_core saves the player immediately, fires
`QBCore:Server:PlayerDropped(src, reason)` and `QBCore:Server:OnPlayerUnload(src)`
while the player can still be read, evicts the character and then fires
`kora_core:server:playerDropped(src, citizenid, reason)`. `dropPlayer(src, reason)`
is the same routine.

#### Other helpers

| Export | Description |
| --- | --- |
| `savePlayer(src, requiredField)` | Queue an immediate save. With `requiredField`, refuses when that field's column is fenced. Returns `true` or `false, err`. |
| `setPlayerBucket(src, bucket)` | Sets the routing bucket, the replicated `instance` state bag and the legacy `QBCore.Player_Buckets` entry, and fires `kora_voice:server:bucketChanged`. |
| `getStarterItems()` | Copy of `QBCore.Shared.StarterItems`. |
