# money module guide

## Purpose
Balance operations over the configured money accounts, implemented as thin wrappers over the player funnel so money inherits dirty-tracking and delta replication without any bespoke persistence. Server only.

## Public API
- `Core.money.getMoney(src, account)` — balance or `nil`.
- `Core.money.addMoney(src, account, amount, reason, ignoreTax)` — add a positive amount. `(true)` / `(false, err)`.
- `Core.money.removeMoney(src, account, amount, reason, ignoreTax)` — remove a positive amount, respecting the floor. `(true)` / `(false, err)`.
- `Core.money.setMoney(src, account, amount, reason)` — set an exact amount, respecting the floor. `(true)` / `(false, err)`. Never taxed.
- `Core.money.transferMoney(fromSrc, toSrc, account, amount, reason, ignoreTax)` — remove-then-add with refund on failure.
- `Core.money.getTaxRate(account, action)` / `Core.money.calculateTax(amount, account, action)` — pure config reads, for showing a tax-inclusive breakdown in a UI.
- `Core.money.getTaxAccount()` — the government banking account name, or `nil` when tax is off.
- `Core.money.collectTax(amount, reason)` — bank an off-path levy (a fine, a licence fee). **Yields**; call it from a thread.

## Implementation notes
- **Everything is `Core.player.setPath(src, {'money', account}, newValue)`.** That's the entire persistence/replication story — money is dirty-tracked as the `money` column and replicated as a `{p={'money',account}, v=newValue}` delta because the funnel does it. These wrappers only validate and compute.
- **Legacy events on every change.** Each mutation fires both `QBCore:Server:OnMoneyChange` and `QBCore:Client:OnMoneyChange` with `(src, account, amount, action, reason)` where action is `'add'`/`'remove'`/`'set'`, so ported resources keep working.
- **Account validity + floors come from config.** `validAccount` checks membership in `Config.money.types`; `floorFor` returns `0` normally, or `Config.money.minusLimit` for an account flagged in `Config.money.allowNegative`. `addMoney`/`removeMoney` insist on a positive magnitude; `setMoney` takes the absolute target and only checks the floor.
- **`transferMoney` compensates rather than rolls back.** It calls `removeMoney` then `addMoney`; if the add fails it re-adds to the sender (`reason='transfer-refund'`). There is no DB transaction spanning the two — this is an in-memory operation on two live handles, and the funnel persists each side independently.
## The transaction tax
`Config.money.tax` diverts a percentage of each transaction into a banking
account (`tax.account`, default `government`) held by `tax.provider` (default
`qb-banking`, reached through the three configurable export names in
`tax.exports` so any bank works). OFF by default. Five decisions worth knowing:

- **The tax is carved OUT of the amount, never added on top.** `remove` costs the
  player exactly `amount` and the government takes its slice off the top instead
  of the whole sum vanishing; `add` pays the player `amount - tax`; `transfer`
  charges the sender `amount` and pays the recipient `amount - tax`. Charging on
  top would mean a call that succeeded yesterday fails today for insufficient
  funds — every shop/job/heist resource in the wild would need re-auditing for
  money it never knew it needed. Carving out leaves the payer's side of each
  existing call site byte-identical.
- **`setMoney` is never taxed** and has no `ignoreTax` param. It is an absolute
  assignment (admin edit, reset, migration), not a transaction.
- **It fails OPEN.** A stopped banking resource, a rejected deposit or a
  missing-and-uncreatable account means the transaction goes through *untaxed* —
  never failed, never with the slice silently destroyed. A bank outage must not
  cost a player money or freeze the economy.
- **The deposit runs on a `CreateThread`, with a compensating refund.** The
  provider's deposit export writes to the database, so it cannot run inline on a
  money mutation. The player-side mutation lands first; if the deposit then
  fails, the withheld tax is returned — to the receiving player on `add`, to the
  sender on `transfer` (which leaves exactly an untaxed transfer of the net), and
  to nobody on `remove` (that money was leaving either way). The refund re-enters
  `addMoney` with `ignoreTax = true`, so it cannot recurse.
- **`tax.accounts` / `tax.actions` are allow-lists.** A key that is absent or not
  `true` is not taxed. Omitting the whole table means "everything".

The physical-cash path takes the tax as its own provider call: `transferMoney`
removes the tax from the sender *first*, then moves the net, so the pair costs
the sender the same as an untaxed transfer of `amount` (it can never newly fail
for funds) and a failed move has exactly one thing to put back.

- **No `CoreInternal.money` table.** `validAccount`/`floorFor` are file-local. Internals in other modules live on `CoreInternal.<module>` and are never exported; `build/finalise.lua` walks only `Core.<module>` and skips `_`-prefixed functions.

## Best practices
- Pass a meaningful `reason` — it flows into the money-change events and any logging built on them.
- Don't write `PlayerData.money` directly; use these wrappers so the funnel, events, and floors all apply.
- Pass `ignoreTax = true` for movements that are not economic activity: refunds, admin grants, moving a player's own money between their own accounts (an ATM deposit/withdrawal), rollbacks, and anything already taxed upstream. Taxing a refund charges the player twice for one purchase.
- The money-change events carry the **net** the balance actually moved by, not the gross. Anything reconciling balances against those events stays correct with tax on.
