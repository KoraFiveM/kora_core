---
title: Inventory gateway
sidebar_position: 5
---

# Inventory gateway

kora_core does not ship an inventory UI. The inventory exports below are a gateway:

- When the resource named in `Config.inventory.provider` (default
  [kora_inventory](https://github.com/KoraFiveM/kora_inventory)) is started, every
  call is forwarded to the export of the same name on that resource. `createUseable`
  additionally passes the calling resource name. If the provider is started but
  lacks the export, the call returns `nil` and an error message.
- When the provider is not started and `Config.inventory.allowLegacyFallback` is
  `true`, a built-in slot-based engine that stores items in `PlayerData.items` is
  used, with a one-time warning. With `false`, calls return `nil` and an error.

The behaviour described below for each export is the built-in fallback; with
kora_inventory running, kora_inventory's own rules apply. kora_core does not
`provide 'qb-inventory'`.

## Item records in PlayerData

```lua
PlayerData.items[slot] = {
    slot = 3, name = 'water_bottle', amount = 2, info = {},
    type = 'item', unique = false, useable = true,
    image = 'water_bottle.png', imageUrl = 'https://...', label = 'Water',
    weight = 500, shouldClose = true, description = 'Refreshing.', created = 1700000000,
}
```

Items are keyed by slot. `image` is the legacy file name; `imageUrl` is copied from
the registry definition when present.

## Server API

| Export | Returns | Description |
| --- | --- | --- |
| `addItem(src, name, amount, slot, info, reason)` | `true` or `false, err` | Adds an item from the `items` or `weapons` registry. Stackable items merge into the lowest matching slot; unique items and weapons take one slot each. Sends `kora_core:client:itemBox`. |
| `removeItem(src, name, amount, slot, reason)` | `true` or `false, err` | Removes from `slot` or from the lowest matching slots; checks the total first, never removes partially. |
| `getItemByName(src, name)` | item or `nil` | Lowest-slot item with that name. |
| `getItemsByName(src, name)` | array | Every item with that name. |
| `getItemBySlot(src, slot)` | item or `nil` | |
| `getItemCount(src, name)` | integer | Total amount across slots. |
| `hasItem(src, nameOrList, amount)` | boolean | At least `amount` (default 1) of one item, of every item in an array, or of every `[name] = count` pair in a map. |
| `getFreeSlot(src)` | integer or `nil` | Lowest free slot. |
| `canCarry(src, name, amount)` | `true` or `false, err` | Weight and slot check. |
| `getWeight(src)` | weight, maxWeight | Current weight and `Config.inventory.maxWeight`. |
| `moveItem(src, fromSlot, toSlot, amount)` | `true` or `false, err` | Moves or splits a stack; refuses a different item in the destination. |
| `clearInventory(src, keep)` | `true` or `false, err` | Removes everything except names listed in `keep`. |
| `setItems(src, items)` | boolean | Replaces the whole table in one write (legacy `SetInventory`). |
| `createUseable(name, handler)` | | Registers `handler(src, item)`; owner-tracked, removed when the registering resource stops. |
| `getUseable(name)` | table or `nil` | `func` and `resource` of the registered handler. |
| `useItem(src, slotOrName)` | boolean | Runs the useable handler (`pcall`-protected); returns `false` if the handler returned `false`. Without a handler fires `QBCore:Server:UseItem(src, item)` and returns `false`. |
| `stashGet(identifier)` | table | Yields. Items stored in `inventories.items`. |
| `stashSet(identifier, items)` | `true` | Queues an upsert of `inventories` (kind `stash`). |
| `stashOpen(src, identifier, opts)` | `true` | Fires the server event `kora_core:inventory:open(src, data)` with `kind`, `identifier`, `slots` (default 50) and `maxweight` (default 100000) for a UI resource. |
| `dropCreate(coords, items)` | integer | Creates an in-memory ground drop and sends `kora_core:client:dropCreated(id, coords)`. |
| `dropTake(src, dropId, slot, amount)` | `true` or `false, err` | Moves items from a drop into the player; sends `kora_core:client:dropRemoved(id)` when empty. |

Fallback error strings include `no such player`, `player data is busy`,
`amount must be positive`, `unknown item`, `invalid slot`, `slot occupied`,
`over weight`, `no free slot`, `not enough of item`, `empty source slot`,
`destination occupied`, `no such drop` and `empty slot`.

Fallback rules:

- Weight is the sum of registry weight (or the item's own `weight`) times amount;
  the limit is `Config.inventory.maxWeight` and the slot count `Config.inventory.slots`.
- With `Config.inventory.matchInfoOnStack`, items only stack when their `info`
  tables are equal.
- Ground drops expire after `Config.inventory.dropTTL` and are not persisted.
- `stashOpen` prints a warning when `Config.inventory.warnOnUnhandledOpen` is on
  and no UI handled the event.

```lua
exports.kora_core:createUseable('bandage', function(src, item)
    if exports.kora_core:removeItem(src, 'bandage', 1, item.slot) then
        -- heal the player
    end
end)
```

Every change to `PlayerData.items` fires the server event
`kora_core:server:inventoryChanged(src, path, value)`.

## Client API

| Export | Description |
| --- | --- |
| `getInventory()` | The local `items` table from the mirror, or an empty table. |

The client shows a notification (`Received 2x Water` / `Removed ...`) on
`kora_core:client:itemBox`.

## Consumable effects

When `Config.consumables.enabled` is on and kora_inventory is started, kora_core
registers a `usingItem` hook on kora_inventory (retried when kora_inventory
starts). For an item whose registry record has an `effect` table it calls
`Kora.status.apply(src, itemName, effect)` and applies these optional deltas,
clamped to 0..100:

```lua
effect = { hungerDelta = 10, thirstDelta = -5, stressDelta = -2 }
```

The hook never blocks the use. Real gameplay logic stays in the item's useable
handler. The server export `isRegistered()` reports whether the hook is active.
