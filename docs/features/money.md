---
title: Money and transactions
sidebar_position: 2
---

# Money and transactions

Accounts are the names in `Config.money.types` (default `cash`, `bank`, `crypto`).
Balances live in `PlayerData.money` and change only through the money API, which
writes through the player funnel and emits the legacy money events. All functions
are server-side.

## API

| Export | Returns | Description |
| --- | --- | --- |
| `getMoney(src, account)` | number or `nil` | Current balance. For a physical-cash account the inventory provider is asked. |
| `addMoney(src, account, amount, reason, ignoreTax)` | `true` or `false, err` | Adds a positive gross amount. With tax the player receives `amount - tax`. |
| `removeMoney(src, account, amount, reason, ignoreTax)` | `true` or `false, err` | Removes a positive amount; refuses to go below the account floor. The player always pays exactly `amount`. |
| `setMoney(src, account, amount, reason)` | `true` or `false, err` | Sets an exact balance. Never taxed. |
| `transferMoney(fromSrc, toSrc, account, amount, reason, ignoreTax)` | `true` or `false, err` | Removes from the sender, then adds to the recipient; refunds the sender if the add fails. |
| `addOfflineMoney(citizenid, account, amount)` | `true` or `false, err` | Yields. Atomically increments a stored balance of an offline character (`JSON_SET` on `players.money`). Untaxed. Refuses online characters. |

Failure reasons include `invalid account`, `amount must be positive`,
`amount must be a finite number`, `insufficient funds`, `below account floor`,
`no such player`, `invalid transfer`, `player data is busy`, and for physical cash
`physical cash provider unavailable` and `physical cash amount must be whole`.

The account floor is `0`, or `Config.money.minusLimit` for accounts listed in
`Config.money.allowNegative` (empty by default, so no account can go negative).

```lua
local ok, err = exports.kora_core:removeMoney(source, 'bank', 250, 'parking fine')
if not ok then
    print(('fine failed: %s'):format(err))
end
```

### Side effects of every balance change

- Server event `QBCore:Server:OnMoneyChange(src, account, amount, action, reason)`
- Client events `QBCore:Client:OnMoneyChange(account, amount, action, reason)` and
  `hud:client:OnMoneyChange(account, amount, isRemove)`
- `qb-phone:client:RemoveBankMoney(amount)` for bank removals
- Replicated player state bag `kora_core:money:<account>` with the new balance
  (also published for every account at login)

`amount` in these events is the net amount actually moved. For `setMoney` the
action is `set`; on the normal ledger the amount is the new balance, and on a
physical-cash account it is the absolute difference.

## Transaction tax

When `Config.money.tax.enabled` is on, a share of each taxable add, remove or
transfer is deposited into a banking account (`government` on `qb-banking` by
default). The tax is carved out of the amount, never added on top:

| Call | Player | Recipient | Government |
| --- | --- | --- | --- |
| `addMoney(src, 'bank', 100)` | +95 | | +5 |
| `removeMoney(src, 'bank', 100)` | -100 | | +5 |
| `transferMoney(a, b, 'bank', 100)` | a: -100 | b: +95 | +5 |
| `setMoney(src, 'bank', 100)` | = 100 | | 0 |

- The tax is `math.floor(amount * rate)`; small amounts can round to 0.
- Pass `ignoreTax = true` for movements that are not economic activity (refunds,
  admin grants, moving money between a player's own accounts). Legacy
  `Player.Functions.AddMoney/RemoveMoney` accept the same fourth argument.
- If the provider is not started, the transaction goes through untaxed (a warning
  is printed at most once a minute).
- The deposit runs on a separate thread after the player-side change. If it fails,
  the withheld tax is refunded to the receiving player for `addMoney`, to the
  sender for `transferMoney` (offline characters are credited with
  `addOfflineMoney`), and to nobody for `removeMoney`.
- A transfer is taxed once; both legs run untaxed internally.

| Export | Description |
| --- | --- |
| `getTaxRate(account, action)` | Configured rate (0..1), or 0 when tax is off or the account/action is not taxed. `nil` skips that check. |
| `calculateTax(amount, account, action)` | Tax that would be carved out, from configuration only. |
| `getTransactionTax(amount, account, action)` | Tax that would actually be applied now (0 while the provider is stopped). |
| `getTaxAccount()` | Tax account name, or `nil` when tax is disabled. |
| `collectTax(amount, reason)` | Yields. Deposits directly into the tax account (creating it if allowed). Returns `true` or `false, err`. |

```lua
CreateThread(function()
    local ok, err = exports.kora_core:collectTax(500, 'business rates')
end)
```

After each successful deposit the server event
`kora_core:server:taxCollected(account, amount, reason)` fires.

## Physical cash

The configured inventory provider (`Config.inventory.provider`) can take ownership
of the `Config.money.cashType` account so cash exists as an item:

| Export | Caller | Description |
| --- | --- | --- |
| `registerPhysicalCash(account)` | inventory provider only | Imports every online player's ledger cash into the provider (`physicalCashCanImport`, `physicalCashImport`), sets the ledger to 0 and routes the account to the provider. |
| `unregisterPhysicalCash(account)` | the registered provider | Returns the account to the ledger. |
| `isPhysicalCash(account)` | any | Whether the account is provider-owned. |
| `migratePhysicalCash(src)` | any | Imports one player's ledger cash; runs automatically at login. |
| `syncState(src)` | any | Republishes the `kora_core:money:<account>` state bags. |

While registered, `getMoney`, `addMoney`, `removeMoney`, `setMoney` and
`transferMoney` call the provider's `physicalCashGet`, `physicalCashAdd`,
`physicalCashRemove`, `physicalCashSet` and `physicalCashTransfer` exports. If the
provider stops, those calls fail instead of falling back to the ledger. The stored
ledger stays 0, while the legacy PlayerData view and the replicated client mirror
show the real balance, refreshed on money changes and on
`kora_core:server:inventoryChanged`. Direct `setPath` writes to the cash account
are refused.

## Transactions

`transaction(src, definition)` applies a set of money and item changes after
checking all of them first:

```lua
local ok, err = exports.kora_core:transaction(source, {
    reason = 'shop purchase',
    coords = vector3(1.0, 2.0, 3.0), -- metadata only, no distance check
    money = {
        remove = { { account = 'cash', amount = 500 } },
        add = { { account = 'bank', amount = 50 } },
    },
    items = {
        remove = { { item = 'water_bottle', amount = 1 } },
        add = { { item = 'sandwich', amount = 2, info = {} } },
    },
    random = {
        { item = 'water_bottle' },
        { item = 'bread' },
        { item = 'cryptostick', chance = 1, amount = { min = 1, max = 2 } },
    },
})
```

- Amounts must be positive whole numbers. Item entries use `item`, `amount`,
  optional `slot` and `info`; money entries use `account` and `amount`.
- Checked before any change: money balances, item counts, carry capacity for all
  additions (including winning random items) and that added accounts exist.
- Order: remove money, remove items, add items, add money. A failure triggers a
  best-effort reversal of the steps already done.
- Money moved by a transaction is never taxed.
- `random` is rolled once with `Kora.rewards.generate` in percent mode with
  `allowNone`. `chance` is an independent percentage; entries without a chance share
  100 percent equally. `amount` defaults to 1 or may be a positive integer or a
  `min`/`max` range. Zero, one or several entries can win; winners are added like
  `items.add` entries.

This is compensating rollback, not crash-proof atomicity, and concurrent calls can
race. The caller must authorize the operation and validate price, ownership,
permissions and distance. Never pass a client-built definition.

## Paychecks

See [Jobs and gangs](./jobs-gangs.md#paychecks). Paychecks are credited to
`Config.money.cashType` with reason `paycheck` and are subject to the tax.
