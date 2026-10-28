# Logging module

## Overview
A lightweight, ring-buffered event log with an optional Discord webhook and aggregate per-category counters. Deliberately small; loaded last among the modules so it can observe the others. Server only. Functions are defined on `Core.logging` and exported flat as `exports.kora_core:<fn>`.

## API

### `Core.logging.event(category, src, data)`
Records a gameplay/admin event into the in-memory ring buffer, bumps the category counter, and — if the `qbcore_log_webhook` convar is set — fires a fire-and-forget Discord webhook.

#### Parameters
- `category: string` — Groups events, e.g. `'money'`, `'job'`, `'admin'`.
- `src: integer` — The acting player (`0` for system).
- `data: table | nil` — Arbitrary structured detail.

#### Example
```lua
exports.kora_core:event('money', src, { account = 'bank', amount = 500, reason = 'paycheck' })
```

### `Core.logging.getStats()`
Returns aggregate counters and the current ring size.

#### Returns
- `table` — `{ counts = { [category] = n }, ringSize = n }`.

## Notes
- **Ring buffer.** The last 500 events are kept in memory (a fixed-size ring). Older events are overwritten — this is a live tail for diagnostics, not durable audit storage.
- **Optional webhook.** The Discord webhook fires only when the `qbcore_log_webhook` convar is non-empty, and is fire-and-forget (an empty callback), so it never blocks the caller.
- **Counters are cumulative** for the server session; `getStats` exposes them for tooling/HUDs.
