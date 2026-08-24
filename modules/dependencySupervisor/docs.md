# Dependency supervisor module

## Overview
Restarts a resource when a dependency of that resource restarts mid-session.
Built for legacy, unmodifiable resources (e.g. `qb-banking`,
`qb-recyclejob`) that cannot re-register themselves when `qbcore`,
`qbinventory`, `qbtarget`, or `PolyZone` come back from a restart. Disabled
by default. Server only. No exported functions -- it's a single reactive
`onResourceStart` handler.

## Configuration

`Config.dependencySupervisor` in `config.lua`:

```lua
Config.dependencySupervisor = {
    enabled = false,       -- must be explicitly turned on
    map = {
        -- providerResourceName = { dependentResourceName, ... }
        qbinventory = { 'qb-banking' },
        qbtarget = { 'qb-banking', 'qb-recyclejob' },
        PolyZone = { 'qb-recyclejob' },
        qbcore = { 'qb-banking', 'qb-recyclejob' },
    },
    cooldownMs = 15000,    -- min ms between two restarts of the SAME resource
}
```

- `enabled` -- opt-in flag. Leave `false` unless you've confirmed the blast
  radius (a resource restart drops in-flight state in that resource) is
  acceptable for your server.
- `map` -- keyed by provider resource name; each value is an array of
  resource names to restart once the provider (re)starts.
- `cooldownMs` -- a dependent won't be restarted again within this many
  milliseconds of the last restart WE issued for it, regardless of which
  provider triggered it.

## Behavior

When a resource `resourceName` starts (`onResourceStart`):
1. If `Config.dependencySupervisor.enabled` is falsy, do nothing.
2. If `resourceName` is not a key in `Config.dependencySupervisor.map`, do
   nothing.
3. For each `dependent` in `map[resourceName]`:
   - Skip if `dependent == resourceName` (never restart the resource that
     just triggered this).
   - Skip if `GetResourceState(dependent) ~= 'started'` -- this is also what
     prevents restarting a dependent on the very first server boot, before
     it has ever started.
   - Skip if `dependent` was restarted by this module less than
     `cooldownMs` ago.
   - Otherwise call `ExecuteCommand('restart ' .. dependent)` and record the
     restart time.

Every restart or skip is logged with `print`.

## Notes
- Only ever issues `restart`, never separate `stop`/`start` calls.
- Only restarts resources that are already running; it never starts a
  resource that isn't up.
- Not enabled in `server.cfg` by this change -- turning it on is a per-server
  decision.
