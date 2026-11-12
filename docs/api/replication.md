---
title: "Replication and the client mirror"
sidebar_position: 13
---


# Replication and the client mirror

## Server

Server side of PlayerData replication. It has no exports: the functions are internal and are driven by the player funnel. Each `setPath` queues an op; ops are coalesced per player and flushed once per tick as a single numbered delta, and a full snapshot is sent on login or on request.

Namespace: `exports.kora_core` · Source: `modules/replication/server.lua`

### How it works

Wire ops are `{ p = keyArray, v = value }` or `{ p = keyArray, d = true }` for a delete. Within a tick the last write to a path wins, and overlapping paths collapse (a write to a parent replaces queued child ops; a write to a child of a queued parent re-reads the parent value). Each flushed batch increments a per-player `seq`; the client uses it to detect a lost batch.

### Events

`kora_core:rep:snapshot` (server to client): `(seq, PlayerData)`, sent on adoption (login or character creation) and in response to a resync. `kora_core:rep:delta` (server to client): `(seq, ops)`, sent on the next tick after changes (`SetTimeout(0)`), only when at least one op remains. `kora_core:rep:resync` (client to server, no arguments): asks for a fresh snapshot.

### Resync rate limit

A resync is served at most once per `Config.replication.resyncRateLimit` ms (default 5000) per citizenid. Requests inside the window are dropped silently with no reply, and requests from a source with no logged-in character are ignored. The limiter entry is cleared when the player is forgotten (logout or drop). The client cannot influence the data in the snapshot, only how often it is resent.

### Hooks

If the money module defines a mirror hook, the physical-cash balance is added to the ops of each flush and to snapshots before sending, so clients see the inventory-owned cash as PlayerData.money.

### Related guides

- [Player data and lifecycle](./player.md)
- [Money](./money.md)

## Client

Holds the local PlayerData mirror: nil until the first snapshot, updated by numbered deltas, with a sequence check that asks the server for a resync when a batch is missed. It also publishes the legacy-shaped data to `QBCore.PlayerData` and fires the legacy client events from the mirror (locally, never over the network).

Namespace: `exports.kora_core` · Source: `modules/replication/client.lua`

### How it works

On `kora_core:rep:snapshot` the mirror is replaced, `expectedSeq` is set to the snapshot seq, local event `kora_core:client:playerLoaded` (mirror) fires and the legacy events fire. On `kora_core:rep:delta` a batch is applied only when `seq == expectedSeq + 1`; otherwise the client counts a resync and sends `kora_core:rep:resync` (a delta before any snapshot also requests a resync). `expectedSeq` is not advanced on a gap, so every later delta requests again until the server (rate-limited) sends a snapshot.

### Legacy events fired locally

After each snapshot or delta: `QBCore:Player:SetPlayerData` (legacy-shaped data, plus an internal re-fire token) when `Config.compat.fireLegacyPlayerDataEvent` is true (default). When a batch contains only `items` ops and `Config.compat.inventoryPlayerDataEventInterval` is above 0 (default 250 ms), that event is coalesced into one trailing call. `QBCore:Client:OnJobUpdate` (job) and `QBCore:Client:OnGangUpdate` (gang) fire when the root changed and `Config.compat.jobUpdateEventSource` is not `server` (default `client`). `QBCore:Client:OnPlayerUpdated` (key, value, token) fires for `job` and `gang` under the same condition. A snapshot counts as a job and gang change.

### Trust caveat for the inbound handlers

Both `QBCore:Player:SetPlayerData` and `QBCore:Client:OnPlayerUnload` are registered with `RegisterNetEvent`, so they accept the server's net triggers and local triggers from any client resource. A foreign `SetPlayerData` with a table argument replaces the contents of the mirror (a console warning names the writing resource), and `OnPlayerUnload` empties the mirror and resets the sequence. Both are ignored when they originate from kora_core itself or carry the internal re-fire token. This only changes what the local client scripts see; the server data is untouched. The injected data survives until the next server snapshot (login or a served resync): deltas keep applying on top of it. Client-side checks on PlayerData must never be treated as authoritative.

### Unload

`QBCore:Client:OnPlayerUnload` clears the mirror table in place (held references see it empty), sets the mirror to nil, `expectedSeq` to 0 and `stats.seq` to 0.

### Subscriber cleanup

Subscribers registered with `onChange` are removed on `onClientResourceStop` of the owning resource.

### Functions

Client exports. `exports.kora_core:getPlayerData` and `onPlayerDataChange` in the player module are thin wrappers over `getData` and `onChange`.

#### `exports.kora_core:reannounceFull()`

Re-fires the legacy full-blob event `QBCore:Player:SetPlayerData` from the current mirror without modifying it, and refreshes `QBCore.PlayerData`. Use this instead of a raw TriggerEvent of that event (which would be treated as a foreign write). Cancels a pending coalesced inventory announcement.

**Parameters**



**Returns**

- **true** — announced (or suppressed because `Config.compat.fireLegacyPlayerDataEvent` is false).
- **false** — no mirror yet.

**Example**

```lua
if exports.kora_core:reannounceFull() then
    print('legacy listeners refreshed')
end
```

**Representative console output**

```text
true
```

#### `exports.kora_core:getData(path?)`

Reads the mirror or a value inside it. Same-VM callers get a live reference; callers through exports get a copy.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `path?` | table | Array of keys. Omit for the whole mirror. |

**Returns**

- **any** — the mirror or value at `path`.
- **nil** — no mirror yet, or nothing at that path.

**Example**

```lua
local items = exports.kora_core:getData({ 'items' })
```

**Representative console output**

```text
{ [1] = { name = "water", amount = 2, slot = 1 } }
```

#### `exports.kora_core:onChange(pathPrefix, handler)`

Subscribes to mirror changes under a prefix; the handler fires for each delta op as it is applied (before the rest of the batch is applied), pcall-wrapped (errors printed as `[kora_core:rep] onChange errored`). Removed when the invoking resource stops.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `pathPrefix` | table | Key array. A non-table value is wrapped as one key. |
| `handler` | function | `handler(path, value)`; `value` is nil for a delete op. |

**Returns**

- **integer** — subscription id.
- **nil** — second return value is the reason: 'handler must be callable'.

**Example**

```lua
local id = exports.kora_core:onChange({ 'metadata', 'hunger' }, function(path, value)
    setHungerBar(value)
end)
```

**Representative console output**

```text
Handler receives { "metadata", "hunger" }, 72.
```

#### `exports.kora_core:offChange(id)`

Removes a subscription.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | integer | Id returned by `onChange`. |

**Returns**

- **nil** — Returns nothing.

**Example**

```lua
exports.kora_core:offChange(id)
```

**Representative console output**

```text
No output.
```

#### `exports.kora_core:requestResync()`

Asks the server for a fresh snapshot by triggering `kora_core:rep:resync`. The server rate-limits to one per `Config.replication.resyncRateLimit` ms (default 5000) and silently ignores the rest.

**Parameters**



**Returns**

- **nil** — Returns nothing.

**Example**

```lua
exports.kora_core:requestResync()
```

**Representative console output**

```text
A kora_core:rep:snapshot arrives if the request was served.
```

#### `exports.kora_core:getStats()`

Returns replication counters for diagnostics.

**Parameters**



**Returns**

- **table** — `{ seq, resyncs, opsApplied, lastDeltaAt }`: last applied sequence, number of seq-gap resyncs requested, number of ops applied, and `GetGameTimer()` ms of the last applied delta (0 if none). Not reset on unload except `seq`.

**Example**

```lua
local stats = exports.kora_core:getStats()
print(stats.seq, stats.resyncs, stats.opsApplied)
```

**Representative console output**

```text
42 0 311
```

### Related guides

- [Player data and lifecycle](./player.md)
- [Compatibility](./compatibility.md)

## Client mirror (code-derived)

### Client mirror

Each client holds a live copy of its own PlayerData, updated by deltas
(`{ p = path, v = value }` or `{ p = path, d = true }`) that the server coalesces
per player per frame. Each batch carries a sequence number; a gap or a delta before the first
snapshot makes the client request a resync (rate-limited by
`Config.replication.resyncRateLimit`).

```lua
-- client
local cash = exports.kora_core:getPlayerData({ 'money', 'cash' })

local id = exports.kora_core:onPlayerDataChange({ 'metadata', 'hunger' }, function(path, value)
    updateHungerBar(value)
end)
exports.kora_core:offPlayerDataChange(id)
```

| Client export | Description |
| --- | --- |
| `getPlayerData(path)` / `getData(path)` | Value at `path`, or the live mirror table when `path` is `nil` (`nil` before the first snapshot). Paths are key arrays. |
| `onPlayerDataChange(prefix, handler)` / `onChange(prefix, handler)` | Subscribe; `handler(path, value)` runs for every applied op under the prefix. |
| `offPlayerDataChange(id)` / `offChange(id)` | Unsubscribe. |
| `requestResync()` | Ask for a fresh snapshot. |
| `getStats()` | `seq`, `resyncs`, `opsApplied`, `lastDeltaAt`. |
| `reannounceFull()` | Re-fire the legacy `QBCore:Player:SetPlayerData` from the current mirror. Returns `false` before the first snapshot. |
| `isWearingGloves()` | `true` unless the arms drawable is in the stock no-glove lists. |

On every snapshot the client fires `kora_core:client:playerLoaded(mirror)`. Legacy
events (`QBCore:Player:SetPlayerData`, `QBCore:Client:OnJobUpdate`, ...) are fired
locally from the mirror; see [Compatibility](./compatibility.md#client-playerdata).
