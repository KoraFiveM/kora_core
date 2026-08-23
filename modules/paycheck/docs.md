# Paycheck module

## Overview
Pays every employed player on a timer: `job.payment` while on duty, `job.offDutyPay` while off duty (skipped if `offDutyPay` is `false`). Server only. Functions are defined on `Core.paycheck` and exported flat as `exports.qbcore:<fn>`.

## API

### `Core.paycheck.startPaycheck()`
Starts the paycheck loop, ticking every `Config.jobs.paycheckInterval` ms. Calling it while already running is a no-op. Also called automatically when qbcore itself finishes starting.

#### Returns
- Nothing.

### `Core.paycheck.stopPaycheck()`
Stops the loop. The in-flight `Wait()` still runs out before the thread notices and exits — at most one tick's worth of delay.

#### Returns
- Nothing.

### `Core.paycheck.isPaycheckRunning()`
#### Returns
- `boolean`

#### Example
```lua
if not exports.qbcore:isPaycheckRunning() then
    exports.qbcore:startPaycheck()
end
```

## Notes
- **Starts automatically.** qbcore calls `startPaycheck()` itself once it finishes starting — most setups never need to call it directly.
- **On duty:** paid `job.payment` (the current grade's payment, from `Core.jobs.getJob`) if it's a number `> 0`.
- **Off duty:** paid `job.offDutyPay` from the job's registry record, only if it's a number `> 0`. `false` (the common case) means no off-duty pay.
- **One `Core.jobs.getPlayersByJob` lookup per distinct job**, not per player, to determine the on-duty set for that tick.
- **A tick that errors is caught and logged** (`[qbcore:paycheck] tick errored: ...`); it does not stop the loop.
