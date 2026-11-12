---
title: "Inventory gateway, usable items and consumables"
sidebar_position: 7
---


# Inventory gateway, usable items and consumables

## Server

kora_core owns the `PlayerData.items` persistence and replication funnel, but it is not the inventory authority when kora_inventory is running. `gateway.lua` wraps every inventory export: when the provider resource (`Config.inventory.provider`, default `kora_inventory`) is `started`, the call is forwarded to that resource's export of the same name and its return values come back unchanged. kora_core's own slot engine (the "legacy engine" in `server.lua`) only runs as a fallback.

Namespace: `exports.kora_core` · Source: `modules/inventory/server.lua, gateway.lua, shared.lua; modules/consumables/server.lua`

### Config.inventory.*

Defaults from config.lua.

| Key | Default | Meaning |
| --- | --- | --- |
| maxWeight | 120000 | Legacy engine carry limit in grams. Returned as the second value of `getWeight`. |
| slots | 41 | Legacy engine slots per player (valid slots are 1 to this value). |
| matchInfoOnStack | false | Legacy: when true, a stackable item only merges into a stack whose `info` is equal (one level deep). `addItem` into a forced slot then returns `slot occupied` on mismatch. |
| warnOnUnhandledOpen | true | Legacy `stashOpen` prints a warning when no UI handled `kora_core:inventory:open`. |
| provider | 'kora_inventory' | Resource the gateway forwards to while it is `started`. Read once at load. |
| allowLegacyFallback | true | When the provider is not started: true uses the legacy engine (with a one-time warning), false makes every call return `nil, message`. |
| dropTTL | 1800000 | Milliseconds a legacy ground drop survives uncollected. |
| dropSweepInterval | 300000 | Milliseconds between sweeps that delete expired legacy drops and broadcast `kora_core:client:dropRemoved`. |

### How it works

Everything below that states a failure reason lists which path produces it. Provider path: values and reasons are kora_inventory's and are not documented here. Gateway path: reasons produced by the wrapper itself. Legacy path: reasons produced by the built-in engine.

### How a call is routed

1. **1. Provider started** — If `GetResourceState(Config.inventory.provider) == 'started'` the wrapper calls `exports[provider]:<name>(...)` (colon-call, wrapped in pcall, to avoid the FXServer dot-dispatch argument bug). The provider's return values are passed through. `createUseable` gets a third argument, the invoking resource name, appended.
2. **2. Gateway failure** — If the provider is started but lacks the export: `nil, "kora_inventory is started but is missing required kora_core gateway export '<name>'"`. If the export throws: `nil, "kora_inventory gateway export '<name>' failed: <error>"`. The text says `kora_inventory` regardless of the configured provider name.
3. **3. Provider not started, fallback off** — Any state other than `started` (stopped, starting, missing, uninitialized) with `allowLegacyFallback = false` returns `nil, "kora_inventory is not started (state: <state>); set Config.inventory.allowLegacyFallback=true ..."`.
4. **4. Provider not started, fallback on** — A one-time console warning is printed (`[kora_core:inventory] kora_inventory is not started (state: ...); using the temporary built-in legacy fallback`) and the legacy engine runs. Legacy functions that call sibling functions stay inside the legacy engine through an internal depth guard. Legacy failures are `false, reason`, not `nil, reason`.

### Terms used on this page

| Term | Meaning |
| --- | --- |
| Provider path | Behaviour is whatever kora_inventory implements. Item records, slot rules, weights, events and reasons all come from there. |
| Legacy engine | kora_core's own slot-keyed `PlayerData.items[slot]` model in `modules/inventory/server.lua`, written through `Core.player.setPath`. Used only when the provider is not started and `allowLegacyFallback` is true. |
| Failure shapes | Gateway failures are `nil, message`. Legacy failures are `false, reason`. A caller that must work on both should test `if not ok`, not `ok == false`. |
| Provider is read once | `Config.inventory.provider` is captured when kora_core loads; changing it needs a kora_core restart. |

### Config.inventory

Read from `Config.inventory` in config.lua. `provider` is captured at load. The legacy-only keys (`maxWeight`, `slots`, `matchInfoOnStack`, `warnOnUnhandledOpen`, `dropTTL`, `dropSweepInterval`) affect only the legacy engine and its drop sweep.

### Events

`kora_core:client:itemBox(itemDef, action, amount)` is sent to the player by the legacy `addItem` (`add`) and `removeItem` (`remove`). `kora_core:client:dropCreated(id, coords)` and `kora_core:client:dropRemoved(id)` are broadcast to everyone by the legacy drop functions and the sweep; kora_core's client has no handler for the drop events, a UI resource must listen. `kora_core:inventory:open` is a server-side `TriggerEvent(src, {kind='stash', identifier, slots, maxweight})` from legacy `stashOpen`. `QBCore:Server:UseItem(src, item)` is a server-side `TriggerEvent` from legacy `useItem` when the item has no registered handler. None of these events are emitted by kora_core when the provider handles the call; whether kora_inventory emits its own is its business.

### Stacking and weight (legacy)

Item definitions come from the registry (`items`, then `weapons`): `weight` is grams, `unique` or any weapon entry means one item per slot, everything else stacks. `findStackSlot` picks the lowest matching slot. A unique item added with `amount` greater than 1 occupies that many free slots and ignores a requested slot. Total weight is the sum of `weight * amount` over all slots.

### Usable items

`createUseable` records `{resource, handler}` per item name, tracked by owning resource so a restarted resource leaves no stale handlers. With the provider started the registration is forwarded to kora_inventory instead and the legacy table is not consulted by `useItem`.

### Consumables

When `Config.consumables.enabled` (default true) and `kora_inventory` is `started`, kora_core registers a `usingItem` hook through `exports.kora_inventory:registerHook` (falling back to `RegisterHook`). The resource name is literally `kora_inventory`, not `Config.inventory.provider`. The hook is re-registered on every `onResourceStart` of kora_inventory, and `isRegistered` goes false on its `onResourceStop`. For an item whose shared definition has an `effect` table the hook calls `Kora.status.apply(src, itemName, effect)` (a failure prints `[kora_core:consumables] failed to apply effect for <item>: <err>`), then applies `effect.hungerDelta`, `effect.thirstDelta` and `effect.stressDelta` to metadata `hunger`, `thirst`, `stress` through `incrementMetaData`, clamped to 0..100. The hook always returns `true`: it never denies a use. Real gameplay effects stay in the item's `createUseable` handler.

### Functions

Exports on this page apply to all 21 inventory functions plus `isRegistered`. Each entry splits its returns into the three paths. `src` is always a player server id; none of these functions can be called by a client.

#### `exports.kora_core:getWeight(src)`

Current carried weight and the carry limit.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |

**Returns**

- **Provider path** — whatever kora_inventory returns.
- **Gateway path** — `nil, message` (see routing).
- **Legacy path** — weight, maxWeight: grams carried and `Config.inventory.maxWeight`. For an unknown player: `0, Config.inventory.maxWeight`.

**Example**

```lua
local weight, maxWeight = exports.kora_core:getWeight(src)
print(('%d / %d g'):format(weight, maxWeight))
```

**Representative console output**

```text
4200 / 120000 g
```

#### `exports.kora_core:canCarry(src, name, amount)`

Check whether an item amount fits without adding it.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `name` | string | Item name. |
| `amount?` | integer | Default 1. |

**Returns**

- **Provider path** — kora_inventory's results.
- **Gateway path** — `nil, message`.
- **Legacy path** — true when it fits.
- **Legacy path** — false, 'no such player' — no logged-in player.
- **Legacy path** — false, 'unknown item' — not in the items or weapons registry.
- **Legacy path** — false, 'over weight' — would exceed `maxWeight`.
- **Legacy path** — false, 'no free slot' — no stack to merge into and no free slot (unique items need `amount` free slots).

**Example**

```lua
local ok, reason = exports.kora_core:canCarry(src, 'water', 3)
if not ok then
    TriggerClientEvent('QBCore:Notify', src, 'Cannot carry: ' .. tostring(reason), 'error')
end
```

**Representative console output**

```text
-- false, 'over weight'
```

#### `exports.kora_core:addItem(src, name, amount, slot, info, reason)`

Add an item to a player. Legacy path writes through `Core.player.setPath` (dirty tracking and delta replication) and sends `kora_core:client:itemBox`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `name` | string | Item name. |
| `amount?` | integer | Default 1; floored; must be positive. |
| `slot?` | integer | Force a slot (1 to `Config.inventory.slots`); otherwise stack into the lowest matching stack or take the first free slot. |
| `info?` | table | Item metadata for a new record. A merge into an existing stack keeps the existing `info`. |
| `reason?` | string | Audit text. Passed to the provider; ignored by the legacy engine. |

**Returns**

- **Provider path** — kora_inventory's results.
- **Gateway path** — `nil, message`.
- **Legacy path** — true on success.
- **Legacy path** — false, 'no such player'; 'player data is busy' (logging out or an inventory column operation is running); 'amount must be positive'; 'unknown item'; 'invalid slot'; 'slot occupied' (forced slot holds a different item, a unique item, or a mismatched `info` when `matchInfoOnStack`).
- **Legacy path** — false plus the `canCarry` reasons: 'over weight', 'no free slot'.

**Example**

```lua
local ok, reason = exports.kora_core:addItem(src, 'bandage', 2, nil, { quality = 100 }, 'shop purchase')
if not ok then
    print(('addItem failed: %s'):format(tostring(reason)))
end
```

**Representative console output**

```text
-- ok = true; client shows "Received 2x Bandage"
```

#### `exports.kora_core:removeItem(src, name, amount, slot, reason)`

Remove an item. Legacy path sends `kora_core:client:itemBox` with `remove`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `name` | string | Item name. |
| `amount?` | integer | Default 1; floored; must be positive. |
| `slot?` | integer | Remove from this slot when it holds `name`; if the slot is empty or holds another item the slot is ignored and stacks are drained lowest slot first. |
| `reason?` | string | Audit text. Provider only. |

**Returns**

- **Provider path** — kora_inventory's results.
- **Gateway path** — `nil, message`.
- **Legacy path** — true on success.
- **Legacy path** — false, 'no such player'; 'player data is busy'; 'amount must be positive'; 'not enough of item' (total across all slots is less than `amount`; checked first so nothing is partially removed).
- **Legacy path** — note: with a matching `slot` the removal is capped at what that slot holds and still returns true even if `amount` was larger; the total is not checked in that case.

**Example**

```lua
local ok, reason = exports.kora_core:removeItem(src, 'lockpick', 1)
if not ok then return end
```

**Representative console output**

```text
-- ok = true
```

#### `exports.kora_core:getItemByName(src, name)`

First item record with that name.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `name` | string | Item name. |

**Returns**

- **Provider path** — kora_inventory's result.
- **Legacy path** — the record in the lowest slot (`{slot, name, amount, info, type, unique, useable, image, imageUrl, label, weight, shouldClose, description, created}`), or nil when there is none or the player is unknown.

**Example**

```lua
local phone = exports.kora_core:getItemByName(src, 'phone')
if phone then print(phone.slot, phone.info.number) end
```

**Representative console output**

```text
3   555-0142
```

#### `exports.kora_core:getItemsByName(src, name)`

Every record with that name.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `name` | string | Item name. |

**Returns**

- **Provider path** — kora_inventory's result.
- **Legacy path** — array of records (in `pairs` order, not sorted by slot); empty table when none or the player is unknown. Never nil.

**Example**

```lua
for _, item in ipairs(exports.kora_core:getItemsByName(src, 'sandwich')) do
    print(item.slot, item.amount)
end
```

**Representative console output**

```text
2   3
```

#### `exports.kora_core:getItemBySlot(src, slot)`

Record in one slot.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `slot` | integer | Slot number. |

**Returns**

- **Provider path** — kora_inventory's result.
- **Legacy path** — the record, or nil for an empty slot or unknown player.

**Example**

```lua
local item = exports.kora_core:getItemBySlot(src, 1)
print(item and item.name or 'empty')
```

**Representative console output**

```text
phone
```

#### `exports.kora_core:getItemCount(src, name)`

Total amount of an item across all slots.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `name` | string | Item name. |

**Returns**

- **Provider path** — kora_inventory's result.
- **Legacy path** — integer sum, 0 when none or the player is unknown.

**Example**

```lua
if exports.kora_core:getItemCount(src, 'cash_roll') < 10 then return end
```

**Representative console output**

```text
12
```

#### `exports.kora_core:hasItem(src, nameOrList, amount)`

Check that the player holds an item, or every item of a list.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `nameOrList` | string\|string[]\|table&lt;string,integer> | One item name; an array of names (each needs `amount`, default 1); or a map `{name = needed}` (each needs `amount` if given, else its own value, else 1). |
| `amount?` | integer | Required count; default 1. Overrides per-item values of a map. |

**Returns**

- **Provider path** — kora_inventory's result.
- **Legacy path** — true when every requirement is met, false otherwise. An empty table returns true. There is no reason string.

**Example**

```lua
local hasKit = exports.kora_core:hasItem(src, { 'repairkit', 'screwdriverset' })
local hasCash = exports.kora_core:hasItem(src, { cash_roll = 5 })
```

**Representative console output**

```text
true
```

#### `exports.kora_core:getFreeSlot(src)`

Lowest free slot.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |

**Returns**

- **Provider path** — kora_inventory's result.
- **Legacy path** — slot number from 1 to `Config.inventory.slots`, or nil when full or the player is unknown.

**Example**

```lua
local slot = exports.kora_core:getFreeSlot(src)
if not slot then return end
```

**Representative console output**

```text
7
```

#### `exports.kora_core:moveItem(src, fromSlot, toSlot, amount)`

Move or split a stack between slots; merges into a destination holding the same item name.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `fromSlot` | integer | Source slot. |
| `toSlot` | integer | Destination slot. |
| `amount?` | integer | Default and maximum: the whole source stack; floored. |

**Returns**

- **Provider path** — kora_inventory's results.
- **Gateway path** — `nil, message`.
- **Legacy path** — true on success, including when `fromSlot == toSlot` (no-op).
- **Legacy path** — false, 'no such player'; 'player data is busy'; 'invalid slot'; 'empty source slot'; 'amount must be finite'; 'amount must be positive'; 'destination occupied' (different item in the destination).
- **Legacy path** — no weight, unique or `matchInfoOnStack` check is made when merging.

**Example**

```lua
local ok, reason = exports.kora_core:moveItem(src, 1, 5, 2)
```

**Representative console output**

```text
-- ok = true: 2 items moved from slot 1 to slot 5
```

#### `exports.kora_core:clearInventory(src, keep)`

Delete every item except a keep list.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `keep?` | string[] | Item names to keep. |

**Returns**

- **Provider path** — kora_inventory's result.
- **Gateway path** — `nil, message`.
- **Legacy path** — true.
- **Legacy path** — false (no reason) for an unknown player; false, 'player data is busy' while logging out or locked.

**Example**

```lua
exports.kora_core:clearInventory(src, { 'phone', 'id_card' })
```

**Representative console output**

```text
-- true
```

#### `exports.kora_core:setItems(src, newItems)`

Replace the whole `PlayerData.items` table in one write. No validation of the table shape, item names or weights, and the busy check of other mutators is not applied.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `newItems?` | table | Slot-keyed items table; nil becomes `{}`. |

**Returns**

- **Provider path** — kora_inventory's results.
- **Gateway path** — `nil, message`.
- **Legacy path** — false for an unknown player; otherwise the result of `Core.player.setPath(src, {'items'}, newItems)`: true, or false, reason (for example `player logout is in progress`, `player data is busy`).

**Example**

```lua
local ok, reason = exports.kora_core:setItems(src, {})
```

**Representative console output**

```text
-- true
```

#### `exports.kora_core:createUseable(name, handler)`

Register a use handler for an item. The owner is the invoking resource; re-registering a name replaces it and transfers ownership; the entry is removed when the owner resource stops.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Item name. |
| `handler` | fun(src:integer, item:table) | Called when the item is used. Return `false` to report a failed use. |

**Returns**

- **Provider path** — kora_inventory's result; the invoking resource name is appended as a third argument.
- **Gateway path** — `nil, message`.
- **Legacy path** — nothing returned.

**Example**

```lua
exports.kora_core:createUseable('bandage', function(src, item)
    exports.kora_core:removeItem(src, 'bandage', 1)
    TriggerClientEvent('myambulance:client:heal', src)
end)
```

**Representative console output**

```text
-- no output
```

#### `exports.kora_core:getUseable(name)`

Look up a registered handler.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Item name. |

**Returns**

- **Provider path** — kora_inventory's result.
- **Legacy path** — `{func = handler, resource = ownerResource}`, or nil if none is registered (not whether the item exists).

**Example**

```lua
local useable = exports.kora_core:getUseable('bandage')
if useable then print(useable.resource) end
```

**Representative console output**

```text
myambulance
```

#### `exports.kora_core:useItem(src, slotOrName)`

Use an item by slot or name.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `slotOrName` | integer\|string | A number selects a slot; anything else is treated as an item name (lowest slot). |

**Returns**

- **Provider path** — kora_inventory's result.
- **Gateway path** — `nil, message`.
- **Legacy path** — true when a handler ran and did not return `false`.
- **Legacy path** — false: unknown or logging-out player; item not found; no handler registered (also triggers `QBCore:Server:UseItem(src, item)`); the handler errored (prints `[kora_core:inventory] useable '<name>' errored: <error>`); or the handler returned `false`.

**Example**

```lua
RegisterCommand('eat', function(src)
    exports.kora_core:useItem(src, 'sandwich')
end, false)
```

**Representative console output**

```text
-- true
```

#### `exports.kora_core:stashGet(identifier)`

Read a stash's items from the `inventories` table. Yields (SQL). Works in the legacy engine only when the provider is not started.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `identifier` | string | Stash identifier. |

**Returns**

- **Provider path** — kora_inventory's result.
- **Legacy path** — decoded items table; `{}` when no row exists, the SQL call fails or the JSON does not decode.

**Example**

```lua
local items = exports.kora_core:stashGet('police_evidence_1')
```

**Representative console output**

```text
{ [1] = { name = 'weed_baggy', amount = 2 } }
```

#### `exports.kora_core:stashSet(identifier, stashItems)`

Write a stash's items. Enqueued to the SQL coalescing queue (`inventories`, kind `stash`, assign mode), so it does not block and is flushed later.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `identifier` | string | Stash identifier. |
| `stashItems?` | table | Items table; nil becomes `{}`. Not validated. |

**Returns**

- **Provider path** — kora_inventory's result.
- **Legacy path** — always true.

**Example**

```lua
exports.kora_core:stashSet('police_evidence_1', items)
```

**Representative console output**

```text
-- true
```

#### `exports.kora_core:stashOpen(src, identifier, opts)`

Open a stash for a player. The legacy engine ships no UI: it emits a server event for a UI resource to handle.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `identifier` | string | Stash identifier. |
| `opts?` | table | `{slots?, maxweight?}`; defaults 50 slots and 100000 grams. |

**Returns**

- **Provider path** — kora_inventory's results.
- **Gateway path** — `nil, message`.
- **Legacy path** — always true. It triggers `kora_core:inventory:open(src, {kind = 'stash', identifier, slots, maxweight})` on the server. Unless `Config.inventory.warnOnUnhandledOpen` is false it also prints a `no UI resource handled it` warning whenever the global `__qbcoreInventoryUIHandled` is unset in kora_core's VM; nothing in kora_core sets it.

**Example**

```lua
AddEventHandler('kora_core:inventory:open', function(src, data)
    TriggerClientEvent('myui:openStash', src, data)
end)
exports.kora_core:stashOpen(src, 'police_evidence_1', { slots = 30, maxweight = 50000 })
```

**Representative console output**

```text
-- true
```

#### `exports.kora_core:dropCreate(coords, dropItems)`

Create a ground drop and broadcast `kora_core:client:dropCreated(id, coords)` to all players. Drops live in server memory only and are lost on restart.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `coords` | table | World position, broadcast as given. Not validated. |
| `dropItems?` | table | Slot-keyed `{name, amount, info}` records; nil becomes `{}`. |

**Returns**

- **Provider path** — kora_inventory's result.
- **Legacy path** — dropId: integer from a counter starting at 1.

**Example**

```lua
local dropId = exports.kora_core:dropCreate(coords, { [1] = { name = 'water', amount = 2 } })
```

**Representative console output**

```text
1
```

#### `exports.kora_core:dropTake(src, dropId, slot, amount)`

Move items from a drop into a player's inventory via `addItem`. No proximity check: the caller must verify the player is near the drop. Removes the drop and broadcasts `kora_core:client:dropRemoved(id)` once empty.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `dropId` | integer | Id returned by `dropCreate`. |
| `slot` | integer | Slot inside the drop. |
| `amount?` | integer | Default and maximum: the stack amount. |

**Returns**

- **Provider path** — kora_inventory's results.
- **Gateway path** — `nil, message`.
- **Legacy path** — true on success.
- **Legacy path** — false, 'no such drop'; 'empty slot'; or any `addItem` reason ('no such player', 'player data is busy', 'amount must be positive', 'over weight', 'no free slot', ...). The drop is unchanged on failure.

**Example**

```lua
local ok, reason = exports.kora_core:dropTake(src, dropId, 1, 1)
```

**Representative console output**

```text
-- true
```

#### `exports.kora_core:isRegistered()`

Whether the consumables `usingItem` hook is currently registered on kora_inventory. This is the consumables module, not the provider gateway, so it never forwards.

**Parameters**



**Returns**

- **true** — the hook was registered and kora_inventory has not stopped since.
- **false** — `Config.consumables.enabled` is false, kora_inventory is not started, registration failed, or kora_inventory stopped.

**Example**

```lua
if not exports.kora_core:isRegistered() then
    print('consumable effects are not active')
end
```

**Representative console output**

```text
consumable effects are not active
```

### Common use cases

- Give a reward from a job resource and read the single failure shape with `if not ok`.
- Register usable items from your own resource without knowing which inventory is active.
- Add an `effect = { hungerDelta = 25 }` table to an item definition and let the consumables hook apply it with no game logic.

### Limits and related APIs

Failure reasons from the provider path are not listed here. The gateway forwards every export and does not change argument semantics, so the same call can return different reason strings depending on which path is active. Legacy drops and stash writes are not shared with kora_inventory. The weight, stacking and drop sweep configuration only applies to the legacy engine.

### Related guides

- [Player: setPath](./player.md)
- [Metadata: incrementMetaData](./metadata.md)
- [Persistence](./persistence.md)
- [Config.inventory and Config.consumables](./configuration.md)
- [Registry: items and weapons](./registry.md)

## Client

Minimal client glue: an item-pickup notification and a read of the local inventory from the replication mirror. The server owns the model; no NUI is shipped.

Namespace: `exports.kora_core` · Source: `modules/inventory/client.lua`

### Terms used on this page

| Term | Meaning |
| --- | --- |
| kora_core:client:itemBox | Registered net event `(itemDef, action, amount)`. Shows a Kora notification: `Received <amount>x <label>` (type success) or `Removed ...` when `action == 'remove'` (type error). Label falls back to `itemDef.name`, then `item`; amount defaults to 1. |

### Functions

Functions exported by this realm.

#### `exports.kora_core:getInventory()`

The local player's inventory from the replicated mirror.

**Parameters**



**Returns**

- **items** — slot-keyed table from `Core.replication.getData({'items'})`, or `{}` when nothing is mirrored yet. Read-only view; edits do not reach the server.

**Example**

```lua
local items = exports.kora_core:getInventory()
for slot, item in pairs(items) do
    print(slot, item.name, item.amount)
end
```

**Representative console output**

```text
1   phone   1
```

### Limits and related APIs

Mirror data is as current as the last replicated delta. Do not make decisions that must be secure from it; ask the server.

### Related guides

- [Replication](./replication.md)

## Implementation notes and quick reference

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

### Item records in PlayerData

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

### Server API

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

### Client API

| Export | Description |
| --- | --- |
| `getInventory()` | The local `items` table from the mirror, or an empty table. |

The client shows a notification (`Received 2x Water` / `Removed ...`) on
`kora_core:client:itemBox`.

### Consumable effects

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
