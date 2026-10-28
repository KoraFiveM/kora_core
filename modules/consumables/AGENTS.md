# consumables module guide

## Purpose
The generic item-effect bridge. Reads an item's shared `.effect` table (set by whichever resource registered the item, e.g. kora_ambulance's bandage, kora_drugs' every drug item) and plays it back via `QB.status`/metadata when the item is used — ONE hook services every effect-bearing item in the whole framework, so a new drug/medical item needs only a data entry, never new game logic. Server only.

This layer is **cosmetic/status only** and never denies an item use — real gameplay effects (actually healing HP, etc.) stay in each job resource's own `Core.inventory.createUseable` handler, which runs independently of this hook.

## Public API
- `Core.consumables.isRegistered()` — `boolean`, whether the kora_inventory `usingItem` hook is currently registered.

## Implementation notes
- **Two real integration constraints**, both confirmed by reading kora_inventory's own source (not assumed):
  1. kora_core is a **dependency** of kora_inventory, so FXServer starts kora_core first — registering the hook must be deferred to `onResourceStart`, never called unconditionally at load time, or it errors against a not-yet-running kora_inventory.
  2. kora_inventory's `runHooks` passes `(payload, src)` to a `usingItem` hook — this relies on that shape rather than parsing `src` back out of `payload.inventoryId`.
- **Registered via `exports.kora_inventory:RegisterHook`** (capital `R` — FiveM export names are case-sensitive; kora_inventory's own export table only defines the capitalized form, see `kora_inventory/server.lua`'s exports block).
- **`register()` runs both at file-load and on `onResourceStart`.** The unconditional call at load time covers kora_inventory already running when kora_core starts (a restart, not a fresh boot); the `onResourceStart` handler covers the fresh-boot ordering.
- **Effect application never denies the use.** `onUsingItem` always returns `true` so a status-apply failure (logged, not raised) can't block whatever the item's own `createUseable` handler does.

## Best practices
- Give a new effect-bearing item a shared `.effect` table (`hungerDelta`/`thirstDelta`/`stressDelta`, plus whatever `QB.status`/`QB.fx` consume) instead of writing a bespoke `createUseable` handler just to apply cosmetic status changes.
- Real, non-cosmetic gameplay effects still belong in the item's own `createUseable` handler — don't try to encode them into `.effect`.
