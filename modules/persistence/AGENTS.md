# persistence module guide

## Purpose
Persist player data with the minimum writes: dirty-column tracking, a byte-identical change gate, throttled position sampling, and a coalescing flush into `qbsql`'s `enqueueMany`. `migrate.lua` runs qbcore's own schema migrations at boot. Server only. Loaded **before** `player.lua` because `player.login`/`createCharacter` call the internal `_adopt`/`_seedEncoded`/`_insertNew` helpers at runtime.

## Public API
Public functions are exported flat:
- `Core.persistence.flushAll()` — sample positions, collect dirty rows, one batched enqueue; returns count.
- `Core.persistence.getOfflinePlayerData(citizenid)` — decoded character snapshot, without a legacy Player object.
- `Core.persistence.saveOfflinePlayer(data, fields)` — update only requested mutable columns of an offline character; never inserts or changes license/cid.
- `Core.persistence.beginPlayerColumnOperation(key, citizenids, columns)` / `finishPlayerColumnOperation(token, values)` / `abortPlayerColumnOperation(token)` / `getPlayerColumnOperations()` — yielding durable-provider fence API; see docs.md.
- `Core.persistence.saveNow(player)` — immediate single-player flush (drop/logout), immediate priority.

## Internal (not exported)
These are `_`-prefixed and are **not** part of the public export surface — `build/finalise.lua` skips any `_`-prefixed function even on a `Core.<module>` table. They are called only by the player funnel, the player lifecycle, and the multichar module:
- `Core.persistence._markDirty(player, column)` — mark a column dirty (called by the funnel).
- `Core.persistence._adopt(player)` / `_seedEncoded(player)` / `_forget(player)` — lifecycle hooks + encoded-baseline seeding.
- `Core.persistence._insertNew(citizenid, license, cid, data)` — plain INSERT for a new character (yields). `(true)` / `(false, err)`.
- `Core.persistence._load(citizenid)` — decode a character blob (yields). `(table)` / `(nil, err)`.
- `Core.persistence._listCharacters(license)` — character summaries for a select screen (yields).
- `Core.persistence._deleteCharacterRow(citizenid)` — soft-delete (yields).

File-local (not even on a `Core`/`CoreInternal` table): `COLUMN_SOURCE`, `dirty`, `posState`, `encodeColumn`, `samplePosition`, `collectRows`.

## Design — the two gates
A dirty column reaches the DB only when **both** are true:
1. **Gate 1 — dirty.** The funnel called `_markDirty` for the column since the last flush (`player._dirty[column]`).
2. **Gate 2 — changed.** The column's freshly-encoded JSON differs byte-for-byte from `player._encoded[column]` (the last-persisted baseline). Identical JSON is dropped and never enqueued.

Gate 1 alone would still write "set to same value" churn; Gate 2 eliminates it. This is why the highest-churn writes (metadata hunger/thirst/stress ticks) cost nothing when they land on the current value.

## Implementation notes
- **`_encoded` is the baseline the change gate compares against.** `_seedEncoded` fills it from current `PlayerData` on adopt (and after a fresh insert, so the first flush is a no-op). `collectRows`/`saveNow` update it in place whenever they emit a column, so the next comparison is against what actually hit the wire.
- **Column encoding is centralised in `encodeColumn`.** Most columns are `json.encode(PlayerData[srcKey])`; `position`/`name`/`phone_number` have bespoke encoders (position is normalised to `{x,y,z,h}`, name/phone are scalar-ish). `COLUMN_SOURCE` maps a column back to its PlayerData root (inverse of `COLUMN_FOR`, minus the special cases).
- **Position sampling is throttled by movement and age.** `samplePosition` reads the ped at flush time (server-side OneSync coords) and only marks position dirty if the player moved ≥ `positionEpsilon` (compared squared, to avoid a sqrt) or `positionMaxAge` elapsed. `posState[cid]` holds the last persisted coords + timestamp. A parked player never re-writes position.
- **Coalescing flush = one boundary crossing.** `flushAll` gathers all dirty players into a single `QB.sql.enqueueMany('players', 'citizenid', rows, {mode='assign'})`. The flush thread waits `interval ± intervalJitter` (jitter avoids a thundering herd) and, if anything flushed, calls `QB.sql.flush('players')` to nudge qbsql to drain rather than wait its own interval.
- **Immediate paths bypass the interval.** `saveNow` enqueues one row at `priority='immediate'`. txAdmin `serverShuttingDown` and a `scheduledRestart` with ≤60s remaining call `flushEveryoneNow`; `onResourceStop` does a final best-effort drain.
- **Bounded, not guaranteed, durability.** FXServer gives no guarantee the `onResourceStop` yield completes, so the design *bounds* worst-case loss to one `interval`, it doesn't eliminate it. That's the tuning knob (`Config.persistence.interval`, default 60s). Documented in docs.md so operators understand the trade.
- **New characters use a plain INSERT, not an upsert.** `_insertNew` wants a `(license,cid)`/`citizenid` collision to *raise* (so a duplicate can be retried with a fresh citizenid) rather than silently overwrite a different player's row.
- **`license`/`cid` are triple-guarded against persistence.** Absent from `COLUMN_FOR` (can't be marked dirty), and explicitly skipped in both `collectRows` and `saveNow`. The `players` table has two unique keys (`citizenid` and `(license,cid)`); writing these as mutable data risks cross-row corruption.
- **`migrate.lua`** loads `sql/*.sql` via `LoadResourceFile`, checksums each version Lua-side (a 64-bit FNV-1a forward+reversed rendered to hex, padded to `CHAR(64)` — FiveM Lua has no SHA and only change-*detection* per version is needed), and hands them to `QB.sql.migrate`, which aborts on a checksum mismatch for an already-applied version. `sql/003_generated_columns.sql` is appended only when `Config.persistence.generatedColumns` is on. On success it warms qbsql's prepared-statement cache with the hot player queries and fires `qbcore:server:databaseReady`. This runs at boot.
- **Legacy `players` tables are upgraded in place.** `sql/006_legacy_players.sql` adds the scalar phone and soft-delete columns expected by this rebuild when migration v1 previously encountered an existing qb-core table. Both columns are nullable, so old character rows remain intact; `_load` falls back to the phone embedded in legacy `charinfo`.
- **Legacy vehicle finance stays loadable.** `sql/007_legacy_vehicle_finance.sql` idempotently adds qb-vehicleshop's financing columns to `player_vehicles`, preventing an imported or core-created table from breaking the stock vehicleshop's startup finance query.
- **Database startup races recover in place.** The migration worker retries its readiness wait instead of permanently skipping schema setup after 60 seconds. qbsql reconnects transient network failures; once it becomes ready, migrations continue without restarting FXServer.
- **The internal helpers stay internal.** Genuinely private cross-file helpers elsewhere use `CoreInternal.<module>`; here the persistence internals sit on `Core.persistence` but are `_`-prefixed, which `build/finalise.lua` skips just the same. The ordinary save APIs and the four durable-provider fence APIs above are public.

## Best practices
- Don't call `flushAll`/`saveNow` on a hot path — the funnel + periodic flush already do the right thing. Reserve `saveNow` for genuine "must be on disk now" moments.
- If you add a new persisted root key, add it to `COLUMN_FOR` (player/shared) *and* give it an encoder path here, or it silently won't save.
- Set `Config.persistence.interval` with the bounded-loss caveat in mind — it's your worst-case crash window.

- `operations.lua` fences money/inventory/metadata against queued saves and ordinary writers.
  Migration 10 persists fences across core restarts. Never release an uncertain
  operation without joining the old SQL worker and reconciling a durable receipt.
