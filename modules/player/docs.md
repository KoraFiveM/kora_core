# Player module

## Overview
The authoritative player cache and the **single mutation funnel**, `Core.player.setPath`. Every money / job / metadata / inventory change in the whole framework routes through `setPath`, so dirty-tracking, delta replication, and `onChange` subscribers are all handled in exactly one place. Reads return **deep-cloned snapshots**, never the live handle, so an external resource can't mutate `PlayerData` out from under the funnel. Functions are split across realms (server = the funnel + lifecycle; client = mirror reads) and exported flat as `exports.qbcore:<fn>`.

## API

### `Core.player.setPath(src, path, value, opts)` — server
**The single mutation entry point.** Writes `value` into `PlayerData` at `path`, marks the owning DB column dirty, queues a client delta, and fires every subscriber whose prefix matches `path`. Use this (or a higher-level wrapper like `Core.money.addMoney`) for *all* player-data mutation.

#### Parameters
- `src: integer`
- `path: (string|integer)[]` — A non-empty key array, e.g. `{ 'money', 'cash' }` or `{ 'metadata', 'hunger' }`.
- `value: any` — `nil` becomes a delete on the wire.
- `opts: table | nil` — `{ silent = true }` skips replication (rare).

#### Returns
- `boolean` — `true` on success.
- `string | nil` — Failure reason (`'no such player'`, or a bad path).

#### Example
```lua
local ok, err = exports.qbcore:setPath(src, { 'metadata', 'stress' }, 20)
```

### `Core.player.getPlayer(src)` — server
Returns a **deep-cloned** snapshot of a source's `PlayerData`, or `nil`. Safe to cross the export boundary; mutating the returned table does nothing to the real player.

#### Parameters
- `src: integer`

#### Returns
- `table | nil`

### `Core.player.getPlayerByCitizenId(citizenid)` — server
Same as `getPlayer` but keyed by citizenid. Returns a deep clone or `nil`.

#### Parameters
- `citizenid: string`

#### Returns
- `table | nil`

### `Core.player.getPlayerData(src, path)` — server
Reads a sub-path of a player's data without cloning the whole blob. With no `path`, returns a full clone. A table result is deep-cloned; a scalar is returned directly.

#### Parameters
- `src: integer`
- `path: (string|integer)[] | nil`

#### Returns
- `any`

#### Example
```lua
local hunger = exports.qbcore:getPlayerData(src, { 'metadata', 'hunger' })
```

### `Core.player.getPlayers()` — server
Returns the source ids of every online player.

#### Returns
- `integer[]`

### `Core.player.getAllPlayers()` — server
Returns a deep-cloned snapshot of every online player's `PlayerData`.

#### Returns
- `table[]`

### `Core.player.onChange(pathPrefix, handler)` — server
Subscribes to changes under a path prefix. `handler(src, path, value)` fires whenever a `setPath` whose `path` starts with `pathPrefix` lands. Handlers are `pcall`-wrapped.

#### Parameters
- `pathPrefix: (string|integer)[]` — e.g. `{ 'money' }` or `{ 'metadata', 'hunger' }`. A bare string is wrapped into a one-element array.
- `handler: fun(src: integer, path: table, value: any)`

#### Returns
- `integer | nil` — Subscription id.
- `string | nil` — Failure reason (non-callable handler).

#### Example
```lua
exports.qbcore:onChange({ 'money' }, function(src, path, value)
    print(('%s money.%s = %s'):format(src, path[2], value))
end)
```

### `Core.player.offChange(id)` — server
Removes a server-side subscription by id.

#### Parameters
- `id: integer`

### `Core.player.login(src, citizenid, data)` — server
Logs a source in with already-loaded `data` (from `Core.persistence.load`). Builds the `Player` handle, adopts it into the caches, sends the initial PlayerData snapshot, then replicates `Player(src).state['qbcore:loggedIn'] = true`. Legacy load events are retained for compatibility. Returns `(true)` or `(false, err)`.

#### Parameters
- `src: integer`
- `citizenid: string`
- `data: table` — Decoded `PlayerData`.

#### Returns
- `boolean`, `string | nil`

### `Core.player.createCharacter(src, charinfo, cid)` — server
Creates a brand-new character: resolves the primary identifier, builds a fresh `PlayerData`, inserts the row, records identifiers, and adopts the player. **Yields** (DB insert). Returns the new `citizenid`, or `(nil, err)`.

#### Parameters
- `src: integer`
- `charinfo: table` — `{ firstname, lastname, birthdate, gender, nationality, phone, … }`.
- `cid: integer | nil` — Character slot (default `1`).

#### Returns
- `string | nil` — The citizenid.
- `string | nil` — Failure reason.

### `Core.player.logout(src)` — server
Logs a source out (keeps the connection, drops the character). Flushes to DB first, replicates `Player(src).state['qbcore:loggedIn'] = false`, fires unload events, and evicts from every cache.

#### Parameters
- `src: integer`

#### Returns
- `boolean`

### `Core.player.drop(src, reason)` — server
Handles a hard disconnect: immediate flush, then eviction. Wired to the `playerDropped` event, so you rarely call it directly.

#### Parameters
- `src: integer`
- `reason: string | nil`

### `Core.player.isCoreReady()` — server
Returns whether the core has finished its first-frame init — a readiness marker for consumers and `@qbcore/init.lua`.

#### Returns
- `boolean`

### `Core.player.getPlayerData(path)` — client
Client-side read of the local replicated mirror. With no `path`, returns the full local `PlayerData` (a live reference); with a `path`, the value at it.

#### Parameters
- `path: (string|integer)[] | nil`

#### Returns
- `any`

### `Core.player.onPlayerDataChange(pathPrefix, handler)` — client
Subscribes to local mirror changes under a prefix. `handler(path, value)`. Thin wrapper over `Core.replication.onChange`.

#### Parameters
- `pathPrefix: (string|integer)[]`
- `handler: fun(path: table, value: any)`

#### Returns
- `integer | nil`, `string | nil`

### `Core.player.offPlayerDataChange(id)` — client
Removes a client-side subscription by id.

#### Parameters
- `id: integer`

## The QBPlayer handle
Internally each online player is a `Player` handle (never exported — reads clone out of it). Its fields:

- `source: integer` — Current server source.
- `citizenid: string` — Character key.
- `license: string` — Primary identifier (immutable).
- `cid: integer` — Character slot.
- `PlayerData: table` — The live data blob: `citizenid`, `license`, `cid`, `name`, `money`, `charinfo`, `job`, `gang`, `position`, `metadata`, `items`, `phone`, `source`.
- `_dirty: table` — DB columns changed since the last flush.
- `_encoded: table` — Baseline of each column's last-persisted JSON (the byte-compare gate).
- `_pendingOps: table` — Replication ops coalesced this frame.
- `_seq: integer` — Replication sequence counter.

## Notes
- **Everything funnels through `setPath`.** `Core.money`, `Core.jobs`, `Core.metadata`, and `Core.inventory` are all thin wrappers that ultimately call it — which is why they get dirty-tracking and replication "for free".
- **Reads clone; the handle never leaves.** `getPlayer`/`getPlayerByCitizenId`/`getPlayerData`/`getAllPlayers` all deep-clone. There is no exported way to get the live handle — that's `CoreInternal.player.handle(src)`, used only by in-resource modules and compat.
- **`onChange` matches by prefix.** `{ 'money' }` catches every account write; `{ 'metadata', 'hunger' }` catches only hunger. The full changed `path` is passed to the handler so it can tell which leaf changed.
- **`COLUMN_FOR` decides persistence.** Only root keys present in that map (`charinfo`/`job`/`gang`/`money`/`metadata`/`items`→`inventory`/`position`/`name`/`phone`) persist. `license`/`cid` are deliberately absent and never enter a save write-set.
