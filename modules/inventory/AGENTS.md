# inventory module guide

## Purpose
The item model, in the legacy slot-keyed shape, driven entirely through the player funnel so per-slot changes get dirty-tracking and delta replication for free. Weight/stacking math lives in the shared realm; the server owns mutation, stashes, drops, and useables; the client surfaces the pickup box and reads the mirror. **Shipping a NUI is an explicit non-goal.**

## Public API
Server (mutation/queries): `getWeight`, `canCarry`, `addItem`, `removeItem`, `getItemByName`, `getItemsByName`, `getItemBySlot`, `getItemCount`, `hasItem`, `getFreeSlot`, `moveItem`, `clearInventory`, `setItems`.
Server (useables): `createUseable`, `useItem`.
Server (stashes): `stashGet`, `stashSet`, `stashOpen`.
Server (drops): `dropCreate`, `dropTake`.
Client: `getInventory` (reads `{ 'items' }` from the mirror).
Shared math (internal, `CoreInternal.inventory`): `totalWeight`, `isUnique`, `findStackSlot`, `infoEquals`, `firstFreeSlot`.

## Design — storage shape
`PlayerData.items` is a **slot-keyed map**: `items[slot] = { slot, name, amount, info, type, unique, useable, image, label, weight, shouldClose, description, created }`. This is the shape legacy inventory resources read, so ports work. Every write is `Core.player.setPath(src, {'items', slot}, record)` — one slot = one dirty `inventory` column + one delta op; clearing a slot is `setPath(..., nil)` (a delete op).

## Implementation notes
- **Stacking rules (shared).** `isUnique(name)` is true for weapons and items flagged `unique` — those never stack. `findStackSlot` returns the lowest slot holding a stackable match; when `Config.inventory.matchInfoOnStack` is set it also requires `infoEquals(item.info, info)` (a one-level table compare — good enough for stack decisions, stricter than legacy which ignores `info`).
- **Weight (shared).** `totalWeight` sums `def.weight * amount` per slot, pulling weights from the `items` registry then the `weapons` registry, falling back to the record's own `weight`. `canCarry` enforces `Config.inventory.maxWeight` *and* a slot check (a free slot is required unless the add fully stacks).
- **Never a partial removal.** `removeItem` computes the total across matching slots first and refuses with `'not enough of item'` if short, then drains lowest-slot-first. Per-slot removal goes through `Core.inventory._removeFromSlot` — note the leading underscore: it is **not exported** (`build/finalise.lua` skips `_`-prefixed functions), it's an internal helper.
- **Unique items take multiple slots.** `addItem(name, amount>1)` for a unique item loops, placing one per free slot, failing partway with `'no free slot'` if it runs out (already-placed slots stay).
- **Useables are owner-tagged** (`{resource=..., handler=...}`) and `pcall`-guarded. `useItem` accepts a slot number or an item name; with no registered handler it falls back to the legacy `QBCore:Server:UseItem` event. (There is no owner-stop sweep of useables today — unlike commands/registry — so a resource that registers a useable and restarts leaves the old handler until it re-registers.)
- **Stashes persist to the `inventories` table.** `stashGet` is a live read (yields); `stashSet` is a fire-and-forget `QB.sql.enqueue` upsert (`kind='stash'`). Stash *contents* are JSON in the `items` column.
- **`stashOpen` ships no NUI — deliberately.** It emits `qbcore:inventory:open` with `{kind, identifier, slots, maxweight}` for a UI resource to handle, and warns (gated by `Config.inventory.warnOnUnhandledOpen`) when nothing did. This is a stated non-goal, surfaced honestly rather than faked with a stub UI. The unhandled-open detection uses a `_G.__qbcoreInventoryUIHandled` flag a UI resource sets.
- **Ground drops are in-memory only.** `drops[dropId] = {coords, items}`, broadcast to all clients on create/remove. Not persisted across restart, by design — a crash drops the drops.
- **Client is minimal.** `qbcore:client:itemBox` shows a `QB.notify.send` by default (a UI resource can also listen); `getInventory` reads the mirror. No client-side authority.

## Best practices
- Mutate inventory only through these functions so each change is one funnel write with correct dirty/replication behaviour.
- Bring an inventory UI: handle `qbcore:inventory:open` (and set the handled flag), or set `Config.inventory.warnOnUnhandledOpen=false` if you intentionally run headless.
- Put per-instance state (serials, durability) in `info`; enable `matchInfoOnStack` if such items must not merge.
