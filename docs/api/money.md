---
title: "Money, accounts and transactions"
sidebar_position: 3
---


# Money, accounts and transactions

Server-authoritative balances for the accounts listed in `Config.money.types` (default `cash`, `bank`, `crypto`). Every change goes through `Core.player.setPath(src, {'money', account}, value)`, so balances get dirty-tracking, delta replication to the client and persistence in the `players.money` column. On top of that the module owns two optional systems: the physical-cash provider model (the `cash` account lives as an item stack in the inventory resource) and the transaction tax (a percentage of each add/remove/transfer is carved out and deposited into a banking account). The bare export `transaction` applies several money and item changes as one validated, rolled-back unit.

Namespace: `exports.kora_core` · Source: `modules/money/server.lua, modules/transaction/server.lua`

## Config.money

Defined in config.lua. `Config.money.default` seeds the balances of a newly created character (accounts missing from it start at 0).

| Key | Default | Meaning |
| --- | --- | --- |
| types | &#123; 'cash', 'bank', 'crypto' &#125; | Valid account names. Anything else returns `invalid account`. |
| default | &#123; cash = 500, bank = 5000, crypto = 0 &#125; | Starting balances for a new character. |
| cashType | 'cash' | The account that paychecks credit and the only account allowed to become physical cash. |
| allowNegative | &#123; bank = true &#125; | Accounts that may go below zero. Other accounts have a floor of 0. |
| minusLimit | -50000 | Floor for accounts listed in allowNegative (`-math.huge` if unset). Used by `removeMoney` and `setMoney`. |
| tax.enabled | false | Master switch. While false every tax function returns 0 and nothing is withheld. |
| tax.rate | 0.05 | Fraction (0 to 1) of each taxable transaction. Values above 1 are clamped to 1; 0 or below disables. |
| tax.account | 'government' | Banking account that receives the tax. |
| tax.provider | 'qb-banking' | Resource holding that account. While it is not started, transactions go through untaxed. |
| tax.autoCreateAccount | true | Create `tax.account` through the provider on first collection. Set to `false` to fail with `banking account <name> does not exist` instead. |
| tax.exports | &#123; add = 'AddMoney', get = 'GetAccount', create = 'CreateJobAccount' &#125; | Provider export names, so another banking resource can be used. Missing keys fall back to these defaults. |
| tax.accounts | &#123; cash = true, bank = true, crypto = false &#125; | Allow-list of taxable accounts. An account absent or not `true` is never taxed; omit the table to tax all accounts. |
| tax.actions | &#123; add = true, remove = true, transfer = true &#125; | Allow-list of taxable operations. Omit the table to tax all three. `setMoney` is never taxed. |

## How it works

Mutating exports (`addMoney`, `removeMoney`, `setMoney`, `transferMoney`) return `true` on success and `false, reason` on failure; they never throw for bad input. Read exports return `nil` when the player or balance cannot be resolved. All of these exports run on the server only and can be called by any resource (no `GetInvokingResource()` check) except `registerPhysicalCash` and `unregisterPhysicalCash`, which only accept the inventory provider. Clients cannot call them; a client only receives the resulting events and state bag.

## Terms used on this page

| Term | Meaning |
| --- | --- |
| Ledger | The `PlayerData.money[account]` value persisted in `players.money`. For a normal account it is the balance. For a physical-cash account it is held at 0 and is not the balance. |
| Physical cash | An account registered through `registerPhysicalCash`. Its real balance is the item stack owned by the inventory provider; `getMoney`, `addMoney`, `removeMoney`, `setMoney` and `transferMoney` call the provider's `physicalCash*` exports instead of touching the ledger. Only `Config.money.cashType` can be physical. |
| Mirror | While an account is physical, the real balance is overlaid onto the legacy-shaped PlayerData view and onto outgoing replication ops and snapshots, so stock qb-* scripts that read `PlayerData.money.cash` see the item balance. The ledger and persistence are never written by the mirror. It refreshes on every Core.money change and on every `kora_core:server:inventoryChanged` event; nothing polls. |
| Government account | The banking account named by `Config.money.tax.account` (default `government`) that receives collected tax. |
| Gross / net | For a taxed `add`, `amount` is gross and the player receives `amount - tax`. For `remove` the player always pays the full `amount`. For `transfer` the sender pays `amount` and the recipient receives `amount - tax`. |

## transaction input table

Every list is an array of tables. Amounts must be positive whole numbers. Item entries for the same item name are summed for the pre-checks; money entries are checked one by one (two entries on the same account are each compared against the full balance in the pre-check). A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `reason?` | string | Passed as the reason to every money and inventory call. Rollback uses `transaction rollback`. |
| `money.remove?` | &#123; account, amount &#125;[] | Amounts to take. Applied first. |
| `money.add?` | &#123; account, amount &#125;[] | Amounts to give. Applied last. Legs use `ignoreTax = true`. |
| `items.remove?` | &#123; item, amount, slot? &#125;[] | Items to take, optionally from a specific slot. |
| `items.add?` | &#123; item, amount, slot?, info? &#125;[] | Items to give, with optional forced slot and item `info`. |
| `random?` | &#123; item, amount?, chance?, ... &#125;[] | Bonus items rolled by `Kora.rewards.generate` in percent mode with `allowNone = true`, so all of them can miss. `amount` is a whole number or `{ min, max }`, default 1. `chance` is a percent above 0 up to 100; entries that omit it share an equal split of 100 (so a single entry without `chance` has a 100% chance). Hits are appended to `items.add`. |

## Physical cash and the inventory provider

The provider is the resource named by `Config.inventory.provider` (default `kora_inventory`). On start it calls `exports.kora_core:registerPhysicalCash('cash')`. Core then preflights every online player's legacy ledger balance through the provider export `physicalCashCanImport(src, account, balance)`, registers the account, and imports each balance with `physicalCashImport(src, account, balance)` before zeroing the ledger. A full inventory refuses the switch rather than losing money. New players are migrated through `migratePhysicalCash` before their first snapshot.

While registered, balance operations call the provider exports `physicalCashGet`, `physicalCashAdd`, `physicalCashRemove`, `physicalCashSet` and `physicalCashTransfer`. Amounts must be whole numbers (`physical cash amount must be whole`). The registration is kept if the provider stops unexpectedly: operations then fail closed with `physical cash provider unavailable` instead of falling back to a second ledger balance. A provider that stops cleanly calls `unregisterPhysicalCash`, which restores the ledger value to the legacy view and the client.

While an account is physical, `Core.player.setPath` refuses direct writes to `money.<account>` with `physical cash account is inventory-owned`; only the one-way migration may write it.

## Transaction tax model

The tax is always carved out of the amount, never added on top, so the payer side of every call stays identical to an untaxed call. `remove`: the player pays `amount`, the tax slice is banked instead of vanishing. `add`: the player receives `amount - tax`. `transfer`: sender pays `amount`, recipient receives `amount - tax`. `tax = floor(amount * rate)`, so a whole amount stays whole and a small amount can tax to 0. `setMoney`, `addOfflineMoney` and `transaction` legs are never taxed. Pass `ignoreTax = true` as the last argument of `addMoney`, `removeMoney` or `transferMoney` to exempt one call. Paychecks call `addMoney` without `ignoreTax`, so they are taxed when tax is enabled for `cash` and `add`.

The tax is failure-open. If the provider resource is not started the transaction proceeds untaxed and a warning (`[kora_core:money] transaction tax skipped: ...`) is printed at most once per 60 seconds. The deposit itself runs in a new thread (it writes to the database) and never blocks the money change. If the deposit fails, a failed `add` or `transfer` refunds the withheld tax to the player it was taken from (reason `tax-refund`); a failed `remove` just loses the slice, exactly like an untaxed remove. The provider is called as `exports[provider].AddMoney(account, amount, reason or 'tax')` and, on first use, `GetAccount(account)` then `CreateJobAccount(account, 0)` (export names from `tax.exports`). After a successful deposit core fires the local event `kora_core:server:taxCollected(account, amount, reason)`.

## Side effects of every money change

After each successful `addMoney`, `removeMoney` and `setMoney` (and for both legs of `transferMoney`), core does the following in order. The physical-cash mirror is refreshed. The state bag `Player(src).state['kora_core:money:<account>']` is set (replicated) to the new balance, which is what kora_hud reads. The local server event `QBCore:Server:OnMoneyChange(src, account, amount, action, reason)` is fired. The client events `QBCore:Client:OnMoneyChange(account, amount, action, reason)` and `hud:client:OnMoneyChange(account, amount, isRemove)` are sent to that player (the second is the legacy qb-hud popup hook). For a `bank` removal the client event `qb-phone:client:RemoveBankMoney(amount)` is also sent.

`action` is `add`, `remove` or `set`. `amount` is the net amount credited for `add`, the gross amount for `remove`, and for `set` the new balance on a normal account but the absolute difference from the previous balance on a physical account. In a transfer the sender gets a `remove` event with the gross amount and the recipient an `add` event with the net amount. Nothing is fired when a taxed add nets to 0 (100% rate).

## Transaction input shape, ordering and rollback

See the `transaction` entry. Validation is complete before the first change: every leg is checked, then applied in a fixed order (remove money, remove items, add items, add money). A failure at any step undoes the earlier steps in reverse. It is not atomic in the database sense: rollback is a best-effort replay whose results are ignored, and other resources can change balances or inventory between the validation pass and the apply pass.

## Functions

Amounts are plain numbers in whole currency units. Accounts that are not in `Config.money.types` are rejected with `invalid account`. Functions marked as yielding touch the database or the banking resource: call them from a thread.

### `exports.kora_core:getTaxRate(account?, action?)`

Configured tax rate for an account/action pair as a 0..1 fraction. Reads config only; it does not check whether the banking resource is running.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `account?` | string | Account name. When given and not allowed by `Config.money.tax.accounts`, the rate is 0. `nil` skips the account check. |
| `action?` | 'add'\|'remove'\|'transfer' | Operation. When given and not allowed by `tax.actions` (or not one of the three), the rate is 0. `nil` skips the action check. |

**Returns**

- **rate** — number from 0 to 1. `0` when tax is disabled, the rate is not above 0, or the pair is not taxable. Rates above 1 are returned as 1.

**Example**

```lua
local rate = exports.kora_core:getTaxRate('bank', 'transfer')
print(('bank transfers are taxed at %d%%'):format(rate * 100))
```

**Representative console output**

```text
bank transfers are taxed at 5%
```

### `exports.kora_core:calculateTax(amount, account?, action?)`

Tax that would be carved out of `amount`. Pure and safe to call from a shop UI to show a tax-inclusive breakdown. Floored, so the government never takes more than its share.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `amount` | number | Gross amount. |
| `account?` | string | Account name, as for `getTaxRate`. |
| `action?` | 'add'\|'remove'\|'transfer' | Operation, as for `getTaxRate`. |

**Returns**

- **tax** — integer, `floor(amount * rate)`. `0` when amount is not a positive number, the rate is 0, or the result rounds to 0. Does not consult the banking resource, so it can be non-zero while the money APIs would go untaxed (use `getTransactionTax` for that).

**Example**

```lua
local price = 200
local tax = exports.kora_core:calculateTax(price, 'cash', 'remove')
print(('price %d, of which tax %d'):format(price, tax))
```

**Representative console output**

```text
price 200, of which tax 10
```

### `exports.kora_core:getTaxAccount()`

Name of the banking account collected tax is deposited into.

**Parameters**



**Returns**

- **account** — string, `Config.money.tax.account` (default `government`).
- **nil** — when `Config.money.tax.enabled` is false.

**Example**

```lua
local account = exports.kora_core:getTaxAccount()
if account then print(('tax goes to %s'):format(account)) end
```

**Representative console output**

```text
tax goes to government
```

### `exports.kora_core:collectTax(amount, reason?)`

Deposits `amount` into the government banking account, creating the account through the provider on first use. Yields: the provider export writes to the database, so call it from a thread. The money APIs already do this internally; call it directly only for custom taxes. It does not take money from anyone.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `amount` | number | Positive amount to deposit. |
| `reason?` | string | Passed to the provider. Defaults to `tax`. |

**Returns**

- **true** — deposited. Also fires the local event `kora_core:server:taxCollected(account, amount, reason)`.
- **false, 'transaction tax is disabled'** — `Config.money.tax.enabled` is false.
- **false, 'amount must be positive'** — not a number or not above 0.
- **false, 'no banking provider configured'** — `tax.provider` is empty or not a string.
- **false, 'banking provider &lt;resource> is not running'** — the provider is not started.
- **false, 'banking account &lt;account> does not exist'** — account missing and `autoCreateAccount` is `false`.
- **false, 'could not create banking account &lt;account>'** — the provider create export failed or returned falsy.
- **false, 'banking provider &lt;resource> rejected the tax deposit'** — the add export errored or returned falsy. The cached "account exists" marker is cleared so the next call re-checks.

**Example**

```lua
CreateThread(function()
    local ok, err = exports.kora_core:collectTax(150, 'impound-fee')
    if not ok then print(('tax not collected: %s'):format(err)) end
end)
```

**Representative console output**

```text
tax not collected: banking provider qb-banking is not running
```

### `exports.kora_core:getTransactionTax(amount, account, action)`

Preview of the tax the money APIs would actually apply right now. Unlike `calculateTax` it returns 0 when the banking provider is not started, matching the untaxed outage behaviour. Has no `ignoreTax` parameter.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `amount` | number | Gross amount. |
| `account` | string | Account name. |
| `action` | 'add'\|'remove'\|'transfer' | Operation. |

**Returns**

- **tax** — integer to be withheld, or `0` when tax is off, not applicable or the provider is unavailable (the unavailable case also prints the rate-limited warning).

**Example**

```lua
local tax = exports.kora_core:getTransactionTax(price, 'cash', 'remove')
TriggerClientEvent('shop:showTotal', src, price, tax)
```

**Representative console output**

```text
tax = 10 (or 0 while qb-banking is stopped)
```

### `exports.kora_core:syncState(src)`

Publishes the authoritative balance of every account in `Config.money.types` to the replicated state bag `Player(src).state['kora_core:money:<account>']`. Call it when a player loads or a HUD needs a refresh. Physical accounts are read from the provider, never from the ledger.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |

**Returns**

- **nil** — no return value. An account whose balance cannot be resolved (`getMoney` returned nil) is skipped.

**Example**

```lua
AddEventHandler('kora_core:server:playerLoaded', function(src)
    exports.kora_core:syncState(src)
end)
```

**Representative console output**

```text
Player(src).state['kora_core:money:cash'] == 500, ['kora_core:money:bank'] == 5000, ['kora_core:money:crypto'] == 0
```

### `exports.kora_core:registerPhysicalCash(account)`

Declares the calling inventory resource the authority for a physical money account. Resource-restricted: only the resource named by `Config.inventory.provider` may call it. Preflights and migrates every online player's legacy ledger balance into the provider as an item stack.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `account` | string | Account to make physical. Must equal `Config.money.cashType`. |

**Returns**

- **true** — registered, balances imported, mirror refreshed.
- **false, 'only the configured inventory provider may register physical cash'** — caller is not `Config.inventory.provider` (or has no invoking resource).
- **false, 'only the configured cash account may be physical'** — invalid account or not `cashType`.
- **false, 'physical cash provider already registered'** — another resource holds it.
- **false, 'cash account cannot be negative'** — an online player has a negative ledger balance.
- **false, &lt;provider error> or 'could not reserve space for legacy cash'** — the provider `physicalCashCanImport` call failed or refused (full inventory).
- **false, &lt;error> or 'physical cash import failed'** — import failed after activation (should be unreachable after preflight). The provider marker is kept so cash operations fail closed, and the failure is printed.

**Example**

```lua
-- inside kora_inventory (the configured provider), server side
CreateThread(function()
    local ok, err = exports.kora_core:registerPhysicalCash('cash')
    if not ok then print(('physical cash registration failed: %s'):format(err)) end
end)
```

**Representative console output**

```text
physical cash registration failed: only the configured inventory provider may register physical cash   (when called from any other resource)
```

### `exports.kora_core:unregisterPhysicalCash(account)`

Releases physical-cash authority. Resource-restricted: only the resource that registered the account may release it. Hands the legacy view and the client mirror back to the ledger value.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `account` | string | Account to release. |

**Returns**

- **true** — released.
- **false, 'physical cash provider mismatch'** — the account is not physical or was registered by another resource.

**Example**

```lua
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    exports.kora_core:unregisterPhysicalCash('cash')
end)
```

**Representative console output**

```text
true
```

### `exports.kora_core:isPhysicalCash(account)`

Whether an account is currently owned by an inventory provider.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `account` | string | Account name. |

**Returns**

- **true** — a provider is registered for it (even if that provider is currently stopped).
- **false** — otherwise.

**Example**

```lua
if exports.kora_core:isPhysicalCash('cash') then
    print('cash is an item; do not edit PlayerData.money.cash')
end
```

**Representative console output**

```text
cash is an item; do not edit PlayerData.money.cash
```

### `exports.kora_core:migratePhysicalCash(src)`

Converts one player's legacy ledger balance into the provider item stack, once: the ledger is set to 0 only after the provider accepted the matching stack. A no-op returning `true` when no account is physical or the ledger is already 0. Core calls it during provider activation and before a newly loaded player's first snapshot; resources rarely need it.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |

**Returns**

- **true** — nothing to migrate, or migration completed.
- **false, 'no such player'** — src is not loaded.
- **false, 'physical cash provider unavailable'** — the registered provider is not started.
- **false, 'cash account cannot be negative'** — negative ledger balance.
- **false, &lt;provider error> or 'could not import legacy cash'** — provider `physicalCashImport` failed or returned falsy (e.g. full inventory).
- **false, &lt;reason>** — the ledger zeroing write failed (for example `player data is busy`).

**Example**

```lua
local ok, err = exports.kora_core:migratePhysicalCash(src)
if not ok then DropPlayer(src, ('Could not load your cash: %s'):format(err)) end
```

**Representative console output**

```text
true
```

### `exports.kora_core:getMoney(src, account)`

Reads a balance. For a physical account it queries the provider (`physicalCashGet`); otherwise it reads the live PlayerData ledger. There is no account validation on this path: an unknown account name returns `nil`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `account` | string | Account name. |

**Returns**

- **balance** — number.
- **nil** — player not loaded, account unknown, or the physical provider call failed.
- **nil, 'physical cash provider unavailable'** — the registered physical-cash provider is not started.

**Example**

```lua
local cash = exports.kora_core:getMoney(src, 'cash')
if not cash or cash < price then return end
```

**Representative console output**

```text
500
```

### `exports.kora_core:addOfflineMoney(citizenid, account, amount)`

Credits a stored character who is not online with a single atomic SQL update (`JSON_SET` with `COALESCE(JSON_EXTRACT(...), 0) + amount`). Yields (database). Untaxed, fires no money events, and writes the ledger column only. If `account` is a physical-cash account the credit lands in the ledger; the code migrates a non-zero ledger into the item stack when that player next loads.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `citizenid` | string | Citizen id of the offline character. |
| `account` | string | Account in `Config.money.types`. |
| `amount` | number | Positive finite amount (fractions are accepted). |

**Returns**

- **true** — credited.
- **false, 'invalid citizenid'** — not a non-empty string.
- **false, 'invalid account'** — not in `Config.money.types`.
- **false** — second return value is the reason: 'amount must be positive and finite'.
- **false, 'player is online'** — use `addMoney` instead.
- **false, 'player data is busy'** — a column operation or offline write is in progress for that citizen.
- **false, &lt;reason>** — persistence reports the player columns unavailable.
- **false, 'offline money provider failed'** — the SQL call raised.
- **false, &lt;sql error> or 'player not found'** — no matching undeleted `players` row.

**Example**

```lua
CreateThread(function()
    local ok, err = exports.kora_core:addOfflineMoney('AB12CD34', 'bank', 2500)
    if not ok then print(('offline payout failed: %s'):format(err)) end
end)
```

**Representative console output**

```text
offline payout failed: player is online
```

### `exports.kora_core:addMoney(src, account, amount, reason?, ignoreTax?)`

Adds a positive amount. `amount` is gross: when the transaction tax applies, the player receives `amount - tax` and the tax is banked in a separate thread. Emits the money-change side effects with the net amount.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `account` | string | Account in `Config.money.types`. |
| `amount` | number | Gross positive amount. Must be a whole number for a physical account. |
| `reason?` | string | Free text passed to events and the physical-cash provider. |
| `ignoreTax?` | boolean | When true, this call is exempt from the transaction tax. |

**Returns**

- **true** — added (also `true` when a 100% tax nets the player 0; no events are fired in that case).
- **false** — second return value is the reason: 'invalid account'.
- **false, 'amount must be positive'** — not a number or not above 0.
- **false, 'physical cash provider unavailable'** — the physical provider is not started.
- **false** — second return value is the reason: 'physical cash amount must be whole'.
- **false, 'physical cash provider failed'** — the provider export raised.
- **false, &lt;provider error>** — the provider refused (for example no room); may be nil if the provider gave no reason.
- **false** — second return value is the reason: 'no such player'.
- **false, &lt;setPath reason>** — e.g. 'player logout is in progress', 'player data is busy'.

**Example**

```lua
-- 5% tax enabled: player receives 475, 25 goes to the government account
local ok, err = exports.kora_core:addMoney(src, 'cash', 500, 'job-reward')
if not ok then print(('addMoney failed: %s'):format(err)) end
```

**Representative console output**

```text
true  -- cash +475, QBCore:Server:OnMoneyChange(src, 'cash', 475, 'add', 'job-reward')
```

### `exports.kora_core:removeMoney(src, account, amount, reason?, ignoreTax?)`

Removes a positive amount. The player always pays exactly `amount`; with the tax on, its slice is banked instead of destroyed. The balance may not drop below the account floor: 0, or `Config.money.minusLimit` for accounts in `allowNegative` (default `bank`, -50000).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `account` | string | Account in `Config.money.types`. |
| `amount` | number | Positive amount. Must be whole for a physical account. |
| `reason?` | string | Free text passed to events and the physical-cash provider. |
| `ignoreTax?` | boolean | When true, this call is exempt from the transaction tax. |

**Returns**

- **true** — removed.
- **false** — second return value is the reason: 'invalid account'.
- **false** — second return value is the reason: 'amount must be positive'.
- **false** — second return value is the reason: 'physical cash provider unavailable'.
- **false** — second return value is the reason: 'physical cash amount must be whole'.
- **false** — second return value is the reason: 'physical cash provider failed'.
- **false, &lt;provider error>** — e.g. the provider has too little cash; may be nil.
- **false** — second return value is the reason: 'no such player'.
- **false, 'insufficient funds'** — the result would be below the account floor.
- **false, &lt;setPath reason>** — e.g. 'player data is busy'.

**Example**

```lua
local ok, err = exports.kora_core:removeMoney(src, 'cash', price, 'shop-purchase')
if not ok then
    return TriggerClientEvent('QBCore:Notify', src, err == 'insufficient funds' and 'Not enough cash' or 'Payment failed', 'error')
end
```

**Representative console output**

```text
true  -- or false, 'insufficient funds'
```

### `exports.kora_core:setMoney(src, account, amount, reason?)`

Sets an exact balance. Never taxed (an absolute assignment for admin edits, resets and migrations) and so has no `ignoreTax` parameter. Negative values are allowed only down to the account floor.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `account` | string | Account in `Config.money.types`. |
| `amount` | number | New balance. Whole and not negative for a physical account. |
| `reason?` | string | Free text passed to events and the provider. |

**Returns**

- **true** — set. The emitted `amount` is the new balance on a normal account, or the absolute difference on a physical account.
- **false** — second return value is the reason: 'invalid account'.
- **false** — second return value is the reason: 'amount must be a number'.
- **false** — second return value is the reason: 'physical cash provider unavailable'.
- **false** — second return value is the reason: 'physical cash amount must be whole' (physical account).
- **false, 'below account floor'** — negative on a physical account, or below `floorFor(account)` (0, or `minusLimit` for `allowNegative` accounts).
- **false, 'physical cash balance unavailable'** — the provider could not report the current balance.
- **false** — second return value is the reason: 'physical cash provider failed'.
- **false, &lt;provider error>** — the provider refused the set.
- **false** — second return value is the reason: 'no such player'.
- **false** — second return value is the reason: &lt;setPath reason>.

**Example**

```lua
local ok, err = exports.kora_core:setMoney(target, 'bank', 0, 'admin-reset')
if not ok then print(('reset failed: %s'):format(err)) end
```

**Representative console output**

```text
true
```

### `exports.kora_core:transferMoney(fromSrc, toSrc, account, amount, reason?, ignoreTax?)`

Moves money between two online players: remove from the sender, then add to the recipient. With the tax on the sender pays `amount` and the recipient receives `amount - tax`. Both legs run exempt internally because the tax is settled once for the whole transfer. If the recipient add fails the sender is refunded the full amount (reason `transfer-refund`). Not atomic across a crash. Both players are locked against concurrent persistence column operations for the duration.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `fromSrc` | integer | Sender server id. |
| `toSrc` | integer | Recipient server id. There is no check that it differs from `fromSrc`. |
| `account` | string | Account in `Config.money.types`. |
| `amount` | number | Gross positive amount. Whole for a physical account. |
| `reason?` | string | Free text passed to events and the provider. |
| `ignoreTax?` | boolean | When true, the transfer is untaxed. |

**Returns**

- **true** — transferred. Sender gets an `OnMoneyChange` `remove` event (gross) and the recipient an `add` event (net).
- **false, 'no such player'** — either source is not loaded.
- **false, 'player data is busy'** — one of the characters is already in a persistence column operation or transfer.
- **false, 'invalid transfer'** — invalid account, or amount not a positive number.
- **false** — second return value is the reason: 'physical cash provider unavailable'.
- **false** — second return value is the reason: 'physical cash amount must be whole' (physical account).
- **false** — second return value is the reason: 'physical cash provider failed', or the provider's own error.
- **false, &lt;removeMoney reason>** — e.g. 'insufficient funds'.
- **false, &lt;addMoney reason>** — recipient add failed; the sender has been refunded.

**Example**

```lua
local ok, err = exports.kora_core:transferMoney(src, targetSrc, 'bank', 1000, 'player-transfer')
if not ok then
    TriggerClientEvent('QBCore:Notify', src, err, 'error')
end
```

**Representative console output**

```text
true  -- sender bank -1000, recipient bank +950 with a 5% tax, 50 to the government account
```

### `exports.kora_core:transaction(src, transaction)`

Applies a combined money and item change to one player as a unit: validates every leg first, applies them in a fixed order, and rolls back on failure. Exported under the bare name `transaction`. Money legs are never taxed.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `transaction` | table | Input table, see the shape below. Missing `money`/`items` sections are treated as empty. |

**Returns**

- **true** — all legs applied.
- **false** — second return value is the reason: 'transaction must be a table'.
- **false** — second return value is the reason: 'random must be a table'.
- **false, 'invalid random item entry'** — an entry is not a table with a string `item`.
- **false, 'random item amount must be a positive whole number or an integer range'** — `amount` must be a positive integer, or `{ min, max }` integers with min above 0 and max not below min.
- **false, &lt;message>** — `Kora.rewards.generate` raised (for example a non-dense array or `chance` above 100).
- **false, 'invalid item entry'** — an `items.add`/`items.remove` entry is not a table with a string `item`.
- **false** — second return value is the reason: 'item amount must be a positive whole number'.
- **false, 'invalid money entry'** — entry without a string `account` or a positive whole `amount`.
- **false, 'insufficient funds'** — a `money.remove` account balance is below that entry (or the balance cannot be read).
- **false, 'invalid account'** — a `money.add` account cannot be read for this player.
- **false, 'not enough of item: &lt;item>'** — the player holds fewer than the aggregated remove count.
- **false, &lt;canCarry reason>** — e.g. 'no such player', 'unknown item', 'over weight', 'no free slot' from `Core.inventory.canCarry`.
- **false, &lt;leg reason>** — a leg failed while applying (balance or inventory changed since validation). Everything applied so far has been rolled back with reason `transaction rollback`.

**Example**

```lua
local ok, err = exports.kora_core:transaction(src, {
    reason = 'craft-bandage',
    money = { remove = { { account = 'cash', amount = 20 } } },
    items = {
        remove = { { item = 'cloth', amount = 2 } },
        add = { { item = 'bandage', amount = 1 } },
    },
    random = { { item = 'lollipop', amount = 1, chance = 25 } },
})
if not ok then
    TriggerClientEvent('QBCore:Notify', src, ('Crafting failed: %s'):format(err), 'error')
end
```

**Representative console output**

```text
true  -- or false, 'not enough of item: cloth'
```

## Common use cases

- Shop checkout: take cash and add the purchased items with `transaction`, so a full inventory never costs the player money.
- Paying a player from a job script with `addMoney(src, 'cash', amount, 'reason')` and letting the optional tax divert a share to the government.
- Showing a tax-inclusive price in a UI with `getTransactionTax` before charging.
- Crediting a payout to a character who is offline with `addOfflineMoney`.
- Reading `Player(src).state['kora_core:money:cash']` in a HUD instead of polling `getMoney`.

## Limits and related APIs

Money functions are not atomic with the database: balances persist on the normal save cycle (`Config.persistence.interval`), and `transaction` rollback is best-effort with ignored results. The rollback re-adds removed items with the `info` carried on the remove entry, not the info of the stack that was actually taken. A deposit to the government account can fail after the player has already been charged. `transferMoney` does not reject `fromSrc == toSrc`. `getMoney` does not validate the account name.

## Related guides

- [Player data and the setPath funnel](./player.md)
- [Inventory provider and physical cash](./inventory.md)
- [Persistence and offline writes](./persistence.md)
- [Paycheck uses addMoney](./jobs.md)
- [Money events](./events.md)
- [Config.money and Config.inventory](./configuration.md)

## Implementation notes and quick reference

Accounts are the names in `Config.money.types` (default `cash`, `bank`, `crypto`).
Balances live in `PlayerData.money` and change only through the money API, which
writes through the player funnel and emits the legacy money events. All functions
are server-side.

### API

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

#### Side effects of every balance change

- Server event `QBCore:Server:OnMoneyChange(src, account, amount, action, reason)`
- Client events `QBCore:Client:OnMoneyChange(account, amount, action, reason)` and
  `hud:client:OnMoneyChange(account, amount, isRemove)`
- `qb-phone:client:RemoveBankMoney(amount)` for bank removals
- Replicated player state bag `kora_core:money:<account>` with the new balance
  (also published for every account at login)

`amount` in these events is the net amount actually moved. For `setMoney` the
action is `set`; on the normal ledger the amount is the new balance, and on a
physical-cash account it is the absolute difference.

### Transaction tax

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

### Physical cash

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

### Transactions

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

### Paychecks

See [Jobs and gangs](./jobs.md#paychecks). Paychecks are credited to
`Config.money.cashType` with reason `paycheck` and are subject to the tax.
