---
title: "Shared registries and utilities"
sidebar_position: 11
---


# Shared registries and utilities

## Server

Runtime-updatable shared lists (items, vehicles, jobs, gangs, weapons, locations) that any resource can add to and listen to, plus the small pure helpers in `util`. The server is authoritative. Each change is broadcast as a delta: a local event reaches the `@kora_core/init.lua` mirror in every other server resource, and a net event reaches every client. A resource that registered records and then stops or restarts has its records removed and its subscriptions dropped, so nothing leaks or double-registers.

Namespace: `exports.kora_core` · Source: `modules/registry/shared.lua, modules/registry/server.lua, modules/util/shared.lua, init.lua`

### How it works

Each registry holds a dense array of records in insertion order plus a key lookup. After an unregister the order is not stable (swap-remove). Reads return live data (`allShared` returns the internal array); do not mutate it, use `registerShared`. Across an export call tables are copied, so a resource that needs fast repeated reads should use the `Kora.shared` mirror below instead of calling the export.

### Using the live mirror in your resource

1. **Load** — In fxmanifest add `shared_script '@kora_lib/init.lua'` then `shared_script '@kora_core/init.lua'`. The file asserts that `Kora` already exists.
2. **Seed** — On the server the mirror polls `exports.kora_core:sharedSnapshotAll()` every 25 ms, up to 200 tries (about 5 s), until kora_core answers. On the client it triggers `kora_core:registry:requestSnapshot` and reseeds on `kora_core:registry:snapshotAll`.
3. **Read** — `Kora.shared.get('items', 'water')` or `Kora.shared.all('jobs')`.
4. **Listen** — `Kora.shared.onChange(name, handler)`: handlers run in your VM when a delta arrives and die with your resource.
5. **Write** — `Kora.shared.register(name, key, record)` forwards to `registerShared` on kora_core; the change replicates back into every mirror.

### Terms used on this page

| Term | Meaning |
| --- | --- |
| Registry | One named list with a key field. Registries: `items` (key `name`), `vehicles` (key `model`), `jobs` (key `name`), `gangs` (key `name`), `weapons` (key `name`), `locations` (key `key`). |
| Record | A table whose key field equals the registration key. `registerShared` fills a missing key field from the key and rejects a mismatch. Jobs and gangs have `grades` normalised into a one-based array (legacy maps keyed `"0"`, `"1"` are converted, sorted by level). |
| Owner | The invoking resource of `registerShared` / `onSharedChange` (kora_core itself for seeds). Owned records are unregistered and owned subscribers removed when the owner stops. Re-registering a key transfers ownership to the latest caller. |
| Epoch | A number carried with every delta and snapshot so a mirror can detect that it missed a full re-seed. In this version the server never changes it: it stays 0, so the gap check does not trigger in practice. |
| Delta | One change, sent as `(name, action, key, record, epoch)` with `action` of `add`, `update` or `remove` (`record` is nil for remove). |
| Kora.shared | Consumer-side mirror installed into a resource's own Lua VM by `shared_script '@kora_core/init.lua'` (after `@kora_lib/init.lua`). Reads are local table lookups with no boundary crossing. |

### Replication channels

On every change the server fires local event `kora_core:registry:delta` (name, action, key, record, epoch) for other server resources and `TriggerClientEvent('kora_core:registry:delta', -1, ...)` for all clients. A client that detects an epoch mismatch on a non-remove delta triggers `kora_core:registry:requestSnapshot` instead of applying it.

### Net events

`kora_core:registry:requestSnapshot` (client to server, no arguments): replies to the sender with `kora_core:registry:snapshotAll` carrying every registry as `{ epoch, keyField, records }`. It is not rate-limited, needs no logged-in character and returns the full catalogues, so each call costs one full snapshot. `kora_core:registry:snapshotAll` and `kora_core:registry:delta` are server-to-client. kora_core's client also fires local `kora_core:registry:synced` after applying a snapshot. In consumer VMs the server-realm handlers for delta/snapshot are plain local events and are deliberately not net-registered there, so a client cannot inject records into a server mirror.

### Seeds

At load the server registers the six seed lists (`KoraCoreSeed.items`, `vehicles`, `jobs`, `gangs`, `weapons`, `locations`) through `registerManyShared`, owned by kora_core.

### Trust

Any resource can register, overwrite or unregister any record in any registry, including another resource's; there is no per-record permission. Clients cannot register: the client `registerShared` is a refusing stub.

### Functions

Server registry exports, then util exports (identical in both realms), then the consumer-side `Kora.shared` functions from init.lua (not exports).

#### `exports.kora_core:registerShared(name, key, record)`

Adds or replaces one record, dispatches local subscribers, then broadcasts the delta. The record table is modified in place (the key field is filled in). Ownership goes to the invoking resource.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Registry name: `items`, `vehicles`, `jobs`, `gangs`, `weapons` or `locations`. |
| `key` | string | Record key; must equal `record[keyField]` if that is set. |
| `record` | table | The record. For `jobs` and `gangs`, `grades` may be a legacy zero- or one-based map and is converted to an array. |

**Returns**

- **true** — registered (action `add` for a new key, `update` for an existing key).
- **false** — second return value is the reason: 'record must be a table'.
- **false** — second return value is the reason: 'no registry named "&lt;name>"'.
- **false** — second return value is the reason: 'record.&lt;keyField> (&lt;value>) does not match key (&lt;key>)'.

**Example**

```lua
local ok, err = exports.kora_core:registerShared('items', 'energy_bar', {
    name = 'energy_bar', label = 'Energy Bar', weight = 150, type = 'item',
})
if not ok then print(err) end
```

**Representative console output**

```text
Returns true. Subscribers and clients receive ('items', 'add', 'energy_bar', record, 0).
```

#### `exports.kora_core:registerManyShared(name, records)`

Registers an array of records, using each record's key field as its key. Records without a key, and records that fail validation, are skipped silently.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Registry name. |
| `records` | table[] | Array of records. |

**Returns**

- **integer** — number of records registered (0 when the registry name is unknown; no error string).

**Example**

```lua
local count = exports.kora_core:registerManyShared('jobs', {
    { name = 'taxi', label = 'Taxi', type = 'none', grades = { { name = 'Driver', payment = 60 } } },
})
```

**Representative console output**

```text
count == 1
```

#### `exports.kora_core:unregisterShared(name, key)`

Removes a record, then dispatches and broadcasts a `remove` delta. Raises a Lua error if `name` is not a registry.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Registry name. |
| `key` | string | Record key. |

**Returns**

- **true** — removed.
- **false** — no record with that key.

**Example**

```lua
exports.kora_core:unregisterShared('items', 'energy_bar')
```

**Representative console output**

```text
Returns true. Subscribers receive ('remove', 'energy_bar', nil, previousRecord).
```

#### `exports.kora_core:onSharedChange(name, handler)`

Subscribes to changes in a registry. Handlers are pcall-wrapped (errors printed as `[kora_core:registry] subscriber ... errored`) and are removed when the invoking resource stops.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Registry name. |
| `handler` | function | `handler(action, key, record, previous)`: `action` is `add`, `update` or `remove`; `record` is nil on remove; `previous` is the old record (nil on add). |

**Returns**

- **integer** — subscription id.
- **nil** — second return value is the reason: 'no such registry'.
- **nil** — second return value is the reason: 'handler must be callable'.

**Example**

```lua
local subId = exports.kora_core:onSharedChange('items', function(action, key, record)
    if action == 'remove' then clearCache(key) else cacheItem(key, record) end
end)
```

**Representative console output**

```text
Called with ('add', 'energy_bar', {...}, nil).
```

#### `exports.kora_core:offSharedChange(name, subId)`

Removes a subscription. No owner check.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Registry name. |
| `subId` | integer | Id returned by `onSharedChange`. |

**Returns**

- **nothing** — unknown names or ids are ignored.

**Example**

```lua
exports.kora_core:offSharedChange('items', subId)
```

**Representative console output**

```text
No output.
```

#### `exports.kora_core:getShared(name, key)`

Reads one record by key.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Registry name. |
| `key` | string | Record key. |

**Returns**

- **table** — the record.
- **nil** — unknown registry or key.

**Example**

```lua
local item = exports.kora_core:getShared('items', 'water')
if item then print(item.label, item.weight) end
```

**Representative console output**

```text
Water 500
```

#### `exports.kora_core:allShared(name)`

Returns the dense array of all records. Inside kora_core it is the live array; across an export it is a copy. Order is insertion order, not stable after removals.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Registry name. |

**Returns**

- **table[]** — records (empty table for an unknown registry).

**Example**

```lua
for _, job in ipairs(exports.kora_core:allShared('jobs')) do print(job.name) end
```

**Representative console output**

```text
unemployed
police
ambulance
```

#### `exports.kora_core:countShared(name)`

Returns the number of records in a registry.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Registry name. |

**Returns**

- **integer** — record count (0 for an unknown registry).

**Example**

```lua
print(exports.kora_core:countShared('items'))
```

**Representative console output**

```text
212
```

#### `exports.kora_core:sharedSnapshotAll()`

Snapshots every registry; used to seed `Kora.shared` mirrors. Large: the full catalogues.

**Parameters**



**Returns**

- **table** — map of registry name to `{ epoch = integer, keyField = string, records = table[] }`.

**Example**

```lua
local all = exports.kora_core:sharedSnapshotAll()
print(#all.items.records, all.items.keyField, all.items.epoch)
```

**Representative console output**

```text
212 name 0
```

#### `exports.kora_core:round(value, places?)`

Rounds half up (`floor(value * 10^places + 0.5) / 10^places`). Available in both realms.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | number | Number to round. A non-number returns 0. |
| `places?` | integer | Decimal places; omit to round to an integer. |

**Returns**

- **number** — rounded value; 0 when `value` is not a number.

**Example**

```lua
local price = exports.kora_core:round(12.3456, 2)
```

**Representative console output**

```text
12.35
```

#### `exports.kora_core:trim(value)`

Strips leading and trailing whitespace. Non-strings are returned unchanged. Available in both realms.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | string | String to trim. |

**Returns**

- **string** — trimmed string, or the input unchanged when it is not a string.

**Example**

```lua
local name = exports.kora_core:trim('  Ada  ')
```

**Representative console output**

```text
Ada
```

#### `exports.kora_core:splitStr(str, delimiter)`

Splits a string on a literal delimiter (pattern characters are escaped; the code accepts multi-character delimiters). Keeps empty parts. Both arguments must be strings or a Lua error is raised. Available in both realms.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `str` | string | Input. |
| `delimiter` | string | Literal separator. |

**Returns**

- **string[]** — parts in order.

**Example**

```lua
local parts = exports.kora_core:splitStr('a,b,,c', ',')
```

**Representative console output**

```text
{ "a", "b", "", "c" }
```

#### `exports.kora_core:randomStr(length)`

Random string of uppercase letters A-Z (`math.random`, not cryptographic). Both realms.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `length` | integer | Characters to generate; nil gives an empty string. |

**Returns**

- **string** — random letters.

**Example**

```lua
local code = exports.kora_core:randomStr(4)
```

**Representative console output**

```text
KQZB
```

#### `exports.kora_core:randomInt(length)`

Random string of digits 0-9. Returns a string, not a number (legacy behaviour). Both realms.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `length` | integer | Digits to generate; nil gives an empty string. |

**Returns**

- **string** — random digits (may start with 0).

**Example**

```lua
local pin = exports.kora_core:randomInt(4)
```

**Representative console output**

```text
0831
```

#### `exports.kora_core:randomAlnum(length)`

Random string from A-Z and 0-9; used for citizenids and stash ids. Not cryptographic. Both realms.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `length` | integer | Characters to generate; nil gives an empty string. |

**Returns**

- **string** — random alphanumeric characters.

**Example**

```lua
local stashId = 'stash_' .. exports.kora_core:randomAlnum(8)
```

**Representative console output**

```text
stash_7QK2M9ZA
```

#### `exports.kora_core:deepClone(t)`

Recursively copies a table (arrays and maps). Metatables are not copied; cycles are not handled and would overflow the stack. Non-tables are returned as is. Both realms.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `t` | table | Value to clone. |

**Returns**

- **table** — independent copy.
- **any** — the input when it is not a table.

**Example**

```lua
local copy = exports.kora_core:deepClone(settings)
```

**Representative console output**

```text
Independent copy of settings.
```

#### `exports.kora_core:pathGet(t, path)`

Reads a nested value by key array. Both realms.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `t` | table | Table to read. |
| `path` | table | Array of keys, for example `{ 'money', 'cash' }`. |

**Returns**

- **any** — the value.
- **nil** — a segment is missing or a non-table was reached.

**Example**

```lua
local cash = exports.kora_core:pathGet(data, { 'money', 'cash' })
```

**Representative console output**

```text
500
```

#### `exports.kora_core:pathSet(t, path, value)`

Writes a nested value by key array, creating missing tables (and replacing non-table intermediates). Returns the previous value. Because tables are copied across an export call, only use this export on a table you own inside the same call context: a cross-resource call mutates the copy. Both realms.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `t` | table | Table to modify. |
| `path` | table | Array of keys. |
| `value` | any | Value to store. |

**Returns**

- **any** — previous value at that path (nil if none).

**Example**

```lua
local previous = exports.kora_core:pathSet(state, { 'ui', 'open' }, true)
```

**Representative console output**

```text
nil
```

#### `Kora.shared.get(name, key)`

Consumer-side mirror (init.lua). Reads one record from the local mirror, a plain table lookup.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Registry name. |
| `key` | string | Record key. |

**Returns**

- **table** — the record.
- **nil** — unknown registry or key.

**Example**

```lua
local item = Kora.shared.get('items', 'water')
```

**Representative console output**

```text
{ name = "water", label = "Water", ... }
```

#### `Kora.shared.all(name)`

Returns the live dense array for a registry from the local mirror. Do not mutate. The array reference stays valid across full resyncs.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Registry name. |

**Returns**

- **table[]** — records (empty table for an unknown registry).

**Example**

```lua
for _, vehicle in ipairs(Kora.shared.all('vehicles')) do print(vehicle.model) end
```

**Representative console output**

```text
adder
zentorno
```

#### `Kora.shared.epoch(name)`

Returns the epoch of the local mirror for a registry.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Registry name. |

**Returns**

- **integer** — epoch (0 when the registry has not been seen).

**Example**

```lua
print(Kora.shared.epoch('items'))
```

**Representative console output**

```text
0
```

#### `Kora.shared.register(name, key, record)`

Forwards to `exports.kora_core:registerShared`. Ownership is the calling resource. On the client this returns the refusing stub's result.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Registry name. |
| `key` | string | Record key. |
| `record` | table | Record. |

**Returns**

- **true** — registered.
- **false, &lt;reason>** — see `registerShared` (client: 'client-side registration is not supported').

**Example**

```lua
local ok, err = Kora.shared.register('locations', 'depot', { key = 'depot', x = 1.0, y = 2.0, z = 3.0 })
```

**Representative console output**

```text
Returns true.
```

#### `Kora.shared.unregister(name, key)`

Forwards to `exports.kora_core:unregisterShared`. Server realm only: that export does not exist on the client, so calling it there raises an error.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Registry name. |
| `key` | string | Record key. |

**Returns**

- **true** — removed.
- **false** — no such record.

**Example**

```lua
Kora.shared.unregister('locations', 'depot')
```

**Representative console output**

```text
Returns true.
```

#### `Kora.shared.onChange(name, handler)`

Local subscription dispatched inside this VM when a delta arrives (pcall-wrapped, errors printed as `[kora_core:shared] onChange handler ... errored`). No owner tracking and no callable check: the handler dies with the resource.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Registry name. |
| `handler` | function | `handler(action, key, record, previous)`. |

**Returns**

- **integer** — id for `offChange`.

**Example**

```lua
local id = Kora.shared.onChange('jobs', function(action, key, record)
    print(action, key)
end)
```

**Representative console output**

```text
add taxi
```

#### `Kora.shared.offChange(name, id)`

Removes a local subscription.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Registry name. |
| `id` | integer | Id from `Kora.shared.onChange`. |

**Returns**

- **nil** — Returns nothing.

**Example**

```lua
Kora.shared.offChange('jobs', id)
```

**Representative console output**

```text
No output.
```

### Common use cases

- Let a resource add items, jobs or vehicles at runtime without editing kora_core data files.
- React to catalogue changes (for example refresh a shop UI) with `onSharedChange` or `Kora.shared.onChange`.
- Use `Kora.shared.get` in hot paths where an export call per read is too slow.

### Limits and related APIs

Registry names are fixed (six). A call with an unknown name returns false, nil or an empty value depending on the function; `unregisterShared` raises an error. Keys must be unique per registry. The epoch does not advance on the server in this version.

### Related guides

- [Replication and the client mirror](./replication.md)
- [Jobs](./jobs.md)
- [Inventory](./inventory.md)
- [Events](./events.md)

## Client

The client mirrors the server registries for zero-cost local reads. The mirror requests a full snapshot on start, then applies deltas. The server owns the data: the client cannot register. The util exports below are the same code as the server realm; see the server realm for full notes.

Namespace: `exports.kora_core` · Source: `modules/registry/shared.lua, modules/registry/client.lua, modules/util/shared.lua`

### How it works

A delta whose epoch differs from the mirror's (non-remove only) triggers a snapshot request instead of being applied; deltas do not update the client's epoch, only snapshots do. Subscriptions are not cleaned up when the subscribing resource stops on the client.

### Functions

Same signatures as the server realm.

#### `exports.kora_core:getShared(name, key)`

Reads one record from the local mirror.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Registry name. |
| `key` | string | Record key. |

**Returns**

- **table** — the record.
- **nil** — unknown registry or key (also before the first snapshot).

**Example**

```lua
local weapon = exports.kora_core:getShared('weapons', 'weapon_pistol')
```

**Representative console output**

```text
{ name = "weapon_pistol", ... }
```

#### `exports.kora_core:allShared(name)`

Returns the mirror's dense array for a registry (a copy across the export boundary).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Registry name. |

**Returns**

- **table[]** — records (empty table for an unknown registry).

**Example**

```lua
local jobs = exports.kora_core:allShared('jobs')
```

**Representative console output**

```text
{ ... }
```

#### `exports.kora_core:countShared(name)`

Returns the record count in the local mirror.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Registry name. |

**Returns**

- **integer** — count (0 when unknown or not yet synced).

**Example**

```lua
print(exports.kora_core:countShared('items'))
```

**Representative console output**

```text
212
```

#### `exports.kora_core:sharedSnapshotAll()`

Snapshot of every client registry.

**Parameters**



**Returns**

- **table** — map of registry name to `{ epoch, keyField, records }`.

**Example**

```lua
local all = exports.kora_core:sharedSnapshotAll()
```

**Representative console output**

```text
{ items = {...}, ... }
```

#### `exports.kora_core:onSharedChange(name, handler)`

Subscribes to deltas applied to the local mirror. Unlike the server version it does not check that `handler` is callable and has no resource-stop cleanup.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Registry name. |
| `handler` | function | `handler(action, key, record, previous)`. |

**Returns**

- **integer** — subscription id.
- **nil** — second return value is the reason: 'no such registry'.

**Example**

```lua
local id = exports.kora_core:onSharedChange('items', function(action, key) refreshShop() end)
```

**Representative console output**

```text
Called with ('update', 'water', ...).
```

#### `exports.kora_core:offSharedChange(name, subId)`

Removes a subscription.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Registry name. |
| `subId` | integer | Id from `onSharedChange`. |

**Returns**

- **nil** — Returns nothing.

**Example**

```lua
exports.kora_core:offSharedChange('items', id)
```

**Representative console output**

```text
No output.
```

#### `exports.kora_core:registerShared(name, key)`

Stub that always refuses: the server owns the registries. Prints a warning to the console.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Registry name. |
| `key` | string | Record key. |

**Returns**

- **false, 'client-side registration is not supported'** — always.

**Example**

```lua
local ok, err = exports.kora_core:registerShared('items', 'x', {})
```

**Representative console output**

```text
Console: [kora_core:registry] client-side registerShared('items','x') refused -- register on the server. Returns false.
```

#### `exports.kora_core:round(value, places?)`

Rounds half up; same code as the server realm.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | number | Number; a non-number returns 0. |
| `places?` | integer | Decimal places; omit for an integer. |

**Returns**

- **number** — rounded value.

**Example**

```lua
local rounded = exports.kora_core:round(3.14159, 1)
```

**Representative console output**

```text
3.1
```

#### `exports.kora_core:trim(value)`

Trims whitespace; non-strings returned unchanged.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | string | String. |

**Returns**

- **string** — trimmed value.

**Example**

```lua
local text = exports.kora_core:trim(input)
```

**Representative console output**

```text
Ada
```

#### `exports.kora_core:splitStr(str, delimiter)`

Splits on a literal delimiter; keeps empty parts; errors on non-string arguments.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `str` | string | Input. |
| `delimiter` | string | Separator. |

**Returns**

- **string[]** — parts.

**Example**

```lua
local parts = exports.kora_core:splitStr('a b c', ' ')
```

**Representative console output**

```text
{ "a", "b", "c" }
```

#### `exports.kora_core:randomStr(length)`

Random A-Z string (client `math.random`).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `length` | integer | Characters. |

**Returns**

- **string** — letters.

**Example**

```lua
local tag = exports.kora_core:randomStr(3)
```

**Representative console output**

```text
QWE
```

#### `exports.kora_core:randomInt(length)`

Random digit string (returns a string).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `length` | integer | Digits. |

**Returns**

- **string** — digits.

**Example**

```lua
local digits = exports.kora_core:randomInt(6)
```

**Representative console output**

```text
482910
```

#### `exports.kora_core:randomAlnum(length)`

Random A-Z0-9 string.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `length` | integer | Characters. |

**Returns**

- **string** — characters.

**Example**

```lua
local id = exports.kora_core:randomAlnum(8)
```

**Representative console output**

```text
7QK2M9ZA
```

#### `exports.kora_core:deepClone(t)`

Recursive table copy without metatables or cycle handling.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `t` | table | Value to clone. |

**Returns**

- **table** — copy (non-tables returned as is).

**Example**

```lua
local copy = exports.kora_core:deepClone(config)
```

**Representative console output**

```text
Independent copy.
```

#### `exports.kora_core:pathGet(t, path)`

Reads a nested value by key array.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `t` | table | Table. |
| `path` | table | Key array. |

**Returns**

- **any** — value, or nil when a segment is missing.

**Example**

```lua
local hunger = exports.kora_core:pathGet(data, { 'metadata', 'hunger' })
```

**Representative console output**

```text
90
```

#### `exports.kora_core:pathSet(t, path, value)`

Writes a nested value by key array and returns the previous value. Across an export call it mutates a copy.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `t` | table | Table. |
| `path` | table | Key array. |
| `value` | any | Value. |

**Returns**

- **any** — previous value (nil if none).

**Example**

```lua
local previous = exports.kora_core:pathSet(state, { 'a', 'b' }, 1)
```

**Representative console output**

```text
nil
```

### Related guides

- [Replication and the client mirror](./replication.md)

## Implementation notes and quick reference

kora_core keeps six server-authoritative registries that every resource and client
can read locally and that resources can change at runtime:

| Registry | Key field | Seeded from |
| --- | --- | --- |
| `items` | `name` | `shared/items.lua` plus stock qb-core items that are not already defined |
| `vehicles` | `model` | `shared/vehicles.lua` |
| `jobs` | `name` | `shared/jobs.lua` plus stock qb-core jobs that are not already defined |
| `gangs` | `name` | `shared/gangs.lua` plus stock qb-core gangs that are not already defined |
| `weapons` | `name` | `shared/weapons.lua` plus stock qb-core weapon items |
| `locations` | `key` | `shared/locations.lua` |

When a kora record and a stock record share a name, the kora record wins and only
missing fields are filled from the stock record. The seed data is described on the
[Items](../items.md) page.

Each registry is a dense array plus a key index. Removal swaps the last record into
the removed position, so array order changes after a removal; always key off the
record's key field.

### Server API

| Export | Returns | Description |
| --- | --- | --- |
| `getShared(name, key)` | record or `nil` | Local lookup (both realms). |
| `allShared(name)` | array | The live array (both realms). Do not mutate; fetch it again when building a list. |
| `countShared(name)` | integer | Record count (both realms). |
| `sharedSnapshotAll()` | table | `[name] = { epoch, keyField, records }` (both realms). |
| `registerShared(name, key, record)` | `true` or `false, err` | Add or replace a record. `record[keyField]` is filled from `key` and must match it. Job/gang grades are normalised. |
| `registerManyShared(name, records)` | integer | Registers records that carry their own key field; returns how many succeeded. |
| `unregisterShared(name, key)` | boolean | Removes a record. |
| `onSharedChange(name, handler)` | id or `nil, err` | `handler(action, key, record, previous)`; `action` is `add`, `update` or `remove`. |
| `offSharedChange(name, id)` | | Remove a subscription. |

Registrations are owner-tracked: the last resource that successfully registered a
record owns it, and when that resource stops its records are unregistered and its
subscriptions removed. Unregistering clears ownership regardless of the caller.

On the client, `registerShared` is refused
(`client-side registration is not supported`); `onSharedChange`/`offSharedChange` subscribe to the client copy.

```lua
local ok, err = exports.kora_core:registerShared('items', 'my_widget', {
    label = 'Widget', weight = 100, type = 'item', unique = false, useable = true,
})
```

### The live mirror in other resources

Add `@kora_core/init.lua` after kora_lib's init file to get a local copy as
`Kora.shared`:

```lua
shared_script '@kora_lib/init.lua'
shared_script '@kora_core/init.lua'
```

```lua
local item = Kora.shared.get('items', 'lockpick')   -- local lookup
local all = Kora.shared.all('jobs')                 -- live array, do not mutate
local epoch = Kora.shared.epoch('items')

-- server only: forwards to exports.kora_core:registerShared / unregisterShared
Kora.shared.register('items', 'lockpick', { label = 'Lockpick', weight = 100 })
Kora.shared.unregister('items', 'lockpick')

local id = Kora.shared.onChange('items', function(action, key, record, previous)
    print(action, key)
end)
Kora.shared.offChange('items', id)
```

`Kora.shared.onChange` subscriptions are local to the resource's VM and die with
it. On a server the mirror seeds itself from `sharedSnapshotAll()`; on a client it
requests a snapshot with `kora_core:registry:requestSnapshot`.

### How changes propagate

Every change is applied on the server, dispatched to server subscribers and
broadcast both as a local server event and to all clients as
`kora_core:registry:delta(name, action, key, record, epoch)`. A mirror that sees an
unexpected epoch for a non-remove delta requests a full snapshot instead
(`kora_core:registry:snapshotAll`). After a full client snapshot the client fires
the local event `kora_core:registry:synced`.

### Legacy views

`QBCore.Shared.Items`, `Vehicles`, `VehicleHashes`, `Jobs`, `Gangs`, `Weapons` and
`Locations` are live views rebuilt from the registries. `Items` contains both the
items and the weapons registries keyed by name, `VehicleHashes` is keyed by model
hash, `Jobs`/`Gangs` use stock zero-based grade keys, and `Weapons` is keyed by
weapon hash (with stock `weapontype`/`damagereason` metadata). Writing to those
tables bypasses the registry; use `registerShared` or the legacy
`QBCore.Functions.AddItem/AddJob/AddGang` family instead. New code should call
`getShared`/`allShared` or `Kora.shared.*` and should not cache those maps.
