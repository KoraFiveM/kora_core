# Inventory module

## Overview
The player item shape remains the **legacy slot-keyed** `PlayerData.items[slot] = { slot, name, amount, info, type, unique, useable, image, label, weight, … }`, persisted by qbcore through the player funnel. qbinventory is the headless inventory authority; qbcore's `Core.inventory` / `exports.qbcore:<fn>` surface dynamically forwards operations to it when started. This resource deliberately **does not provide `qb-inventory`**: qbinventory owns that compatibility identity.

For staged upgrades only, `Config.inventory.allowLegacyFallback=true` keeps the original funnel-backed implementation available while qbinventory is absent and logs a one-time warning. Set it to `false` once qbinventory is required to return a clear error instead. A started qbinventory missing any required gateway export is always an error; qbcore never mixes providers per operation.

## API

### `Core.inventory.getWeight(src)` — server
Returns the player's current total weight and the configured max weight.

#### Parameters
- `src: integer`

#### Returns
- `number` — Current weight (grams).
- `number` — `Config.inventory.maxWeight`.

### `Core.inventory.canCarry(src, name, amount)` — server
Checks whether the player can receive `amount` of `name` — both a weight check and a slot check (needs a free slot if it can't fully stack).

#### Parameters
- `src: integer`
- `name: string`
- `amount: integer | nil` — Default `1`.

#### Returns
- `boolean`
- `string | nil` — Failure reason (`'no such player'`, `'unknown item'`, `'over weight'`, `'no free slot'`).

### `Core.inventory.addItem(src, name, amount, slot, info, reason)` — server
Adds an item, stacking into an existing matching slot when the item is stackable, otherwise placing into `slot` (if given) or the first free slot. A unique item added with `amount > 1` occupies multiple slots, one each. Fires the `qbcore:client:itemBox` pickup event.

#### Parameters
- `src: integer`
- `name: string` — Must be a registered item or weapon.
- `amount: integer | nil` — Default `1`, must be `> 0`.
- `slot: integer | nil` — Force a target slot; otherwise stack-or-first-free.
- `info: table | nil` — Per-instance data (serial numbers, durability, …).
- `reason: string | nil`

#### Returns
- `boolean`
- `string | nil` — Failure reason (`'no such player'`, `'amount must be positive'`, `'unknown item'`, a `canCarry` reason, `'no free slot'`).

#### Example
```lua
local ok, err = exports.qbcore:addItem(src, 'water', 2)
```

### `Core.inventory.removeItem(src, name, amount, slot, reason)` — server
Removes `amount` of `name`. From a specific `slot` if given and matching; otherwise drains matching slots lowest-first. Verifies the player has enough **before** removing anything (never a partial removal). Fires the pickup event with a `remove` action.

#### Parameters
- `src: integer`
- `name: string`
- `amount: integer | nil` — Default `1`, must be `> 0`.
- `slot: integer | nil`
- `reason: string | nil`

#### Returns
- `boolean`
- `string | nil` — Failure reason (`'no such player'`, `'amount must be positive'`, `'not enough of item'`).

### `Core.inventory.getItemByName(src, name)` — server
Returns the lowest-slot item record matching `name`, or `nil`.

#### Returns
- `table | nil`

### `Core.inventory.getItemsByName(src, name)` — server
Returns every item record matching `name`.

#### Returns
- `table[]`

### `Core.inventory.getItemBySlot(src, slot)` — server
Returns the item record in a slot, or `nil`.

#### Returns
- `table | nil`

### `Core.inventory.getItemCount(src, name)` — server
Returns the total amount of `name` across all slots.

#### Returns
- `integer`

### `Core.inventory.hasItem(src, nameOrList, amount)` — server
Returns whether the player has at least `amount` (default `1`) of an item — or of **every** item in a list.

#### Parameters
- `src: integer`
- `nameOrList: string | string[]`
- `amount: integer | nil`

#### Returns
- `boolean`

#### Example
```lua
if exports.qbcore:hasItem(src, { 'lockpick', 'screwdriver' }) then
    -- has both
end
```

### `Core.inventory.getFreeSlot(src)` — server
Returns the lowest free slot index, or `nil` if full.

#### Returns
- `integer | nil`

### `Core.inventory.moveItem(src, fromSlot, toSlot, amount)` — server
Moves or splits `amount` from one slot to another, stacking into the destination if it holds the same item and refusing if it holds a different one.

#### Returns
- `boolean`
- `string | nil` — Failure reason (`'no such player'`, `'empty source slot'`, `'destination occupied'`).

### `Core.inventory.clearInventory(src, keep)` — server
Clears the inventory, optionally keeping items whose names are in `keep`.

#### Parameters
- `src: integer`
- `keep: string[] | nil`

#### Returns
- `boolean`

### `Core.inventory.setItems(src, newItems)` — server
Replaces the whole items table in one funnel write (compat `SetInventory`).

#### Returns
- `boolean`

### `Core.inventory.createUseable(name, handler)` — server
Registers a use handler for an item. `handler(src, item)` runs when the item is used. Owner-tagged with the calling resource.

#### Parameters
- `name: string`
- `handler: fun(src: integer, item: table)`

#### Example
```lua
exports.qbcore:createUseable('bandage', function(src, item)
    exports.qbcore:incrementMetaData(src, 'hunger', 0)   -- heal, etc.
    exports.qbcore:removeItem(src, 'bandage', 1)
end)
```

### `Core.inventory.useItem(src, slotOrName)` — server
Uses an item by slot (number) or name (string). Runs the registered useable handler (`pcall`-guarded); if none is registered, fires the legacy `QBCore:Server:UseItem` hook.

#### Parameters
- `src: integer`
- `slotOrName: integer | string`

#### Returns
- `boolean` — `true` if a useable handler ran.

### `Core.inventory.stashGet(identifier)` — server
Reads a stash's items from the `inventories` table. **Yields** on the DB read.

#### Parameters
- `identifier: string`

#### Returns
- `table` — The stash items (empty table if none).

### `Core.inventory.stashSet(identifier, stashItems)` — server
Writes a stash's items (fire-and-forget upsert through the SQL queue).

#### Parameters
- `identifier: string`
- `stashItems: table`

#### Returns
- `boolean`

### `Core.inventory.stashOpen(src, identifier, opts)` — server
Emits `qbcore:inventory:open` for a UI resource to handle. Ships **no NUI**; warns (once, if `Config.inventory.warnOnUnhandledOpen`) when nothing handled it.

#### Parameters
- `src: integer`
- `identifier: string`
- `opts: table | nil` — `{ slots, maxweight }`.

#### Returns
- `boolean`

### `Core.inventory.dropCreate(coords, dropItems)` — server
Creates an in-memory ground drop and broadcasts it to clients. Returns the drop id. Drops are **not** persisted across a restart, by design.

#### Parameters
- `coords: table`
- `dropItems: table`

#### Returns
- `integer` — The drop id.

### `Core.inventory.dropTake(src, dropId, slot, amount)` — server
Takes items from a ground drop into a player's inventory, removing the drop when it empties.

#### Returns
- `boolean`
- `string | nil` — Failure reason (`'no such drop'`, `'empty slot'`, or an `addItem` reason).

### `Core.inventory.getInventory()` — client
Returns the local inventory table from the mirror (`{ 'items' }`), or an empty table.

#### Returns
- `table`

## Notes
- **Slot-keyed legacy shape.** Items live at `items[slot]`, not in a flat array — the shape legacy inventory resources expect.
- **Stacking rules.** Weapons and items flagged `unique` never stack. Stackables merge into the lowest matching slot; when `Config.inventory.matchInfoOnStack` is on, they only stack if their `info` tables match (stricter than legacy).
- **Weight.** Total weight is computed from the `items`/`weapons` registry weights (falling back to a record's own `weight`); `canCarry`/`addItem` enforce `Config.inventory.maxWeight`.
- **Every mutation is a funnel write per slot**, so a slot change is one dirty column (`inventory`) and one delta op — deleting a slot is `setPath(..., nil)`.
- **Headless boundary.** qbcore has no inventory NUI and no `qb-inventory` provider. qbinventory may run headlessly or alongside its optional UI companion; its server exports remain the authority.
- **Drops are ephemeral.** Ground drops live in memory only and vanish on restart, by design.
