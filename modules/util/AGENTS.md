# util module guide

## Purpose
The `QBCore.Shared.*` primitives (`round`/`trim`/`splitStr`/`randomStr`/`randomInt`/`randomAlnum`) plus the two path helpers (`pathGet`/`pathSet`) and `deepClone` that the player funnel and persistence layer are built on. Shared realm, so client and server agree byte-for-byte.

## Public API
- `Core.util.round(value, places)` — Round to `places` decimals (default 0); non-number → `0`.
- `Core.util.trim(value)` — Strip surrounding whitespace; non-string passes through.
- `Core.util.splitStr(str, delimiter)` — Split on a single-character delimiter (delimiter is regex-escaped internally).
- `Core.util.randomStr(length)` — Random uppercase letters.
- `Core.util.randomInt(length)` — Random digits, returned as a **string** (legacy behaviour).
- `Core.util.randomAlnum(length)` — Random uppercase + digits; backs citizenids and stash ids.
- `Core.util.deepClone(t)` — Recursive table copy (no metatables, no cycles).
- `Core.util.pathGet(t, path)` — Read a nested value by a key array.
- `Core.util.pathSet(t, path, value)` — Write a nested value by a key array, creating intermediate tables; returns the previous value.

## Implementation notes
- **Deliberately tiny and deterministic.** These are the codebase's "utility" tier — no natives, no I/O, no hidden state — so `test/smoke/util.lua` can exercise them with zero mocks.
- **`randomInt` returns a string on purpose.** Legacy `QBCore.Shared.RandomInt` returns a string of digits, not a number; callers concatenate it into ids. Keeping the type identical avoids silent breakage in ported resources.
- **`pathSet` returns the previous value** so a caller can detect a no-op write cheaply. The player funnel does not currently use that return (it re-encodes and byte-compares at flush time instead), but it is part of the contract and cheap to keep.
- **`deepClone` is the export-boundary guard.** `Core.player.getPlayer`/`getPlayerData` clone through this so an external resource can never hold a live reference into the authoritative `PlayerData` and mutate it out from under the funnel.
- **No `CoreInternal.util` table.** Everything here is public; there are no private helpers to hide. For modules that do have internals, those live on `CoreInternal.<module>` and are never exported — `build/finalise.lua` walks only `Core.<module>` and additionally skips any `_`-prefixed function.

## Best practices
- Reach for `pathGet`/`pathSet` (or the funnel that wraps them) instead of hand-rolling nested-table access — the key-array path shape is what the whole framework speaks.
- Don't rely on `deepClone` for graphs with cycles or metatables; it silently produces wrong output for both.
