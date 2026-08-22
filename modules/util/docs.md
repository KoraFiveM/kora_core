# Util module

## Overview
The `QBCore.Shared.*` primitives (rounding, trimming, splitting, random-string generation) plus the small path helpers the player funnel is built on. Shared realm — identical on client and server, no natives, no side effects, so every function is deterministic and unit-testable. All functions are defined on `Core.util` and exported flat as `exports.qbcore:<fn>`.

## API

### `Core.util.round(value, places)`
Rounds `value` to `places` decimal places (default `0`). Returns `0` for a non-number input rather than erroring.

#### Parameters
- `value: number`
- `places: integer | nil` — Decimal places to keep. Defaults to `0`.

#### Returns
- `number` — The rounded value.

#### Example
```lua
exports.qbcore:round(12.3456, 2)   -- 12.35
```

### `Core.util.trim(value)`
Strips leading and trailing whitespace. A non-string `value` is returned unchanged.

#### Parameters
- `value: string`

#### Returns
- `string`

### `Core.util.splitStr(str, delimiter)`
Splits `str` on a single-character `delimiter`. The delimiter is escaped internally, so punctuation delimiters (`.`, `-`, …) are safe.

#### Parameters
- `str: string`
- `delimiter: string` — A single character.

#### Returns
- `string[]` — The parts, in order.

#### Example
```lua
local parts = exports.qbcore:splitStr('a.b.c', '.')   -- { 'a', 'b', 'c' }
```

### `Core.util.randomStr(length)`
Returns a random uppercase-letter string of `length` characters (legacy `QBCore.Shared.RandomStr`).

#### Parameters
- `length: integer`

#### Returns
- `string`

### `Core.util.randomInt(length)`
Returns a random digit string of `length` characters. Note it returns a **string**, not a number — matching legacy `QBCore.Shared.RandomInt` behaviour.

#### Parameters
- `length: integer`

#### Returns
- `string`

### `Core.util.randomAlnum(length)`
Returns a random alphanumeric (uppercase + digits) string. This is what backs generated citizenids and stash ids.

#### Parameters
- `length: integer`

#### Returns
- `string`

### `Core.util.deepClone(t)`
Recursively copies a table (arrays and maps). Does **not** copy metatables and does **not** handle cycles. Used to hand a caller an isolated snapshot of `PlayerData` rather than a live internal reference.

#### Parameters
- `t: any` — A non-table value is returned unchanged.

#### Returns
- `any` — A deep copy of `t`.

### `Core.util.pathGet(t, path)`
Reads a nested value by an array of keys. Returns `nil` if any segment along the way is missing or not a table.

#### Parameters
- `t: table`
- `path: (string|integer)[]` — e.g. `{ 'money', 'cash' }`.

#### Returns
- `any` — The value at the path, or `nil`.

#### Example
```lua
local cash = exports.qbcore:pathGet(playerData, { 'money', 'cash' })
```

### `Core.util.pathSet(t, path, value)`
Writes `value` at a nested `path`, creating intermediate tables as needed. Returns the **previous** value at that path (so a caller can detect a no-op write).

#### Parameters
- `t: table`
- `path: (string|integer)[]`
- `value: any`

#### Returns
- `any` — The value that was at `path` before the write.

#### Example
```lua
local prev = exports.qbcore:pathSet(data, { 'metadata', 'hunger' }, 100)
```

## Notes
- `randomInt` returns a string, not a number — a legacy quirk kept for drop-in compatibility.
- `deepClone` has no cycle protection; only use it on tree-shaped data (which `PlayerData` is).
- `pathGet`/`pathSet` are the read/write primitives the player funnel (`Core.player.setPath`) is built on — the same key-array path shape flows through replication, subscriptions, and dirty tracking.
