# Replication module

## Overview
Keeps each client's local `PlayerData` mirror in sync with the server using a **delta protocol** instead of resending the whole blob on every change. The funnel queues ops; the server coalesces them per-player-per-frame and ships a sequenced batch; the client applies them in order, detecting a dropped batch via the sequence number and requesting a resync. Legacy full-blob events are re-fired **client-side** from the already-mirrored table, so every legacy listener keeps working at zero network cost. Functions are split across realms and exported flat as `exports.kora_core:<fn>`.

## Wire shape
- **Snapshot** (`kora_core:rep:snapshot`): `seq, PlayerData` — full state; resets the client's expected seq.
- **Delta** (`kora_core:rep:delta`): `seq, ops` where each op is `{ p = keyArray, v = value }` or `{ p = keyArray, d = true }` for a delete.

## API

### `Core.replication.queueOp(player, path, value)` — server
Queues one op for a player, called by the funnel. Coalesces by path within the frame (last value wins), so many writes to the same leaf in one frame collapse to one op. `value == nil` becomes a delete op. A frame-end `SetTimeout(0)` drains all pending players.

#### Parameters
- `player: table` — The live player handle.
- `path: (string|integer)[]`
- `value: any`

### `Core.replication.sendSnapshot(player)` — server
Sends a full snapshot to a player's client (initial load or resync) and resets the client's expected seq to the current server seq.

#### Parameters
- `player: table`

### `Core.replication.getData(path)` — client
Reads the local mirror: with no `path`, the whole `PlayerData` (a live reference, `nil` until the first snapshot); with a `path`, the value at it.

#### Parameters
- `path: (string|integer)[] | nil`

#### Returns
- `any`

#### Example
```lua
local cash = exports.kora_core:getData({ 'money', 'cash' })
```

### `Core.replication.onChange(pathPrefix, handler)` — client
Subscribes to local mirror changes under a prefix. `handler(path, value)` fires as each delta op is applied. Handlers are `pcall`-wrapped.

#### Parameters
- `pathPrefix: (string|integer)[]` — A bare string is wrapped into a one-element array.
- `handler: fun(path: table, value: any)`

#### Returns
- `integer | nil` — Subscription id.
- `string | nil` — Failure reason (non-callable handler).

#### Example
```lua
exports.kora_core:onChange({ 'metadata', 'hunger' }, function(path, value)
    updateHungerBar(value)
end)
```

### `Core.replication.offChange(id)` — client
Removes a subscription by id.

#### Parameters
- `id: integer`

### `Core.replication.requestResync()` — client
Manually asks the server for a fresh snapshot. Normally automatic (fired on a detected seq gap), but exposed for recovery.

### `Core.replication.getStats()` — client
Returns replication counters: `{ seq, resyncs, opsApplied, lastDeltaAt }`. Useful for diagnostics.

#### Returns
- `table`

## Notes
- **Coalescing.** 30 writes to `metadata.hunger` in one frame produce **one** op on the wire — the path is the coalescing key (`table.concat(path, '\31')`, using the unit separator because item/meta keys can contain `.`).
- **Sequence + resync.** Each player carries a `seq`; every non-empty batch bumps it. If the client receives `seq ≠ expected + 1`, it assumes a dropped batch and requests a resync rather than applying onto stale data. The server rate-limits resyncs per `Config.replication.resyncRateLimit`.
- **Legacy notifications.** The full `QBCore:Player:SetPlayerData` payload is re-fired locally, without a server-to-client full-blob resend. CFX still serializes local events. Inventory-only notifications therefore schedule current data for `Config.compat.inventoryPlayerDataEventInterval` ms after the first pending change (default 250; set 0 for every-delta timing). Continuous changes do not reset this timer; the callback runs on the next eligible client tick. This also applies to inventory transactions other than firing. The mirror, `QBCore.PlayerData`, `GetPlayerData()`, and modern `onChange` subscribers stay current on every applied delta. Non-inventory changes, snapshots, and explicit re-announcements notify immediately and cancel the pending notification; unload discards it. Job/gang event timing and all payloads stay unchanged. Event emission remains gated by `Config.compat`.
- **Inbound legacy writes are tolerated but warned.** A foreign full-blob legacy event is copied into the live mirror and warned about because it bypasses the delta stream and will be overwritten by the next server snapshot. It also cancels any pending notification. The module identifies its own copied re-fire by a string token to avoid a loop.
- **Mirror is `nil` until the first snapshot.** A delta arriving before any snapshot triggers an immediate resync request.
