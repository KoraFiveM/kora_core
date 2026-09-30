# registry module guide

## Purpose
A generic runtime-registry factory backing the six shared lists (`items`/`vehicles`/`jobs`/`gangs`/`weapons`/`locations`). The server is authoritative; clients and other server resources hold mirrors kept in sync by a delta/snapshot protocol. Modern code reads through getters. Legacy `QBCore.Shared.*` indexed maps are derived compatibility views, never registry storage.

## Public API
- `Core.registry.getShared(name, key)` — Record by key (index + dense-list lookup). Shared.
- `Core.registry.allShared(name)` — Live dense array of records (do not mutate). Shared.
- `Core.registry.countShared(name)` — Record count. Shared.
- `Core.registry.sharedSnapshotAll()` — Snapshot of every registry for mirror seeding. Shared.
- `Core.registry.registerShared(name, key, record)` — Add/update one record; owner-tracked; broadcasts a delta. Server. Returns `(true)` or `(false, err)`.
- `Core.registry.registerManyShared(name, records)` — Bulk register; returns count. Server.
- `Core.registry.unregisterShared(name, key)` — Remove one record; broadcasts. Server.
- `Core.registry.onSharedChange(name, handler)` — Subscribe `handler(action, key, record, previous)`; owner-tracked on server. Both realms. Returns `(subId)` or `(nil, err)`.
- `Core.registry.offSharedChange(name, subId)` — Unsubscribe. Both realms.
- `Core.registry.registerShared(name, key)` — Client stub that refuses (server owns writes).

## Design — the two tables per registry
Each registry holds **two** structures over the same records:
1. **`list`** — a dense, insertion-ordered array. Powers `allShared` and iteration.
2. **`index`** — `key → position in list`. Makes add/update/remove O(1).

`getShared` resolves `index[key]` into `list[position]`. Nothing hits the network per read. Compatibility builds its own live `QBCore.Shared.*` maps from this API and must stay outside new framework code.

## Implementation notes
- **The list is cleared in place, never reassigned.** Callers must fetch it through `allShared` when building a UI or derived collection, but keeping the table object stable means an accidental cached reference still observes a full reseed. The key index is internal and may be replaced.
- **Swap-remove keeps the array dense but destabilises order.** `RI.remove` moves the last element into the freed slot and fixes its `index` entry, so removal is O(1) — but iteration order after any removal is not the original insertion order. This is a deliberate trade (dense array + O(1) removal over stable ordering); documented in docs.md so callers key off the record's key field, not a list position.
- **Epoch + reseed drives client resync.** Every registry has an `epoch`; a full reseed bumps it. The client delta handler compares the incoming epoch to its own and, on any mismatch for a non-`remove` action, discards the delta and requests a fresh snapshot rather than applying onto a stale mirror. This is the recovery path for a missed broadcast.
- **Owner-tracked sweep via `QB.resources.serverRegistry`.** Both registered records (`ownedRecords[resource][name][key]`) and subscribers (`sub.resource`) are tagged with the invoking resource. Replacement transfers ownership to the latest registering resource. When that resource stops, the sweep callback unregisters its records (through `_unregisterInternal`, which clears ownership, removes the record, and broadcasts) and drops its subscribers — so a resource restart neither leaks stale records nor double-registers.
- **Two broadcast channels per delta.** `broadcast()` fires a local `TriggerEvent('qbcore:registry:delta', …)` (other server resources' mirrors) *and* `TriggerClientEvent('qbcore:registry:delta', -1, …)` (all clients). The client also requests a full snapshot (`qbcore:registry:requestSnapshot` → `qbcore:registry:snapshotAll`) on resource start.
- **Defaults use the runtime mutation funnel.** `server.lua` registers `QBCoreSeed.*` through `registerManyShared`, so validation, ownership, notifications, and replication are identical for defaults and later additions.
- **Internals live on `CoreInternal.registry` (`RI`)** — `create`/`reg`/`apply`/`remove`/`reseed`/`dispatch`/`snapshot`/`snapshotAll`/`isCallable`. They are never exported: `build/finalise.lua` walks only `Core.<module>` tables and additionally skips any `_`-prefixed function (e.g. `Core.registry._unregisterInternal`).

## Best practices
- Register on the **server**. Client-side `registerShared` is refused by design.
- Always call `getShared(name, key)` for a record. Do not index or capture `QBCore.Shared.Jobs`/`Items`/etc. in new code.
- Call `allShared(name)` when constructing an admin/UI list; do not cache a derived jobs/grades/options list across openings.
- Don't cache a list index; key off `record[keyField]` because swap-remove reorders `list`.
- Keep `onSharedChange` handlers cheap and defensive — they run inline (pcall-guarded) inside the dispatch loop.
