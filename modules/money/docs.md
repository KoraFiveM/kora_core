# Money module

## Overview
Balance operations over the configured accounts (`Config.money.types`, default `cash`/`bank`/`crypto`). Every balance change routes through the player funnel — `Core.player.setPath(src, { 'money', account }, newValue)` — so money gets dirty-tracking and delta replication for free, and also emits the legacy `QBCore:Server:OnMoneyChange` / `QBCore:Client:OnMoneyChange` events. Server only. Functions are defined on `Core.money` and exported flat as `exports.kora_core:<fn>`.

## API

### `Core.money.getMoney(src, account)`
Returns a player's balance for an account, or `nil` if there is no such player.

#### Parameters
- `src: integer`
- `account: string` — One of `Config.money.types`.

#### Returns
- `number | nil`

#### Example
```lua
local cash = exports.kora_core:getMoney(src, 'cash')
```

### `Core.money.getTransactionTax(amount, account, action)`
Returns the tax the money APIs would apply with the banking provider's current
availability. This server-only query returns `0` while that provider is stopped;
`calculateTax` continues to return the configured estimate. It does not reserve
a balance or guarantee that a later tax deposit succeeds.

### `Core.money.addMoney(src, account, amount, reason, ignoreTax)`
Adds a **positive** amount to an account. `amount` is the **gross** figure: when
the [transaction tax](#transaction-tax) applies, the player receives
`amount - tax` and the tax is banked.

#### Parameters
- `src: integer`
- `account: string`
- `amount: number` — Must be `> 0`.
- `reason: string | nil` — Passed through to the money-change events for logging.
- `ignoreTax: boolean | nil` — `true` exempts this call from the transaction tax.

#### Returns
- `boolean` — `true` on success.
- `string | nil` — Failure reason (`'invalid account'`, `'amount must be positive'`, `'no such player'`).

#### Example
```lua
local ok, err = exports.kora_core:addMoney(src, 'bank', 500, 'paycheck')
```

### `Core.money.removeMoney(src, account, amount, reason, ignoreTax)`
Removes a **positive** amount, refusing to drop below the account floor (0, or `Config.money.minusLimit` for accounts in `Config.money.allowNegative`). The player always pays exactly `amount`; with the [transaction tax](#transaction-tax) on, a slice of it is banked instead of destroyed, so the player-facing cost is identical either way.

#### Parameters
- `src: integer`
- `account: string`
- `amount: number` — Must be `> 0`.
- `reason: string | nil`
- `ignoreTax: boolean | nil` — `true` exempts this call from the transaction tax.

#### Returns
- `boolean`
- `string | nil` — Failure reason (`'invalid account'`, `'amount must be positive'`, `'no such player'`, `'insufficient funds'`).

### `Core.money.setMoney(src, account, amount, reason)`
Sets an account to an exact amount, refusing a value below the account floor. **Never taxed** — this is an absolute assignment (admin edit, reset, migration), not a transaction, so there is no `ignoreTax` parameter.

#### Parameters
- `src: integer`
- `account: string`
- `amount: number`
- `reason: string | nil`

#### Returns
- `boolean`
- `string | nil` — Failure reason (`'invalid account'`, `'amount must be a number'`, `'below account floor'`, `'no such player'`).

### `Core.money.transferMoney(fromSrc, toSrc, account, amount, reason, ignoreTax)`
Moves money between two online players: removes from the sender, then adds to the recipient. If the add fails, the sender is **refunded** and the whole transfer reports failure. With the [transaction tax](#transaction-tax) on, the sender pays `amount` and the recipient receives `amount - tax`.

#### Parameters
- `fromSrc: integer`
- `toSrc: integer`
- `account: string`
- `amount: number`
- `reason: string | nil`
- `ignoreTax: boolean | nil` — `true` exempts this call from the transaction tax.

#### Returns
- `boolean`
- `string | nil` — The underlying `removeMoney`/`addMoney` failure reason.

#### Example
```lua
local ok, err = exports.kora_core:transferMoney(fromSrc, toSrc, 'cash', 100, 'trade')
```

## Transaction tax

A configurable percentage of every transaction can be diverted to a "government"
account held by a banking resource. **Off by default** — an existing economy is
unchanged until a server opts in.

```lua
Config.money.tax = {
    enabled = false,             -- master switch
    rate = 0.05,                 -- 5% of each taxable transaction
    account = 'government',      -- banking account the tax is deposited into
    provider = 'qb-banking',     -- resource holding that account
    autoCreateAccount = true,    -- create `account` on first collection
    exports = { add = 'AddMoney', get = 'GetAccount', create = 'CreateJobAccount' },
    accounts = { cash = true, bank = true, crypto = false },
    actions = { add = true, remove = true, transfer = true },
}
```

### How much the player pays

The tax is always carved **out of** the amount, never added on top. A caller that
worked before tax was switched on still works after, because the payer's side of
the call is unchanged:

| Call | Player | Recipient | Government |
| --- | --- | --- | --- |
| `addMoney(src, 'bank', 100)` | `+95` | — | `+5` |
| `removeMoney(src, 'bank', 100)` | `-100` | — | `+5` |
| `transferMoney(a, b, 'bank', 100)` | `a: -100` | `b: +95` | `+5` |
| `setMoney(src, 'bank', 100)` | `= 100` | — | `0` (never taxed) |

The tax is **floored** (`math.floor(amount * rate)`), so it is never more than the
strict share and a whole-number amount stays whole — a $19 purchase at 5% is
taxed $0. The money-change events carry the **net** the balance actually moved
by, not the gross.

### Exempting a transaction

Pass `ignoreTax = true` as the last argument:

```lua
-- Taxed: the player nets $950 of this $1,000 payout.
exports.kora_core:addMoney(src, 'bank', 1000, 'heist payout')

-- Tax-free: a refund must not be taxed, or the player pays twice for one purchase.
exports.kora_core:addMoney(src, 'bank', 1000, 'refund', true)
```

Exempt anything that is not economic activity: refunds and rollbacks, admin
grants, a player moving their own money between their own accounts (ATM
deposit/withdrawal), and anything already taxed upstream.

The same parameter is on the legacy compat surface, past stock qb-core's 3-arg
signature — an unported resource simply passes `nil` and is taxed:

```lua
Player.Functions.AddMoney('bank', 1000, 'refund', true)
Player.Functions.RemoveMoney('cash', 250, 'admin fee', true)
```

### Availability — it fails open

If the banking resource is stopped, rejects the deposit, or the account is
missing and cannot be created, **the transaction goes through untaxed**. It is
never failed and the slice is never silently destroyed: a bank outage must not
cost a player money or freeze the economy. The skip is printed at most once a
minute.

Because the deposit writes to the database, it is dispatched onto a thread rather
than run inline. The player-side mutation lands first; if the deposit then fails,
the withheld tax is **refunded** — to the receiving player on `addMoney`, to the
sender on `transferMoney`, and to nobody on `removeMoney` (that money was leaving
the player either way).

### Reading and collecting tax directly

### `Core.money.getTaxRate(account, action)`
Effective rate as a `0..1` fraction, or `0` when tax is off, the account is not
in `tax.accounts`, or the action is not in `tax.actions`. Config only — it does
not consult the banking resource's live state. `action` is `'add'`, `'remove'` or
`'transfer'`; `nil` skips the action check.

### `Core.money.calculateTax(amount, account, action)`
The tax that would be carved out of `amount`. Pure — safe to call from a shop UI
to show a tax-inclusive breakdown.

```lua
local tax = exports.kora_core:calculateTax(price, 'bank', 'remove')
print(('$%d (includes $%d tax)'):format(price, tax))
```

### `Core.money.getTaxAccount()`
The banking account name collected tax lands in, or `nil` when tax is disabled.

### `Core.money.collectTax(amount, reason)`
Deposits `amount` into the government account directly, creating it through the
provider if needed. For levies that are not a money mutation — a court fine, a
licence fee, a business rates sweep. Returns `(true)` / `(false, err)`.

**Yields** (the provider's deposit export hits the database), so call it from a
thread:

```lua
CreateThread(function()
    exports.kora_core:collectTax(500, 'business rates')
end)
```

### Events
`qbcore:server:taxCollected(account, amount, reason)` fires server-side after
each successful deposit.


## Notes
- **The funnel does the persistence/replication.** These functions only compute the new balance and call `setPath`; they never touch the DB or the wire directly.
- **Account floors.** By default an account cannot go negative (floor `0`). Accounts listed in `Config.money.allowNegative` may go down to `Config.money.minusLimit`.
- **`addMoney`/`removeMoney` take positive amounts only** — pass the magnitude; direction is chosen by which function you call. `setMoney` takes the absolute target.
- **`transferMoney` is atomic-ish, not transactional.** The remove is committed before the add; a failed add triggers a compensating refund rather than a rollback.
- **Tax is settled once per transaction.** `transferMoney` computes it up front and runs both legs exempt, so a transfer is never taxed twice.

## Offline credits

`exports.kora_core:addOfflineMoney(citizenid, account, amount)` atomically increments a stored character balance without rewriting other player columns. It validates the account and positive finite amount, refuses online characters, and returns `(true)` or `(false, reason)`. It yields and retains the untaxed behavior of legacy offline credits. Use `addMoney` for online players.
