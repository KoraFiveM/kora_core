# Metadata module

## Overview
Get / set / increment on a player's `metadata` sub-table (hunger, thirst, stress, armor, licences, and any custom keys). These are the highest-churn writes in the framework, which is exactly why they route through the funnel: the per-column dirty tracking plus the persistence layer's byte-identical gate mean a hunger tick that lands on the current value writes nothing. Server only. Functions are defined on `Core.metadata` and exported flat as `exports.qbcore:<fn>`.

## API

### `Core.metadata.getMetaData(src, key)`
Returns a metadata value, or the whole metadata table when `key` is `nil`.

#### Parameters
- `src: integer`
- `key: string | nil`

#### Returns
- `any` — The value, the whole `metadata` table (if `key` is `nil`), or `nil` if there is no such player.

#### Example
```lua
local hunger = exports.qbcore:getMetaData(src, 'hunger')
```

### `Core.metadata.setMetaData(src, key, value)`
Sets a metadata key through the funnel and fires `QBCore:Server:OnMetaDataChange`.

#### Parameters
- `src: integer`
- `key: string`
- `value: any`

#### Returns
- `boolean` — `true` on success.
- `string | nil` — Failure reason (`'no such player'`, `'metadata key must be a string'`).

#### Example
```lua
exports.qbcore:setMetaData(src, 'isdead', true)
```

### `Core.metadata.incrementMetaData(src, key, delta, min, max)`
Adds `delta` to a numeric metadata key, optionally clamping to `[min, max]`, writes it through the funnel, and returns the new value.

#### Parameters
- `src: integer`
- `key: string`
- `delta: number`
- `min: number | nil`
- `max: number | nil`

#### Returns
- `number | nil` — The new value.
- `string | nil` — Failure reason (`'no such player'`).

#### Example
```lua
local hunger = exports.qbcore:incrementMetaData(src, 'hunger', -5, 0, 100)
```

## Notes
- **Churn is absorbed by the two gates.** `setMetaData`/`incrementMetaData` mark the `metadata` column dirty via the funnel, but the persistence layer only writes it if the encoded JSON actually changed — so a tick that sets `hunger` to the value it already holds costs nothing at flush time.
- **`incrementMetaData` treats a missing/non-numeric current value as `0`** before applying `delta`, then clamps.
- **`getMetaData` with no key returns the live sub-table** (from the handle); treat it as read-only and don't mutate it — go through `setMetaData` so the funnel sees the change.
