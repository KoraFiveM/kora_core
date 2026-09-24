# Player transactions

Use `exports.qbcore:transaction(source, definition)` for a validated sequence
of money and inventory changes. It checks balances, item quantities, and carry
capacity before applying changes, then attempts rollback if a later operation
fails. `reason`, item `slot`/`info`, and `coords` are accepted as metadata.
