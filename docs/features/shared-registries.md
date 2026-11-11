---
title: Shared registries
sidebar_position: 4
---

# Shared registries

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

## Server API

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

## The live mirror in other resources

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

## How changes propagate

Every change is applied on the server, dispatched to server subscribers and
broadcast both as a local server event and to all clients as
`kora_core:registry:delta(name, action, key, record, epoch)`. A mirror that sees an
unexpected epoch for a non-remove delta requests a full snapshot instead
(`kora_core:registry:snapshotAll`). After a full client snapshot the client fires
the local event `kora_core:registry:synced`.

## Legacy views

`QBCore.Shared.Items`, `Vehicles`, `VehicleHashes`, `Jobs`, `Gangs`, `Weapons` and
`Locations` are live views rebuilt from the registries. `Items` contains both the
items and the weapons registries keyed by name, `VehicleHashes` is keyed by model
hash, `Jobs`/`Gangs` use stock zero-based grade keys, and `Weapons` is keyed by
weapon hash (with stock `weapontype`/`damagereason` metadata). Writing to those
tables bypasses the registry; use `registerShared` or the legacy
`QBCore.Functions.AddItem/AddJob/AddGang` family instead. New code should call
`getShared`/`allShared` or `Kora.shared.*` and should not cache those maps.
