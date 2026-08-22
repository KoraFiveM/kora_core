# money module guide

## Purpose
Balance operations over the configured money accounts, implemented as thin wrappers over the player funnel so money inherits dirty-tracking and delta replication without any bespoke persistence. Server only.

## Public API
- `Core.money.getMoney(src, account)` — balance or `nil`.
- `Core.money.addMoney(src, account, amount, reason)` — add a positive amount. `(true)` / `(false, err)`.
- `Core.money.removeMoney(src, account, amount, reason)` — remove a positive amount, respecting the floor. `(true)` / `(false, err)`.
- `Core.money.setMoney(src, account, amount, reason)` — set an exact amount, respecting the floor. `(true)` / `(false, err)`.
- `Core.money.transferMoney(fromSrc, toSrc, account, amount, reason)` — remove-then-add with refund on failure.

## Implementation notes
- **Everything is `Core.player.setPath(src, {'money', account}, newValue)`.** That's the entire persistence/replication story — money is dirty-tracked as the `money` column and replicated as a `{p={'money',account}, v=newValue}` delta because the funnel does it. These wrappers only validate and compute.
- **Legacy events on every change.** Each mutation fires both `QBCore:Server:OnMoneyChange` and `QBCore:Client:OnMoneyChange` with `(src, account, amount, action, reason)` where action is `'add'`/`'remove'`/`'set'`, so ported resources keep working.
- **Account validity + floors come from config.** `validAccount` checks membership in `Config.money.types`; `floorFor` returns `0` normally, or `Config.money.minusLimit` for an account flagged in `Config.money.allowNegative`. `addMoney`/`removeMoney` insist on a positive magnitude; `setMoney` takes the absolute target and only checks the floor.
- **`transferMoney` compensates rather than rolls back.** It calls `removeMoney` then `addMoney`; if the add fails it re-adds to the sender (`reason='transfer-refund'`). There is no DB transaction spanning the two — this is an in-memory operation on two live handles, and the funnel persists each side independently.
- **No `CoreInternal.money` table.** `validAccount`/`floorFor` are file-local. Internals in other modules live on `CoreInternal.<module>` and are never exported; `build/finalise.lua` walks only `Core.<module>` and skips `_`-prefixed functions.

## Best practices
- Pass a meaningful `reason` — it flows into the money-change events and any logging built on them.
- Don't write `PlayerData.money` directly; use these wrappers so the funnel, events, and floors all apply.
