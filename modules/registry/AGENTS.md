# registry module guide

## Purpose
A generic runtime-registry factory backing the six shared lists (`items`/`vehicles`/`jobs`/`gangs`/`weapons`/`locations`). It exists to serve the legacy `QBCore.Shared.*` tables as plain in-VM lookups on both realms while still allowing live add/update/remove that propagates to every resource and client. The server is authoritative; clients and other server resources hold mirrors kept in sync by a delta/snapshot protocol.

## Public API
- `Core.registry.getShared(name, key)` — Record by key (materialised-table lookup). Shared.
- `Core.registry.allShared(name)` — Live dense array of records (do not mutate). Shared.
- `Core.registry.countShared(name)` — Record count. Shared.
- `Core.registry.sharedSnapshotAll()` — Snapshot of every registry for mirror seeding. Shared.
- `Core.registry.registerShared(name, key, record)` — Add/update one record; owner-tracked; broadcasts a delta. Server. Returns `(true)` or `(false, err)`.
- `Core.registry.registerManyShared(name, records)` — Bulk register; returns count. Server.
- `Core.registry.unregisterShared(name, key)` — Remove one record; broadcasts. Server.
- `Core.registry.onSharedChange(name, handler)` — Subscribe `handler(action, key, record, previous)`; owner-tracked on server. Both realms. Returns `(subId)` or `(nil, err)`.
- `Core.registry.offSharedChange(name, subId)` — Unsubscribe. Both realms.
- `Core.registry.registerShared(name, key)` — Client stub that refuses (server owns writes).

## Design — the three tables per registry
Each registry holds **three** structures over the same records:
1. **`list`** — a dense, insertion-ordered array. Powers `allShared` and iteration.
2. **`index`** — `key → position in list`. Makes add/update/remove O(1).
3. **`materialised`** — `key → record`. This *is* `QBCore.Shared.Items` etc.; legacy code reads it directly.

Reads (`getShared`, `QBCore.Shared.*`) are plain hash lookups on `materialised`. Nothing hits the network per read.

## Implementation notes
- **The materialised table is cleared in place, never reassigned.** Legacy code captures it once (`local Items = QBCore.Shared.Items`). `RI.reseed` therefore does `for k in pairs(r.materialised) do r.materialised[k] = nil end` and refills the same table object — a fresh table would orphan every captured reference. `list`/`index` are internal and *are* replaced wholesale on reseed, which is fine because nothing outside the module holds them.
- **Swap-remove keeps the array dense but destabilises order.** `RI.remove` moves the last element into the freed slot and fixes its `index` entry, so removal is O(1) — but iteration order after any removal is not the original insertion order. This is a deliberate trade (dense array + O(1) removal over stable ordering); documented in docs.md so callers key off the record's key field, not a list position.
- **Epoch + reseed drives client resync.** Every registry has an `epoch`; a full reseed bumps it. The client delta handler compares the incoming epoch to its own and, on any mismatch for a non-`remove` action, discards the delta and requests a fresh snapshot rather than applying onto a stale mirror. This is the recovery path for a missed broadcast.
- **Owner-tracked sweep via `QB.resources.serverRegistry`.** Both registered records (`ownedRecords[resource][name][key]`) and subscribers (`sub.resource`) are tagged with the invoking resource. When that resource stops, the sweep callback unregisters its records (through `_unregisterInternal`, which does the removal + broadcast without owner bookkeeping) and drops its subscribers — so a resource restart neither leaks stale records nor double-registers.
- **Two broadcast channels per delta.** `broadcast()` fires a local `TriggerEvent('qbcore:registry:delta', …)` (other server resources' mirrors) *and* `TriggerClientEvent('qbcore:registry:delta', -1, …)` (all clients). The client also requests a full snapshot (`qbcore:registry:requestSnapshot` → `qbcore:registry:snapshotAll`) on resource start.
- **Seeds are applied silently at boot.** `server.lua` ingests `QBCoreSeed.*` via `RI.apply` directly (no broadcast), so epochs begin at `0` with seeds present and the first client snapshot already carries them.
- **Internals live on `CoreInternal.registry` (`RI`)** — `create`/`reg`/`apply`/`remove`/`reseed`/`dispatch`/`snapshot`/`snapshotAll`/`isCallable`. They are never exported: `build/finalise.lua` walks only `Core.<module>` tables and additionally skips any `_`-prefixed function (e.g. `Core.registry._unregisterInternal`).

## Best practices
- Register on the **server**. Client-side `registerShared` is refused by design.
- Don't cache a list index; key off `record[keyField]` because swap-remove reorders `list`.
- Keep `onSharedChange` handlers cheap and defensive — they run inline (pcall-guarded) inside the dispatch loop.
