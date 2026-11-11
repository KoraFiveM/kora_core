---
title: Permissions, commands and logging
sidebar_position: 9
---

# Permissions, commands and logging

## Permission levels

kora_core maps the legacy levels `god`, `admin`, `mod` and `user` onto FiveM ACE
objects through kora_lib's permission helpers. Grant them in `server.cfg`:

```cfg
add_principal identifier.license:xxxxxxxx kora_core.admin
add_ace group.admin kora_core.admin allow
```

| Export | Returns | Description |
| --- | --- | --- |
| `getPermission(src)` | string | First of `god`, `admin`, `mod` that the player holds through `kora_core.<level>` or `group.<level>`; otherwise `user`. |
| `hasPermission(src, permission)` | boolean | `user` is always true. Otherwise any of the ACE objects `kora_core.<permission>`, `group.<permission>` or `command.<permission>`. |
| `addPermission(src, permission)` | boolean | Runs `add_principal identifier.<kind>:<id> kora_core.<permission>` for the player's primary identifier. Session-only, not saved. |
| `removePermission(src, permission)` | boolean | Runs the matching `remove_principal`. |
| `isOptin(src)` | boolean | `true` for players above `user` unless their PlayerData `optin` is `false`. |

The level check is name-based: `hasPermission(src, 'mod')` does not imply that an
`admin` holder passes unless the ACE configuration grants `kora_core.mod` too.

## Registering commands

`addCommand` wraps kora_lib's command registry:

```lua
exports.kora_core:addCommand('heal', 'Heal a player', {
    { name = 'id', help = 'Server ID' },
}, true, function(source, args, raw)
    -- source is 0 for the server console
end, 'admin')
```

| Export | Description |
| --- | --- |
| `addCommand(name, help, args, argsRequired, handler, permission)` | Registers the command. `permission` defaults to `user`; other values are checked with `hasPermission` (the console always passes). With `argsRequired`, fewer arguments than `#args` are refused. Denials and missing arguments are reported with `QBCore:Notify`. Handlers run under `pcall`. A chat suggestion is broadcast. |
| `removeCommand(name)` | Removes the command and its chat suggestion. |
| `refreshCommands(src)` | Re-sends chat suggestions to one player. |
| `listCommands()` | Array of `name`, `help`, `permission`. |

Commands are owner-tracked: when the registering resource stops, the handler is
dropped and `chat:removeSuggestion` is broadcast.

Legacy `QBCore.Commands.Add` goes through the same registry and additionally runs
`add_ace kora_core.<level> command.<name> allow` for non-`god`/`user` levels and
fires `QBCore:Server:PreCommandExecution`. See [Compatibility](../compatibility.md#commands).

All commands that kora_core registers itself are listed on the
[Commands](../commands.md) page.

## Logging

| Export | Description |
| --- | --- |
| `logEvent(category, src, data)` | Records an event through `Kora.logging.event`: in-memory ring buffer, per-category counter and an optional Discord webhook. `src` is the acting player (0 for the system). |
| `getLogStats()` | `counts` per category and `ringSize`. |

```lua
exports.kora_core:logEvent('money', source, { account = 'bank', amount = 500, reason = 'paycheck' })
```

The webhook URL is read by kora_lib from the `kora_lib_log_webhook` convar, with
`kora_core_log_webhook` as a fallback. kora_core itself logs default admin command
use under `admin` and vehicle-spawn callback use under `vehicle`. The legacy
server event `qb-log:server:CreateLog` (local only) is forwarded to `logEvent`.
