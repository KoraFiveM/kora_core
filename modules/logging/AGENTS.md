# logging module guide

## Purpose
A minimal server-side event log: a fixed-size in-memory ring buffer, cumulative per-category counters, and an optional fire-and-forget Discord webhook. Loaded last among modules so it can observe events the others emit.

## Public API
- `Core.logging.event(category, src, data)` — record an event (ring + counter + optional webhook).
- `Core.logging.getStats()` — `{ counts = {category=n}, ringSize = n }`.

## Implementation notes
- **Fixed 500-entry ring.** `RING = 500`; while under capacity it appends, then wraps using `head` as the write cursor (`ring[head+1] = entry; head = (head+1) % RING`). It's a live tail for diagnostics, not durable audit storage — old events are overwritten and nothing is persisted to the DB.
- **Cumulative counters.** `counts[category]` only ever increments over the session; `getStats` surfaces them (plus `#ring`) for HUDs/tooling.
- **Webhook is convar-gated and non-blocking.** Only fires when `GetConvar('kora_core_log_webhook', '')` is non-empty; `PerformHttpRequest` is called with an empty callback so the caller never waits on the network.
- **Deliberately not wired into every module.** It exposes `event` for callers to log through; it does not auto-subscribe to money/job/etc. changes. Keeping it decoupled is intentional — a server can log exactly what it wants.
- **No `CoreInternal.logging` table.** `RING`/`ring`/`head`/`counts` are file-local; both functions are public. Internals elsewhere use `CoreInternal.<module>`; `build/finalise.lua` walks only `Core.<module>` and skips `_`-prefixed functions.

## Best practices
- Namespace `category` consistently (`'money'`, `'job'`, `'admin'`, …) so `getStats` counters and any webhook filtering stay meaningful.
- Treat the ring as a short live tail; if you need durable audit history, log to your own table/webhook in addition.
