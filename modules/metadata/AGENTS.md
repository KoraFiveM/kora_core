# metadata module guide

## Purpose
Get/set/increment on `PlayerData.metadata` through the funnel. Server only. This is the highest-churn write path (hunger/thirst/stress ticks), so it's the clearest beneficiary of the funnel's dirty tracking + the persistence layer's byte-identical change gate.

## Public API
- `Core.metadata.getMetaData(src, key)` — value, or whole table when `key` is `nil`.
- `Core.metadata.setMetaData(src, key, value)` — write through the funnel. `(true)` / `(false, err)`.
- `Core.metadata.incrementMetaData(src, key, delta, min, max)` — numeric add with optional clamp; returns the new value or `(nil, err)`.

## Implementation notes
- **Wrappers over `Core.player.setPath(src, {'metadata', key}, value)`.** No bespoke persistence or replication — the funnel marks the `metadata` column dirty and queues a `{p={'metadata',key}, v=value}` delta.
- **Why the gates matter most here.** Status ticks fire constantly and frequently re-assert the same value. Gate 1 (dirty) would still enqueue those; Gate 2 in persistence (encoded JSON byte-compare) drops the ones that didn't change, so idle churn is free.
- **`incrementMetaData` is `tonumber`-defensive.** A missing or non-numeric current value is treated as `0`; the result is clamped to `min`/`max` when supplied, then written. It returns the post-clamp value so a caller doesn't re-read.
- **`setMetaData` requires a string key**; `getMetaData(src, nil)` returns the whole live sub-table (read-only by convention).
- **Legacy event.** `setMetaData` fires `QBCore:Server:OnMetaDataChange(src, key, value)`. `incrementMetaData` goes through the funnel but does *not* fire that event itself — call `setMetaData` if you need the legacy event on an increment.
- **No `CoreInternal.metadata` table.** All functions are public. Internals in other modules live on `CoreInternal.<module>` and are never exported; `build/finalise.lua` walks only `Core.<module>` and skips `_`-prefixed functions.

## Best practices
- Prefer `incrementMetaData` with `min`/`max` for status values so you don't hand-roll clamping (and don't re-read to get the result).
- Don't mutate the table returned by `getMetaData(src, nil)` — write through `setMetaData` so the funnel records the change.
