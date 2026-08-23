# Consumables module

## Overview
Bridges qbinventory's `usingItem` hook to `QB.status`/`QB.fx` and hunger/thirst/stress metadata, driven entirely by an item's shared `.effect` table. Server only. Functions are defined on `Core.consumables` and exported flat as `exports.qbcore:<fn>`.

## API

### `Core.consumables.isRegistered()`
Whether the qbinventory `usingItem` hook is currently registered.

#### Returns
- `boolean`

#### Example
```lua
if not exports.qbcore:isRegistered() then
    print('qbinventory effect bridge is not active')
end
```

## Notes
- **Data-driven, not per-item code.** Give an item (in `shared/items.lua`, or any resource's own item registration) an `effect` table and this module applies it automatically whenever the item is used through qbinventory:
  ```lua
  effect = { hungerDelta = 10, thirstDelta = -5, stressDelta = -2 }
  ```
- **Cosmetic/status only.** This never denies a use and never runs real gameplay logic (healing HP, curing an overdose, etc.) — that stays in the item's own `Core.inventory.createUseable` handler (`exports.qbcore:createUseable`), registered independently.
- **Enable/disable via `Config.consumables.enabled`.** When `false`, the hook is never registered.
- **Requires qbinventory.** If qbinventory isn't running, `isRegistered()` returns `false` until it starts; registration is retried on qbinventory's `onResourceStart`.
