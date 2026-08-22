# Money module

## Overview
Balance operations over the configured accounts (`Config.money.types`, default `cash`/`bank`/`crypto`). Every balance change routes through the player funnel — `Core.player.setPath(src, { 'money', account }, newValue)` — so money gets dirty-tracking and delta replication for free, and also emits the legacy `QBCore:Server:OnMoneyChange` / `QBCore:Client:OnMoneyChange` events. Server only. Functions are defined on `Core.money` and exported flat as `exports.qbcore:<fn>`.

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
local cash = exports.qbcore:getMoney(src, 'cash')
```

### `Core.money.addMoney(src, account, amount, reason)`
Adds a **positive** amount to an account.

#### Parameters
- `src: integer`
- `account: string`
- `amount: number` — Must be `> 0`.
- `reason: string | nil` — Passed through to the money-change events for logging.

#### Returns
- `boolean` — `true` on success.
- `string | nil` — Failure reason (`'invalid account'`, `'amount must be positive'`, `'no such player'`).

#### Example
```lua
local ok, err = exports.qbcore:addMoney(src, 'bank', 500, 'paycheck')
```

### `Core.money.removeMoney(src, account, amount, reason)`
Removes a **positive** amount, refusing to drop below the account floor (0, or `Config.money.minusLimit` for accounts in `Config.money.allowNegative`).

#### Parameters
- `src: integer`
- `account: string`
- `amount: number` — Must be `> 0`.
- `reason: string | nil`

#### Returns
- `boolean`
- `string | nil` — Failure reason (`'invalid account'`, `'amount must be positive'`, `'no such player'`, `'insufficient funds'`).

### `Core.money.setMoney(src, account, amount, reason)`
Sets an account to an exact amount, refusing a value below the account floor.

#### Parameters
- `src: integer`
- `account: string`
- `amount: number`
- `reason: string | nil`

#### Returns
- `boolean`
- `string | nil` — Failure reason (`'invalid account'`, `'amount must be a number'`, `'below account floor'`, `'no such player'`).

### `Core.money.transferMoney(fromSrc, toSrc, account, amount, reason)`
Moves money between two online players: removes from the sender, then adds to the recipient. If the add fails, the sender is **refunded** and the whole transfer reports failure.

#### Parameters
- `fromSrc: integer`
- `toSrc: integer`
- `account: string`
- `amount: number`
- `reason: string | nil`

#### Returns
- `boolean`
- `string | nil` — The underlying `removeMoney`/`addMoney` failure reason.

#### Example
```lua
local ok, err = exports.qbcore:transferMoney(fromSrc, toSrc, 'cash', 100, 'trade')
```

## Notes
- **The funnel does the persistence/replication.** These functions only compute the new balance and call `setPath`; they never touch the DB or the wire directly.
- **Account floors.** By default an account cannot go negative (floor `0`). Accounts listed in `Config.money.allowNegative` may go down to `Config.money.minusLimit`.
- **`addMoney`/`removeMoney` take positive amounts only** — pass the magnitude; direction is chosen by which function you call. `setMoney` takes the absolute target.
- **`transferMoney` is atomic-ish, not transactional.** The remove is committed before the add; a failed add triggers a compensating refund rather than a rollback.
