# Player transactions

Use `exports.kora_core:transaction(source, definition)` for a validated sequence
of money and inventory changes. It checks every balance, item quantity, and
destination capacity before mutation. Item entries use `item`, `amount`, and
optional `slot`/`info`; money entries use `account` and `amount`.

Add an optional `random` list for bonus items. Each entry uses `item`, optional
`chance`, optional `amount`, and optional `slot`/`info`:

```lua
exports.kora_core:transaction(source, {
    reason = 'taxi payout',
    money = { add = { { account = 'bank', amount = 250 } } },
    random = {
        { item = 'water_bottle' },
        { item = 'bread' },
        { item = 'cryptostick', chance = 1 }
    }
})
```

The pool is rolled once with `Kora.rewards.generate` in percent mode, allowing
an empty result. Each item's `chance` is an independent percentage in `(0, 100]`.
Entries without a chance split 100% equally among themselves; explicit chances
do not reduce that share. In this example, water and bread each have a 50%
chance and the cryptostick has a 1% chance. Zero, one, or several items can win.

Random amounts default to `1`, or use a positive whole number or
`{ min = 1, max = 3 }` with positive integer bounds. Missing or empty `random`
lists leave ordinary transaction behavior unchanged. Malformed reward pools
return `false, error` before mutation. The definition is not modified.

Winning bonuses are combined with `items.add` for quantity and capacity checks
and use the same grant and rollback path. If a winning bonus cannot be delivered,
the whole transaction fails; an all-miss roll still allows the normal payout.

The mutation order is remove money, remove items, add items, then add money. If
a later operation fails, kora_core attempts best-effort compensation and returns
`false, error`. `reason` and `coords` are metadata; `coords` is not used for a
distance check.

This is not crash-proof atomicity. The caller must validate authorization,
prices, ownership, permissions, and distance, and must never pass an untrusted
client-defined transaction. Concurrent calls can race and rollback can fail if
a provider or the process is unavailable.
