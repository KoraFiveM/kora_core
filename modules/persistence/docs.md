# Persistence module

## Overview
Saves player data to the database with the **minimum** possible writes: per-column dirty tracking, a byte-identical change gate, position sampling with a movement/age throttle, and a coalescing flush that batches every dirty player into a single `kora_sql` `enqueueMany`. Legacy qb-core re-encodes and rewrites all seven JSON columns on every save regardless of what changed; here a column reaches the wire only when it is **both dirty and actually different**. Server only. `migrate.lua` runs the schema migrations at boot.

Most of this module is internal machinery driven by the player funnel and lifecycle — four functions are public exports. Both are defined on `Core.persistence` and exported flat as `exports.kora_core:<fn>`.

## API

### `Core.persistence.flushAll()`
Samples positions for everyone online, collects the dirty rows through both gates, and enqueues them in one `enqueueMany`. This is the periodic flush (run automatically on the flush loop); it can also be called on demand. Returns the number of players flushed.

#### Returns
- `integer` — Players whose rows were enqueued this flush.

#### Example
```lua
local flushed = exports.kora_core:flushAll()
```

### `Core.persistence.saveNow(player)`
Enqueues one player at **immediate** priority: samples position and applies the two change gates. This call does not acknowledge a database commit. The logout lifecycle separately freezes mutations, enqueues a fresh complete mutable snapshot and awaits `Kora.sql.flush('players')`; a failed or uncertain flush retains the character and marks the snapshot retryable.

#### Parameters
- `player: table` — The live player handle (from `CoreInternal.player.handle(src)`).

## Notes
- **The two gates.** A column is written only if (1) it's marked **dirty** since the last flush *and* (2) its freshly-encoded JSON is **byte-different** from the `_encoded` baseline. Gate 2 catches "set to the same value" churn — a hunger tick landing on the current value writes nothing.
- **Position throttle.** Position is sampled at flush time from the ped; it's only marked dirty if the player moved past `Config.persistence.positionEpsilon` metres or `Config.persistence.positionMaxAge` ms elapsed. A parked player never re-writes position.
- **Coalescing flush.** `flushAll` batches every dirty player into a single `Kora.sql.enqueueMany('players', …)` — one boundary crossing per interval, not one per player. The flush loop runs every `Config.persistence.interval` ms with `±intervalJitter` so saves don't thundering-herd, and nudges kora_sql to drain promptly afterward.
- **Immediate-flush paths.** `saveNow` enqueues at `immediate` priority without a commit acknowledgement. Logout additionally awaits confirmation before unloading. txAdmin shutdown (`serverShuttingDown`) and a scheduled restart within 60s flush everyone immediately, as does the resource-stop handler.
- **Bounded-durability caveat.** The `onResourceStop` final drain is best-effort with no guarantee FXServer lets the yield complete. This **bounds** worst-case data loss to one flush interval — it does not eliminate it. Tune `Config.persistence.interval` accordingly.
- **`license`/`cid` are never in a write-set.** They aren't in `COLUMN_FOR`, so nothing can mark them dirty; the collect/save paths also skip them explicitly as belt-and-braces (the schema's two unique keys make writing them a corruption hazard).
- **Deleted character slots are reusable.** Migration 8 applies uniqueness only to active character slots. Soft-deleted rows remain available for history, but no longer block creating a replacement character in the same slot.
- **Everything else is internal.** Dirty marking, the encoded baseline, new-character insert, character load/list, and soft-delete are all `_`-prefixed helpers on `CoreInternal`/`Core.persistence` (see AGENTS.md) — not exported, and reached only through the funnel, the player lifecycle, or the multichar module. Migrations run at boot from `migrate.lua`.

## Offline character data

`exports.kora_core:getOfflinePlayerData(citizenid)` returns a decoded character snapshot or `(nil, reason)`. `exports.kora_core:saveOfflinePlayer(data, fields)` saves only the named mutable roots, such as `{ 'job' }`, and returns `(true)` or `(false, reason)`. Both yield. The save refuses online characters, immutable fields, and missing rows; it never inserts a character. Use the live player funnel for online characters.

## Durable provider column operations

Only `kora_banking` and `Config.inventory.provider` may use these flat server exports:

- `beginPlayerColumnOperation(key, citizenids, columns)` returns a token or
  `(nil, code, message)`. Columns are SQL names `money`, `inventory` and `metadata` (at most three).
  A ready existing operation returns `(token, 'resumed')`.
- `finishPlayerColumnOperation(token, values)` publishes confirmed database
  values and releases the fence; `values[citizenid][column]` must be a table for
  every requested character and column. Returns `(true)` or `(false, reason)`.
- `abortPlayerColumnOperation(token)` releases after confirmed rollback only.
- `getPlayerColumnOperations()` yields and returns the calling provider's
  `{token, operationKey, citizenids, columns, preparing}` records, including
  locks recovered from migration 10 after a core restart. Storage failure raises.

These calls yield. Begin fences ordinary mutations first, drains queued player
saves, then durably records the fence. Saves skip held columns; offline writes,
login and deletion cannot cross a pending operation. Finish updates live state and
its encoded baseline before deleting the durable fence. An uncertain begin,
transaction, finish or abort must remain pending until reconciliation succeeds.
A provider restart must join its old checked SQL worker before treating an absent
or pending receipt as rollback. Store the operation receipt atomically with both
source and destination changes, and never expose these calls as client events.
