# Persistence module

## Overview
Saves player data to the database with the **minimum** possible writes: per-column dirty tracking, a byte-identical change gate, position sampling with a movement/age throttle, and a coalescing flush that batches every dirty player into a single `qbsql` `enqueueMany`. Legacy qb-core re-encodes and rewrites all seven JSON columns on every save regardless of what changed; here a column reaches the wire only when it is **both dirty and actually different**. Server only. `migrate.lua` runs the schema migrations at boot.

Most of this module is internal machinery driven by the player funnel and lifecycle — only two functions are public exports. Both are defined on `Core.persistence` and exported flat as `exports.qbcore:<fn>`.

## API

### `Core.persistence.flushAll()`
Samples positions for everyone online, collects the dirty rows through both gates, and enqueues them in one `enqueueMany`. This is the periodic flush (run automatically on the flush loop); it can also be called on demand. Returns the number of players flushed.

#### Returns
- `integer` — Players whose rows were enqueued this flush.

#### Example
```lua
local flushed = exports.qbcore:flushAll()
```

### `Core.persistence.saveNow(player)`
Immediate save of one player (the drop / logout path): samples position, applies the two gates, and enqueues at **immediate** priority so qbsql drains it out of band.

#### Parameters
- `player: table` — The live player handle (from `CoreInternal.player.handle(src)`).

## Notes
- **The two gates.** A column is written only if (1) it's marked **dirty** since the last flush *and* (2) its freshly-encoded JSON is **byte-different** from the `_encoded` baseline. Gate 2 catches "set to the same value" churn — a hunger tick landing on the current value writes nothing.
- **Position throttle.** Position is sampled at flush time from the ped; it's only marked dirty if the player moved past `Config.persistence.positionEpsilon` metres or `Config.persistence.positionMaxAge` ms elapsed. A parked player never re-writes position.
- **Coalescing flush.** `flushAll` batches every dirty player into a single `QB.sql.enqueueMany('players', …)` — one boundary crossing per interval, not one per player. The flush loop runs every `Config.persistence.interval` ms with `±intervalJitter` so saves don't thundering-herd, and nudges qbsql to drain promptly afterward.
- **Immediate-flush paths.** `saveNow` (drop/logout) enqueues at `immediate` priority. txAdmin shutdown (`serverShuttingDown`) and a scheduled restart within 60s flush everyone immediately, as does the resource-stop handler.
- **Bounded-durability caveat.** The `onResourceStop` final drain is best-effort with no guarantee FXServer lets the yield complete. This **bounds** worst-case data loss to one flush interval — it does not eliminate it. Tune `Config.persistence.interval` accordingly.
- **`license`/`cid` are never in a write-set.** They aren't in `COLUMN_FOR`, so nothing can mark them dirty; the collect/save paths also skip them explicitly as belt-and-braces (the schema's two unique keys make writing them a corruption hazard).
- **Deleted character slots are reusable.** Migration 8 applies uniqueness only to active character slots. Soft-deleted rows remain available for history, but no longer block creating a replacement character in the same slot.
- **Everything else is internal.** Dirty marking, the encoded baseline, new-character insert, character load/list, and soft-delete are all `_`-prefixed helpers on `CoreInternal`/`Core.persistence` (see AGENTS.md) — not exported, and reached only through the funnel, the player lifecycle, or the multichar module. Migrations run at boot from `migrate.lua`.
