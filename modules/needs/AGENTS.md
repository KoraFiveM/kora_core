# needs module guide

## Purpose
Hunger/thirst decay — the one piece of legacy qb-core behavior (hunger/thirst ticking down over time) nothing else in this engine reimplements. The server owns the interval and metadata changes; the client reacts to replicated zero-value updates with ped damage. Stress is deliberately NOT auto-decayed here — there's no generic "stress should go down over time" rule the way there is for hunger/thirst; job resources push stress increases/decreases directly via `Core.metadata.incrementMetaData`.

## Public API
- `Core.needs.startNeedsDecay()` — starts the decay loop. No-op if already running.
- `Core.needs.stopNeedsDecay()` — stops it.
- `Core.needs.reset(src)` — sets hunger/thirst to 100 and stress to 0 for one player.
- (`Core.needs._tick()` is the tick body, underscore-prefixed — see [[paycheck]]'s identical convention.)

## Implementation notes
- **Self-starts on `onResourceStart` for kora_core's own resource name**, same pattern as [[paycheck]] — see that module's AGENTS.md for why this isn't a bare top-level call.
- **`_tick` decrements every online player's `hunger`/`thirst`** by `Config.needs.hungerDecay`/`Config.needs.thirstDecay`, clamped `[0, 100]`, via `Core.metadata.incrementMetaData`.
- **Development mode suppresses the system per player.** `_tick` skips sources for which `Core.development.isDevMode(src)` is true. The client likewise ignores zero-need damage while its local mode is active; explicit metadata writes remain available to test code.
- **Client damage subscribes to hunger and thirst separately.** A replicated zero hunger update applies `Config.needs.hungerDamage`; zero thirst applies `Config.needs.thirstDamage`. Both zero therefore stacks both amounts. Native-dead, metadata-dead, and last-stand players are skipped.
- **`_tick` is directly callable outside the loop** for the same reason `Core.paycheck._tick` is — the mock test harness's `Wait()` never yields, so resuming the `CreateThread` loop even once would hang the test process.
- **Generation counter guards stop/restart races**, identical to [[paycheck]].
- **`reset` restores the legacy hunger/thirst contract** — called from a job resource's own respawn/heal flow. This module doesn't hook death itself.

## Best practices
- Don't auto-decay stress here — push stress changes directly via `Core.metadata.incrementMetaData` from whichever job resource causes them.
- Call `Core.needs.reset(src)` from a respawn/heal flow rather than hand-setting `hunger`/`thirst`/`stress` metadata keys individually.
