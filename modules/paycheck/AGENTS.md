# paycheck module guide

## Purpose
The paycheck loop legacy qb-core's own `Config.jobs.paycheckInterval` was always a stub for — `compat/server/qb-core.lua`'s `F.PaycheckInterval` reads it, but nothing in the original engine ever ticked against it. Pays every employed player once per `Config.jobs.paycheckInterval`: `job.payment` while on duty, `job.offDutyPay` (a flat number, or `false` to skip) while off duty. Server only.

## Public API
- `Core.paycheck.startPaycheck()` — starts the tick loop. No-op if already running.
- `Core.paycheck.stopPaycheck()` — stops it. The in-flight `Wait()` still runs out before the thread notices and exits (at most one tick's worth of delay).
- `Core.paycheck.isPaycheckRunning()` — `boolean`.
- (`Core.paycheck._tick()` is the tick body, underscore-prefixed so `build/finalise.lua` skips it, but directly callable — see below.)

## Implementation notes
- **Self-starts on `onResourceStart` for qbcore's own resource name**, same pattern `modules/persistence/server.lua`'s `onResourceStop` flush uses — `AddEventHandler('onResourceStart', function(resourceName) if resourceName == GetCurrentResourceName() then Core.paycheck.startPaycheck() end end)`. Not called unconditionally at file-load time (unlike `modules/consumables/server.lua`'s `register()`) because there's no cross-resource dependency to gate on, and a bare top-level call would leave `isPaycheckRunning()` already `true` the moment the module loads — including under the plain-Lua test harness, where nothing ever fires `onResourceStart` unless a test explicitly triggers it.
- **Grouped by job, not scanned per player.** `_tick` first buckets online players by `job.name`, then calls `Core.jobs.getPlayersByJob(jobName, true)` once per distinct job currently held by any online player (not once per player) to build the on-duty set.
- **`_tick` is reachable without the loop.** Underscore-prefixed so `build/finalise.lua` never exports it, while staying directly callable from a test — same "internal but testable" convention `Core.persistence._insertNew`/`_load` already use. The plain-Lua mock harness's `Wait()` never yields, so resuming the `CreateThread` loop even once would infinite-loop the test process; tests call `_tick()` directly instead.
- **Generation counter guards stop/restart races.** `stopPaycheck` bumps `threadGeneration` so a stale in-flight `Wait()` from a stopped loop notices `threadGeneration ~= myGeneration` and exits instead of ticking again.
- **Tick body is `pcall`-guarded**; a thrown error in one tick is printed and does not kill the loop.

## Best practices
- Don't call `Core.paycheck._tick()` directly outside a test — it bypasses the running/generation guards `startPaycheck`'s loop relies on.
- If you need to change `paycheckInterval` at runtime, `stopPaycheck()` then `startPaycheck()` — the interval is read fresh from `Config.jobs.paycheckInterval` each time the loop starts.
