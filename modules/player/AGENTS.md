# player module guide

## Purpose
The authoritative in-memory player cache and the **single mutation funnel** (`Core.player.setPath`) that every data change in the framework passes through, plus the player lifecycle (login / create / logout / drop). Concentrating all writes in one funnel is the central design decision of kora_core: dirty-tracking, delta replication, and change subscriptions are each implemented exactly once.

## Public API
Server:
- `Core.player.setPath(src, path, value, opts)` — **the funnel.** Write PlayerData at a key-array path; marks the DB column dirty, queues a delta, fires subscribers. `(true)` / `(false, err)`.
- `Core.player.getPlayer(src)` / `getPlayerByCitizenId(citizenid)` — deep-cloned snapshot or `nil`.
- `Core.player.getPlayerData(src, path)` — sub-path read (cloned if a table), or full clone with no path.
- `Core.player.getPlayers()` / `getAllPlayers()` — source ids / cloned snapshots of everyone online.
- `Core.player.onChange(pathPrefix, handler)` / `offChange(id)` — prefix-matched `handler(src, path, value)`.
- `Core.player.registerPlayerDataField(key, provider)` / `setPlayerDataField(src, key, value)` — resource-owned, replicated-only root fields for client read models backed by another resource's authoritative store.
- `Core.player.login(src, citizenid, data)` / `createCharacter(src, charinfo, cid)` / `logout(src)` / `drop(src, reason)` — lifecycle.
- `Core.player.setPlayerBucket(src, bucket)` / `savePlayer(src)` — native routing with legacy tracking, and immediate save of the live player handle.
- `Core.player.getStarterItems()` — a snapshot of the configured starter item definitions.
- `Core.player.isCoreReady()` — first-frame readiness marker.

Client:
- `Core.player.isWearingGloves()` — uses the legacy drawable lists and preserves their behavior.
- `Core.player.getPlayerData(path)` — read the replicated mirror (wraps `Core.replication.getData`).
- `Core.player.onPlayerDataChange(pathPrefix, handler)` / `offPlayerDataChange(id)` — wrap `Core.replication.onChange/offChange`.

## Design — the funnel
`setPath(src, path, value, opts)` does four things, in order, every time:
1. `Core.util.pathSet(PlayerData, path, value)` — the actual write.
2. `Core.persistence.markDirty(player, COLUMN_FOR[path[1]])` — mark the owning DB column dirty (only if the root key maps to a column).
3. `Core.replication.queueOp(player, path, value)` — queue a client delta (unless `opts.silent`).
4. Fire every subscriber whose `prefix` is a prefix of `path`, `pcall`-guarded.

Because all of `Core.money`/`jobs`/`metadata`/`inventory` are wrappers that end in a `setPath` call, none of them re-implement persistence or replication.

## Implementation notes
- **`COLUMN_FOR` (shared realm) is the persistence gate at the root level.** It maps a PlayerData root key to a DB column: `charinfo`, `job`, `gang`, `money`, `metadata`, `items`→`inventory`, `position`, `name`, `phone`→`phone_number`. A root key *not* in the map never marks anything dirty, so it doesn't persist (the compat `SetPlayerData` shim warns when a write targets an unmapped root). `license`/`cid` are intentionally absent — they are immutable after creation and must never appear in a save write-set (the schema has two unique keys; writing them risks corruption). It lives in `shared.lua` so client-side shape checks and the server funnel agree.
- **Reads deep-clone; the live handle never crosses an export.** `getPlayer` etc. return `Core.util.deepClone(PlayerData)`. The live `Player` handle is reachable only via `CoreInternal.player.handle(src)` — used by the wrapper modules and compat, never exported. This is the modern-API stance: no shared mutable `Player` object handed across resources.
- **Two caches, kept in lockstep.** `bySource[src]` and `byCitizenId[cid]` both point at the same handle; `adopt`/`logout`/`drop` add or evict from both. They're published on `CoreInternal.player` so persistence/replication/money/jobs/etc. reach handles without a second lookup table.
- **External PlayerData fields are read models, not persistence.** A registering resource owns its non-core root key, hydrates it before the initial snapshot, and is the only resource allowed to update it through `setPlayerDataField`. The field has no `COLUMN_FOR` entry, so kora_core never writes it to `players`; the owner must keep authority in its own database/cache and treat the client copy as untrusted presentation data.
- **Subscriptions match by path prefix.** `pathMatchesPrefix(path, prefix)` compares element-by-element. A bare-string prefix is normalised to a one-element array. The handler receives the *full* changed path so it can discriminate leaves.
- **Lifecycle fires both legacy and modern events.** `adopt` triggers `QBCore:Server:PlayerLoaded` + `QBCore:Client:OnPlayerLoaded` (legacy, both realms) *and* `kora_core:server:playerLoaded` (modern), then primes the client mirror with a snapshot. `logout`/`drop` mirror this with unload/drop events. `drop` is wired to FiveM's `playerDropped`.
- **`createCharacter` seeds the encoded baseline** (`Core.persistence.seedEncoded`) right after insert so the very first flush is a no-op — nothing changed since the row was written.
- **Character identity is normalized before slot/insert work.** Names and nationality are bounded visible UTF-8, birth dates are real/non-future `YYYY-MM-DD`, gender is restricted to the two supported freemode models, and phone is generated server-side. Never pass arbitrary client `charinfo` through to `freshData`.
- **`_dirty`/`_encoded`/`_pendingOps`/`_seq`** on the handle are owned by persistence and replication respectively; the player module only initialises them.
- **Internals on `CoreInternal.player`** — `COLUMN_FOR`, `bySource`, `byCitizenId`, `handle`, `freshData`, `buildJob`, `buildGang`. Never exported: `build/finalise.lua` walks only `Core.<module>` and skips `_`-prefixed functions.

## Best practices
- Mutate player data only through `setPath` or a `Core.money`/`jobs`/`metadata`/`inventory` wrapper. Writing `PlayerData` directly (even on the live handle) bypasses dirty-tracking and replication.
- Never persist or mutate `license`/`cid`. They are the account/character keys.
- Treat the result of any read as a snapshot — it will not reflect subsequent changes, and mutating it does nothing.
