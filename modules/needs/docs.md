# Needs module

## Overview
Hunger/thirst decay over time — the one piece of legacy qb-core behavior nothing else in this engine reimplements. Server only. Functions are defined on `Core.needs` and exported flat as `exports.qbcore:<fn>`.

## API

### `Core.needs.startNeedsDecay()`
Starts the decay loop, ticking every `Config.needs.tickInterval` ms. Calling it while already running is a no-op. Also called automatically when qbcore itself finishes starting.

#### Returns
- Nothing.

### `Core.needs.stopNeedsDecay()`
Stops the loop.

#### Returns
- Nothing.

### `Core.needs.reset(src)`
Resets `hunger`/`thirst` to 100 and `stress` to 0 for one player. Mirrors legacy qb-ambulancejob's `hospital:server:resetHungerThirst`, meant to be called from a job resource's own respawn/heal flow — this module doesn't hook death itself.

#### Parameters
- `src: integer`

#### Returns
- Nothing.

#### Example
```lua
exports.qbcore:reset(src) -- e.g. on respawn
```

## Notes
- **Starts automatically.** qbcore calls `startNeedsDecay()` itself once it finishes starting — most setups never need to call it directly.
- **Stress is never auto-decayed.** Only `hunger` and `thirst` tick down, by `Config.needs.hungerDecay`/`Config.needs.thirstDecay` per tick, clamped to `[0, 100]`. Push stress changes directly via `exports.qbcore:incrementMetaData(src, 'stress', delta, 0, 100)`.
- **A tick that errors is caught and logged** (`[qbcore:needs] tick errored: ...`); it does not stop the loop.
