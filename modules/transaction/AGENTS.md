# Transaction module

Keep transactions server-side and validate every money and inventory leg before
mutating player state. This is a compensating transaction, not a database
atomic operation; callers remain responsible for authorization and business
rules.

`Core.commerce.sellItem`/`buyItem` (same file, exported flat as `sellItem`/`buyItem`)
are thin wrappers that build exactly one `Core.transaction`. Keep them that way:
validate the untrusted `amount` with `Kora.util.toAmount`, assert on programmer
errors in the spec, and never take a price from the client. `Core.transaction` is
a bare function on `Core`, which is why the wrappers live on `Core.commerce`.
