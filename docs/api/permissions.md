---
title: "Permissions, commands and logging"
sidebar_position: 10
---


# Permissions, commands and logging

kora_core maps the legacy kora_core levels `god`, `admin`, `mod`, `user` onto FiveM ACEs, registers commands that are gated by that model, and logs events to an in-memory ring with an optional Discord webhook. Permission, command and log mechanics live in kora_lib and run in kora_lib's Lua VM; kora_core only supplies the prefix `kora_core`, the level list and the notify function. The client has no exports for any of this.

Namespace: `exports.kora_core` · Source: `modules/permissions/server.lua, commands/server.lua, logging/server.lua (backed by kora_lib modules/permissions, commands, logging)`

## Command registration rules (kora_lib asserts)

Violations raise an error from `addCommand` rather than returning false.

| Argument | Rule | Error message |
| --- | --- | --- |
| name | String matching `^[%w_:%.%-]+$` (letters, digits, `_`, `:`, `.`, `-`; no whitespace, no leading slash) | Command name must be a non-empty command name without whitespace. |
| help | String or nil | Command help must be a string or nil. |
| args | nil or a dense array of tables, each with a non-empty string `name` and optional string `help` | Command args must be a table or nil. / Command args must be a dense array of tables. / Command argument names must be non-empty strings. / Command argument help must be a string or nil. |
| argsRequired | boolean or nil | Command argsRequired must be a boolean or nil. |
| handler | callable | Command handler must be callable. |
| permission | non-empty string (default `user`) | Command permission must be a non-empty string. |

## How it works

Argument checks use `assert`, so a bad argument raises an error at the call site instead of returning a reason string.

## Securing your own commands

1. **Pick the permission at registration** — Pass `'admin'` or `'mod'` as the last argument of `addCommand` so dispatch rejects the caller before your handler runs.
2. **Validate arguments in the handler** — The permission check only authorises the caller. Parse and range-check every argument yourself.
3. **Re-check for net events** — A command permission does not protect a net event. Check `hasPermission(source, ...)` inside any event that does the same work.
4. **Never pass player text to addPermission** — The permission string goes into a console command unescaped.

## Terms used on this page

| Term | Meaning |
| --- | --- |
| ACE objects checked | `kora_core.<level>` and `group.<level>` for ranking; `kora_core.<permission>`, `group.<permission>` and `command.<permission>` for a flat check. Objects inherit in FiveM, so a grant on a parent object such as `command` also covers `command.<anything>`. |
| Levels | `god`, `admin`, `mod`, `user`, most privileged first. `user` always matches. |
| getPermission is ranked | Returns the first level whose ACE (`kora_core.<level>` or `group.<level>`; not `command.<level>`) is allowed, else `user`. A player who holds only `kora_core.admin` is `admin`. |
| hasPermission is flat | True only if the exact permission name is allowed through one of the three objects. It does not rank: `hasPermission(src, 'mod')` is true for an admin only if your ACE config makes admin inherit mod (for example `add_principal kora_core.admin kora_core.mod`). The permission `user` is always true. |
| addPermission principal | `add_principal identifier.<primaryIdentifier>:<value> kora_core.<permission>` run through `ExecuteCommand`, where `<value>` is the primary identifier with its `prefix:` removed. It changes the live ACE state and is not written to server.cfg. The permission string is interpolated into the console command without sanitising, so never pass player-supplied text. |
| Command dispatch | Commands are registered with `RegisterCommand(name, handler, false)` (not restricted at engine level). Gating is done by kora_lib: console (source 0) and permission `user` always pass; otherwise `Core.permissions.hasPermission(src, permission)` decides. |

## Dispatch order

1. Permission: `user` passes; otherwise `hasPermission(source, permission)`. A denial (or a failing check) sends `QBCore:Notify` with `You do not have permission for this command.` type `error` to the caller and the handler does not run. If the check itself failed or errored, a `[kora_lib:commands] /<name> denied for <source>: <reason>` line is also printed. 2. Arguments: when `argsRequired` is true and `args` was given, fewer raw arguments than `#args` sends `Missing arguments for /<name>` (type error) and stops. 3. The handler runs inside `pcall`; an error prints `[kora_lib:commands] /<name> errored: <err>` and nothing is sent to the player. The handler receives `(source, args, rawCommand)`.

## Ownership and cleanup

A command is owned by the resource that called `addCommand` (the invoking resource). Re-registering a name transfers ownership and replaces the definition. When the owner stops, kora_lib removes the definition and sends `chat:removeSuggestion` to everyone. `removeCommand` through kora_core is only effective for commands kora_core itself registered, because kora_lib compares the owner with the invoking resource and sees `kora_core` for any call arriving via `exports.kora_core:removeCommand`; for a command from another resource it returns nothing and does nothing.

## Chat suggestions

Registering sends `chat:addSuggestion` for `/<name>` to all players (`-1`) with the help text and the argument names/help. Suggestions are not filtered by permission, only the dispatch is. `refreshCommands` re-sends every registered command's suggestion to one player.

## Logging

Entries go into a ring of 500 (oldest overwritten) holding `{category, source, data, at}` plus a per-category counter. There is no export to read the entries back, only `getLogStats`. If a webhook is configured the event is also posted fire-and-forget. The URL comes from ConVar `kora_lib_log_webhook`; when empty, from `kora_lib_log_webhook`, and when that is empty, from `kora_core_log_webhook`. The message is `[<category>] src=<src> <json data>`, cut to 1997 characters plus `...` when over 2000. `allowed_mentions.parse` is empty so `@everyone` in data cannot ping. The webhook username is the invoking resource as seen by kora_lib, which is `kora_core` for events logged through this export. A JSON encode failure prints `[kora_lib:logging] webhook payload for "<category>" could not be encoded: ...` and skips the post; the ring and counters are already updated.

## Functions

Server only. `src` is a connected player's server id unless stated otherwise.

### `exports.kora_core:getPermission(src)`

Highest kora_core level the player holds.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Positive integer player id. Raises `Permission source must be a positive finite player server ID.` otherwise (including 0). |

**Returns**

- **level** — one of `god`, `admin`, `mod`, `user`. Always a string; `user` when nothing higher is allowed.

**Example**

```lua
local level = exports.kora_core:getPermission(src)
if level == 'user' then return end
```

**Representative console output**

```text
admin
```

### `exports.kora_core:hasPermission(src, permission)`

Flat ACE check for one permission name through `kora_core.<permission>`, `group.<permission>`, `command.<permission>`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Positive integer player id (asserted). |
| `permission` | string | Non-empty permission name (asserted: `Permission must be a non-empty string.`). |

**Returns**

- **true** — one of the three ACE objects is allowed, or `permission == 'user'`.
- **false** — none allowed. Always a real boolean.

**Example**

```lua
RegisterNetEvent('myjob:server:adminAction', function()
    local src = source
    if not exports.kora_core:hasPermission(src, 'admin') then return end
    -- ...
end)
```

**Representative console output**

```text
false
```

### `exports.kora_core:addPermission(src, permission)`

Grant a runtime permission by adding an ACE principal for the player's primary identifier. Takes effect immediately and is not persisted.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `permission` | string | Permission suffix; becomes `kora_core.<permission>`. Not validated or escaped. |

**Returns**

- **true** — the `add_principal` command was executed.
- **false** — the player has no primary identifier.

**Example**

```lua
if exports.kora_core:addPermission(targetSrc, 'mod') then
    print('granted mod')
end
```

**Representative console output**

```text
granted mod
```

### `exports.kora_core:removePermission(src, permission)`

Remove the principal that `addPermission` added.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `permission` | string | Permission suffix; becomes `kora_core.<permission>`. Not validated or escaped. |

**Returns**

- **true** — the `remove_principal` command was executed.
- **false** — the player has no primary identifier.

**Example**

```lua
exports.kora_core:removePermission(targetSrc, 'mod')
```

**Representative console output**

```text
-- true
```

### `exports.kora_core:isOptin(src)`

Whether a privileged player is opted into admin or dev features. `PlayerData.optin == false` opts out.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id (same assertions as `getPermission`). |

**Returns**

- **false** — the player's level is `user`.
- **true** — privileged and `PlayerData.optin` is not `false`, including when the player is not logged in.
- **false** — privileged but `PlayerData.optin == false`.

**Example**

```lua
if exports.kora_core:isOptin(src) then
    TriggerClientEvent('myadmin:showOverlay', src)
end
```

**Representative console output**

```text
true
```

### `exports.kora_core:addCommand(name, help, args, argsRequired, handler, permission)`

Register a chat command. The owner is the invoking resource. Failure notifications go to the player through `QBCore:Notify`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Command name without the slash; must match `^[%w_:%.%-]+$`. |
| `help` | string\|nil | Help text for chat suggestions. |
| `args?` | table | `{ {name = 'id', help = 'player id'}, ... }` for suggestions. |
| `argsRequired?` | boolean | When true and `args` is given, fewer arguments than `#args` is rejected before the handler runs. |
| `handler` | fun(source:integer, args:string[], raw:string) | Called after the permission and argument checks. |
| `permission?` | string | Default `user`. Any other value is checked with `hasPermission` (flat). |

**Returns**

- **nil** — returns nothing. Invalid arguments raise an error (see the rules table).

**Example**

```lua
exports.kora_core:addCommand('givecash', 'Give cash to a player', {
    { name = 'id', help = 'player id' },
    { name = 'amount', help = 'amount' },
}, true, function(source, args)
    local target, amount = tonumber(args[1]), tonumber(args[2])
    if not target or not amount or amount <= 0 then return end
    exports.kora_core:addMoney(target, 'cash', amount, 'admin give')
end, 'admin')
```

**Representative console output**

```text
-- /givecash 5 100 by a non-admin: "You do not have permission for this command."
```

### `exports.kora_core:removeCommand(name)`

Remove a registered command and its chat suggestion. Effective only for commands owned by kora_core itself (see Ownership and cleanup).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Command name. |

**Returns**

- **nil** — returns nothing; the kora_lib result (true if removed) is discarded.

**Example**

```lua
exports.kora_core:removeCommand('givecash')
```

**Representative console output**

```text
-- no output
```

### `exports.kora_core:refreshCommands(src)`

Re-send every registered command's chat suggestion to one player, for example on reconnect.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Positive integer player id. Raises `Command refresh source must be a positive integer player ID.` otherwise. |

**Returns**

- **nil** — returns nothing.

**Example**

```lua
AddEventHandler('playerJoining', function()
    exports.kora_core:refreshCommands(source)
end)
```

**Representative console output**

```text
-- no output
```

### `exports.kora_core:listCommands()`

List every command registered through kora_lib, sorted by name.

**Parameters**



**Returns**

- **commands** — array of `{name, help, permission, keybind}`. `keybind` is nil for commands registered through kora_core. Empty array when none.

**Example**

```lua
for _, command in ipairs(exports.kora_core:listCommands()) do
    print(command.name, command.permission)
end
```

**Representative console output**

```text
givecash   admin
```

### `exports.kora_core:logEvent(category, src, data)`

Record an event in the ring buffer and counters, and post it to the webhook if one is configured. Never blocks.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `category` | string | Non-empty, at most 64 bytes (asserted: `Log category must be a non-empty string of at most 64 bytes.`). |
| `src` | integer | Acting player id, or 0 for the system (asserted: `Log source must be zero or a positive integer player ID.`). |
| `data?` | table | Event details; must be a table or nil (asserted: `Log data must be a table or nil.`). |

**Returns**

- **nil** — returns nothing.

**Example**

```lua
exports.kora_core:logEvent('money', src, { action = 'give', target = targetSrc, amount = amount })
```

**Representative console output**

```text
-- webhook message: [money] src=5 {"action":"give","target":7,"amount":100}
```

### `exports.kora_core:getLogStats()`

Per-category event counters and the current ring fill.

**Parameters**



**Returns**

- **stats** — `{counts = {category = n}, ringSize = n}`; `ringSize` is the number of entries held, at most 500. Counters cover all events since kora_lib started, not only the 500 retained.

**Example**

```lua
local stats = exports.kora_core:getLogStats()
for category, count in pairs(stats.counts) do print(category, count) end
```

**Representative console output**

```text
money   12
```

## Common use cases

- Gate an admin command: `addCommand(..., 'admin')`.
- Show or hide an overlay with `getPermission` and `isOptin`.
- Audit trail: `logEvent('money', src, {...})` with a webhook ConVar in server.cfg.

## Limits and related APIs

Permission checks are not cached; each call asks the ACE layer. `hasPermission` is not a rank comparison; rely on ACE inheritance in server.cfg if you want admin to satisfy mod. The ring buffer holds 500 entries in memory and cannot be read through an export.

## Related guides

- [Player](./player.md)
- [Events](./events.md)
- [Configuration](./configuration.md)
- [System](./system.md)

## Implementation notes and quick reference

### Permission levels

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

### Registering commands

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
fires `QBCore:Server:PreCommandExecution`. See [Compatibility](./compatibility.md#commands).

All commands that kora_core registers itself are listed on the
[Commands](../commands.md) page.

### Logging

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
