# Transaction module

Keep transactions server-side and validate every money and inventory leg before
mutating player state. This is a compensating transaction, not a database
atomic operation; callers remain responsible for authorization and business
rules.
