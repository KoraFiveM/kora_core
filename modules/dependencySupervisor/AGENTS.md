# dependencySupervisor module guide

## Purpose
A small, config-driven, OFF-by-default supervisor that restarts a resource
when one of its dependencies restarts mid-session. It exists specifically for
legacy resources (e.g. `qb-banking`) that are kept
byte-identical for backward-compat testing and therefore cannot be edited to
re-register themselves against `qbcore`/`qbinventory`/`qbtarget`/`PolyZone`
coming back up. Since they can't self-heal, this restarts THEM instead.

## Public API
None. Purely reactive -- same shape as `modules/consumables/server.lua`'s
`onUsingItem` hook. All behavior lives in one `onResourceStart` handler.

## Implementation notes
- **Config-gated, disabled by default.** `Config.dependencySupervisor.enabled`
  must be `true` or the handler is a no-op. `Config.dependencySupervisor.map`
  is `{ [providerResourceName] = { dependentResourceName, ... } }`.
- **`GetResourceState(dependent) == 'started'` is the first-boot guard.** A
  resource that has never started (or was intentionally stopped) has state
  `'missing'`/`'stopped'`, not `'started'` -- so this naturally skips both
  "first ever boot" (nothing to recover) and "operator stopped it on
  purpose" (don't fight them).
- **Self-restart guard.** A provider is never restarted as a side effect of
  its own start, even if `map` were misconfigured to list it as its own
  dependent (`dependent ~= resourceName` check).
- **Per-resource cooldown, not per-provider.** `lastRestartAt[dependent]`
  tracks the last time WE restarted that resource, keyed on the dependent, not
  the trigger. Two different providers restarting the same dependent in quick
  succession still only produces one restart within
  `Config.dependencySupervisor.cooldownMs`.
- **Restart mechanism is the standard idiom.**
  `ExecuteCommand('restart ' .. dependent)`, the same call qbadmin's
  `/restartresource` command uses
  (`resources/qbadmin/server/commands/privileged.lua`).
- **Logs every decision** (restart issued, or skipped for cooldown) via
  `print` -- there's no dedicated log sink here; if you need it in
  `Core.logging`'s ring buffer, call `Core.logging.event('dependencySupervisor', ...)`
  from a wrapper, don't couple this module to it.

## Best practices
- Keep `map` narrow -- only list resources that are genuinely unable to
  re-register themselves. A resource that CAN recover on its own
  (`onResourceStart` re-registration) should not be in here; restarting it
  too is blast radius for no benefit.
- `cooldownMs` should comfortably exceed how long the dependent's own startup
  takes, or a slow-starting dependent can look like it needs a second restart
  before its cooldown window even matters.
- This module only ever calls `restart`, never `stop`/`start` separately, and
  never touches a resource that isn't already `'started'`.
