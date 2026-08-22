# Replication module

## Overview
Keeps each client's local `PlayerData` mirror in sync with the server using a **delta protocol** instead of resending the whole blob on every change. The funnel queues ops; the server coalesces them per-player-per-frame and ships a sequenced batch; the client applies them in order, detecting a dropped batch via the sequence number and requesting a resync. Legacy full-blob events are re-fired **client-side** from the already-mirrored table, so every legacy listener keeps working at zero network cost. Functions are split across realms and exported flat as `exports.qbcore:<fn>`.

## Wire shape
- **Snapshot** (`qbcore:rep:snapshot`): `seq, PlayerData` — full state; resets the client's expected seq.
- **Delta** (`qbcore:rep:delta`): `seq, ops` where each op is `{ p = keyArray, v = value }` or `{ p = keyArray, d = true }` for a delete.

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
local cash = exports.qbcore:getData({ 'money', 'cash' })
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
exports.qbcore:onChange({ 'metadata', 'hunger' }, function(path, value)
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
- **The free legacy-event trick.** `QBCore:Player:SetPlayerData` / `QBCore:Client:OnJobUpdate` / `OnGangUpdate` are re-fired **on the client** from the mirror table — a pure in-VM reference pass, no network cost — so legacy resources listening for the old full-blob events keep working unchanged. Which ones fire is gated by `Config.compat`.
- **Inbound legacy writes are tolerated but warned.** If a foreign resource `TriggerEvent`s the full-blob `QBCore:Player:SetPlayerData` with a *different* table, the mirror accepts it but prints a warning — the write bypassed the delta stream and will be overwritten on the next server snapshot. The module ignores its own re-fired event (same table reference) to avoid a loop.
- **Mirror is `nil` until the first snapshot.** A delta arriving before any snapshot triggers an immediate resync request.
