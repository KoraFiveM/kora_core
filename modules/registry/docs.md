# Registry module

## Overview
The shared-lists engine behind `items`, `vehicles`, `jobs`, `gangs`, `weapons`, and `locations`. Each named registry keeps a dense insertion-ordered array plus a key→position index. The server is authoritative; clients mirror it over a delta/snapshot protocol. Modern code always reads records through getters. Legacy `QBCore.Shared.*` indexed tables are live compatibility views, not registry storage. All functions are defined on `Core.registry` and exported flat as `exports.qbcore:<fn>`.

The registry names and their key fields:

| name        | key field |
|-------------|-----------|
| `items`     | `name`    |
| `vehicles`  | `model`   |
| `jobs`      | `name`    |
| `gangs`     | `name`    |
| `weapons`   | `name`    |
| `locations` | `key`     |

## API

### `Core.registry.getShared(name, key)` — shared
Returns the record for `key` in registry `name`, or `nil`. This is a local index lookup; it does not cross the network.

#### Parameters
- `name: string` — Registry name (`'items'`, `'jobs'`, …).
- `key: string`

#### Returns
- `table | nil` — The record, or `nil` if absent.

#### Example
```lua
local water = exports.qbcore:getShared('items', 'water')
```

### `Core.registry.allShared(name)` — shared
Returns the **live** dense array of records for `name`. Do not mutate it. Fetch it when constructing each UI/admin list rather than caching a derived list. Its table reference survives full resyncs, but iteration order is **not stable across removals** (see Notes).

#### Parameters
- `name: string`

#### Returns
- `table[]` — The live list (empty table if `name` is unknown).

### `Core.registry.countShared(name)` — shared
Returns the number of records in `name`.

#### Parameters
- `name: string`

#### Returns
- `integer`

### `Core.registry.sharedSnapshotAll()` — shared
Returns a snapshot of every registry — `{ [name] = { epoch, keyField, records } }`. Used to seed an external resource's mirror (`@qbcore/init.lua`).

#### Returns
- `table`

### `Core.registry.registerShared(name, key, record)` — server
Registers or updates one record. `record[keyField]` is filled in from `key` if absent, and must match `key` if present. The write is applied, subscribers fire, and a delta is broadcast to every other server resource and every client. The registration is **owner-tracked**: the latest successful registering resource owns the record, and its stop sweeps the record. Stopping a previous owner leaves the replacement intact.

#### Parameters
- `name: string`
- `key: string`
- `record: table`

#### Returns
- `boolean` — `true` on success, `false` on failure.
- `string | nil` — The failure reason (unknown registry, non-table record, or key mismatch).

#### Example
```lua
local ok, err = exports.qbcore:registerShared('items', 'my_widget', {
    name = 'my_widget', label = 'Widget', weight = 100, type = 'item',
})
if not ok then print(err) end
```

### `Core.registry.registerManyShared(name, records)` — server
Registers many records at once. Each record must carry its own key field. Returns how many were registered.

#### Parameters
- `name: string`
- `records: table[]`

#### Returns
- `integer` — Count registered.

### `Core.registry.unregisterShared(name, key)` — server
Removes `key` from `name`, dispatches a `'remove'` to subscribers, and broadcasts the removal. Clears the record's current ownership regardless of which resource calls unregister.

#### Parameters
- `name: string`
- `key: string`

#### Returns
- `boolean` — `true` if a record was removed.

### `Core.registry.onSharedChange(name, handler)` — server & client
Subscribes to changes in `name`. `handler(action, key, record, previous)` where `action` is `'add'`, `'update'`, or `'remove'`. On the server the subscription is owner-tracked (swept when the registering resource stops). Handlers are `pcall`-wrapped so one faulty handler never breaks a registration.

#### Parameters
- `name: string`
- `handler: fun(action: string, key: string, record: table|nil, previous: table|nil)`

#### Returns
- `integer | nil` — A subscription id, or `nil` on failure.
- `string | nil` — The failure reason (unknown registry, or non-callable handler).

#### Example
```lua
exports.qbcore:onSharedChange('jobs', function(action, key, record, previous)
    if action == 'remove' then
        print('job removed:', key)
    end
end)
```

### `Core.registry.offSharedChange(name, subId)` — server & client
Removes a subscription by the id `onSharedChange` returned.

#### Parameters
- `name: string`
- `subId: integer`

### `Core.registry.registerShared(name, key)` — client (refused)
Client-side registration is **not supported** — the server owns the registries. The client stub logs a warning and returns `false, 'client-side registration is not supported'`.

## Notes
- **Getter-first.** New code must call `getShared(name, key)` for individual records and `allShared(name)` whenever it constructs a list. Do not index or capture `QBCore.Shared.Jobs`, `Items`, and friends; those maps exist only for unchanged legacy resources.
- **Compatibility views remain live.** The legacy maps are rebuilt in place after runtime mutations and resyncs, so old resources keep working without defining the modern contract.
- **Reads are free.** `getShared`/`QBCore.Shared.*` are plain table lookups on the mirror; there is no per-read network round trip on either realm.
- **Removal is O(1) via swap-remove, which reorders the array.** The removed slot is backfilled with the last element and its index fixed up, so `allShared(name)` iteration order changes after any removal. Never assume a stable index into the list across removals; key off `record[keyField]`.
- **Epoch + resync.** Each registry carries an `epoch`. A full reseed bumps it. If a client receives a delta whose epoch doesn't match its own (and the action isn't a `remove`), the mirror is assumed stale and the client pulls a fresh snapshot instead of applying the delta onto stale data.
- **Two broadcast channels.** The server emits each delta as both a local `TriggerEvent` (reaching every other server resource's mirror) and a `TriggerClientEvent(-1)` (reaching every client).
- **Default data uses runtime registration** at boot, through the same validation/change/replication funnel as records added later by other resources.
