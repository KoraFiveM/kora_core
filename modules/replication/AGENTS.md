# replication module guide

## Purpose
Ship `PlayerData` changes to clients as **deltas** rather than whole-blob resends, with per-frame coalescing and a sequence-number safety net, and keep the local mirror that all client-side reads (`Core.player.getPlayerData`, `Core.jobs.getJob`, `Core.inventory.getInventory`, …) go through. Loaded before `player.lua` because `Core.player.adopt` calls into it.

## Public API
Server:
- `Core.replication.queueOp(player, path, value)` — queue one op (called by the funnel); coalesces per path per frame; `nil` → delete.
- `Core.replication.sendSnapshot(player)` — full state to one client; resets client seq.
- (`adopt`/`forget` are lifecycle hooks called by `player.lua`, not part of the public surface people call.)

Client:
- `Core.replication.getData(path)` — read the mirror (live ref with no path).
- `Core.replication.onChange(pathPrefix, handler)` / `offChange(id)` — prefix-matched `handler(path, value)`.
- `Core.replication.requestResync()` — force a snapshot.
- `Core.replication.getStats()` — `{ seq, resyncs, opsApplied, lastDeltaAt }`.

## Design — the delta protocol
Legacy qb-core resends the entire `PlayerData` on every field change. Here each change is an op `{ p = keyArray, v = value }` (or `{ p, d = true }` for a delete). The funnel calls `queueOp`; a single frame-end `SetTimeout(0)` drains every player with pending ops, assigning each drained batch a new per-player `seq`. The client applies ops in order and, before applying, checks `seq == expected + 1`.

## Implementation notes
- **Per-frame coalescing keyed by path.** `_pendingOps` is a map keyed by `opKey(path)` (`table.concat(path, '\31')`). The unit separator `\31` is used, not `.`, because item and metadata keys legitimately contain dots — a `.` join would alias distinct paths. Last write in the frame wins, so a hunger tick that writes the same leaf 30 times sends one op. The path array is *copied* into the op because the caller may reuse/mutate it.
- **One flush drains everyone.** `pendingPlayers` is a set of citizenids; `scheduleFlush` arms a single `SetTimeout(0)` that iterates it, so N players with pending ops cost one timer, not N.
- **Seq gap → resync, never blind apply.** A mismatched `seq` (or a delta before any snapshot) makes the client fire `qbcore:rep:resync` and wait for a fresh snapshot, rather than applying a delta onto a mirror that already missed a batch. The server rate-limits resync service per citizenid (`Config.replication.resyncRateLimit`) so a desynced client can't storm it.
- **Legacy notification cost and timing.** `fireLegacy` updates `QBCore.PlayerData` immediately and re-emits the full legacy payload locally. CFX serializes local events too, so inventory-only `QBCore:Player:SetPlayerData` notifications are coalesced for `Config.compat.inventoryPlayerDataEventInterval` ms (default 250; 0 restores every-delta timing). The timer starts on the first change and emits current data even during continuous firing. Snapshots, non-inventory changes, and explicit `reannounceFull()` emit immediately and invalidate the pending timer; unload and foreign legacy writes invalidate it too. Mirror reads and `onChange` dispatch stay immediate. Job/gang events retain their existing timing and `Config.compat.jobUpdateEventSource` gate.
- **Loop guard on inbound legacy writes.** Our own full legacy event includes a string token that survives CFX's payload copy; the inbound handler ignores that token. A foreign write is accepted in place but warned, because it bypassed the delta stream and dies on the next snapshot.
- **Snapshot resets expected seq.** `qbcore:rep:snapshot` replaces the mirror wholesale and sets `expectedSeq = seq`, re-baselining the sequence after a load or resync.
- **Client-side `onChange` is local and in-VM** (separate from the server's `Core.player.onChange`); it dispatches as each op is applied, `pcall`-guarded so one bad handler doesn't break the batch.
- **No `CoreInternal.replication` table.** The server keeps its state in file-local upvalues (`pendingPlayers`, `flushScheduled`, `lastResync`) and the client in locals (`mirror`, `expectedSeq`, `stats`, `subscribers`). Lifecycle hooks `adopt`/`forget` sit on `Core.replication` but are only meaningful internally. Internals in other modules use `CoreInternal.<module>`; `build/finalise.lua` exports only non-`_` `Core.<module>` functions.

## Best practices
- Never emit deltas by hand — go through the funnel, which calls `queueOp`.
- On the client, read through `getData`/the `Core.player`/`Core.jobs`/`Core.inventory` wrappers and subscribe with `onChange`; don't cache the mirror reference across a resync (a snapshot replaces the table object).
- Keep `onChange` handlers cheap — they run inline per applied op.
