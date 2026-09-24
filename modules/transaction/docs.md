# Player transactions

Use `exports.qbcore:transaction(source, definition)` for a validated sequence
of money and inventory changes. It checks every balance, item quantity, and
destination capacity before mutation. Item entries use `item`, `amount`, and
optional `slot`/`info`; money entries use `account` and `amount`.

The mutation order is remove money, remove items, add items, then add money. If
a later operation fails, qbcore attempts best-effort compensation and returns
`false, error`. `reason` and `coords` are metadata; `coords` is not used for a
distance check.

This is not crash-proof atomicity. The caller must validate authorization,
prices, ownership, permissions, and distance, and must never pass an untrusted
client-defined transaction. Concurrent calls can race and rollback can fail if
a provider or the process is unavailable.
