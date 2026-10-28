# inventory module guide

## Purpose
The player item model remains in the legacy slot-keyed shape and persists through kora_core's player funnel. kora_inventory owns inventory operations; `gateway.lua` forwards the legacy `Core.inventory` API to its lower-camel exports at runtime. kora_core ships neither an inventory NUI nor the `qb-inventory` provider identity.

## Public API
Server gateway (mutation/queries): `getWeight`, `canCarry`, `addItem`, `removeItem`, `getItemByName`, `getItemsByName`, `getItemBySlot`, `getItemCount`, `hasItem`, `getFreeSlot`, `moveItem`, `clearInventory`, `setItems`.
Server (useables): `createUseable`, `useItem`.
Server (stashes): `stashGet`, `stashSet`, `stashOpen`.
Server (drops): `dropCreate`, `dropTake`.
Client: `getInventory` (reads `{ 'items' }` from the mirror).
Shared math (internal, `CoreInternal.inventory`): `totalWeight`, `isUnique`, `findStackSlot`, `infoEquals`, `firstFreeSlot`. The original implementation is captured as `CoreInternal.inventory.legacy` solely for the configured staged fallback.

## Design — storage shape
`PlayerData.items` is a **slot-keyed map**: `items[slot] = { slot, name, amount, info, type, unique, useable, image, label, weight, shouldClose, description, created }`. This is the shape legacy inventory resources read, so ports work. Every write is `Core.player.setPath(src, {'items', slot}, record)` — one slot = one dirty `inventory` column + one delta op; clearing a slot is `setPath(..., nil)` (a delete op).

## Implementation notes
- **Stacking rules (shared).** `isUnique(name)` is true for weapons and items flagged `unique` — those never stack. `findStackSlot` returns the lowest slot holding a stackable match; when `Config.inventory.matchInfoOnStack` is set it also requires `infoEquals(item.info, info)` (a one-level table compare — good enough for stack decisions, stricter than legacy which ignores `info`).
- **Weight (shared).** `totalWeight` sums `def.weight * amount` per slot, pulling weights from the `items` registry then the `weapons` registry, falling back to the record's own `weight`. `canCarry` enforces `Config.inventory.maxWeight` *and* a slot check (a free slot is required unless the add fully stacks).
- **Never a partial removal.** `removeItem` computes the total across matching slots first and refuses with `'not enough of item'` if short, then drains lowest-slot-first. Per-slot removal goes through `Core.inventory._removeFromSlot` — note the leading underscore: it is **not exported** (`build/finalise.lua` skips `_`-prefixed functions), it's an internal helper.
- **Unique items take multiple slots.** `canCarry` preflights one free slot per unique item. `addItem(name, amount>1)` then places one per slot; insufficient space returns `'no free slot'` before any items are added.
- **Explicit slots are validated.** A requested slot must be within the configured range. Single-slot grants require an empty destination or a compatible non-unique stack. `nil`/`false` retain automatic selection; bulk unique grants retain their automatic placement.
- **Useables are owner-tagged** (`{resource=..., handler=...}`) and `pcall`-guarded. `useItem` accepts a slot number or an item name; with no registered handler it falls back to the legacy `QBCore:Server:UseItem` event. (There is no owner-stop sweep of useables today — unlike commands/registry — so a resource that registers a useable and restarts leaves the old handler until it re-registers.)
- **Stashes persist to the `inventories` table.** `stashGet` is a live read (yields); `stashSet` is a fire-and-forget `QB.sql.enqueue` upsert (`kind='stash'`). Stash *contents* are JSON in the `items` column.
- **Gateway is all-or-nothing.** Once kora_inventory is started, every public server operation goes through its same-named lower-camel export. Never add a partial fallback for a missing kora_inventory export: return the clear gateway error instead, otherwise player/stash authority would split.
- **Fallback is transitional.** If kora_inventory is stopped, `allowLegacyFallback` selects the captured implementation and emits one warning. Set it false in production once migration is complete; it then returns a descriptive failure instead of silently writing through kora_core.
- **Ground drops are in-memory only.** `drops[dropId] = {coords, items, created}`, broadcast to all clients on create/remove. Not persisted across restart, by design — a crash drops the drops. A sweep thread expires drops older than `Config.inventory.dropTTL` every `Config.inventory.dropSweepInterval`, so uncollected drops don't accumulate forever.
- **Client is minimal.** `qbcore:client:itemBox` shows a `QB.notify.send` by default (a UI resource can also listen); `getInventory` reads the mirror. No client-side authority.

## Best practices
- Mutate inventory only through these functions so each change is one funnel write with correct dirty/replication behaviour.
- kora_inventory owns the inventory API and bundled UI. Do not reintroduce `provide 'qb-inventory'` or direct NUI calls here; compatibility identity advertising belongs to kora_inventory only after its contracts are complete.
- Put per-instance state (serials, durability) in `info`; enable `matchInfoOnStack` if such items must not merge.
