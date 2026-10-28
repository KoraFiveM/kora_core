# Commands module

## Overview
A registration wrapper over `RegisterCommand` with permission gating and chat-suggestion support. Registered commands are **owner-tracked** — when the registering resource stops, its commands are removed and their chat suggestions withdrawn, so a resource restart doesn't leave dead handlers behind (legacy qb-core does). Server owns registration; the client file defines no functions today. Functions are defined on `Core.commands` and exported flat as `exports.kora_core:<fn>`.

## API

### `Core.commands.add(name, help, args, argsRequired, handler, permission)` — server
Registers a command. Wraps `RegisterCommand` with a permission check (via `Core.permissions.hasPermission`), an arg-count check, and a `pcall`-guarded handler, then adds a chat suggestion for all clients.

#### Parameters
- `name: string` — Command name (without the leading `/`).
- `help: string` — Description shown in chat suggestions.
- `args: table | nil` — `{ { name=, help= }, … }` for chat suggestions.
- `argsRequired: boolean | nil` — If true, the handler is skipped when fewer than `#args` are supplied.
- `handler: fun(source: integer, args: string[], raw: string)`
- `permission: string | nil` — Required permission; default `'user'`.

#### Example
```lua
exports.kora_core:add('heal', 'Heal a player', {
    { name = 'id', help = 'server id' },
}, true, function(source, args, raw)
    -- ...
end, 'admin')
```

### `Core.commands.remove(name)` — server
Removes a command and withdraws its chat suggestion from all clients.

#### Parameters
- `name: string`

### `Core.commands.refresh(src)` — server
Re-sends every registered command's chat suggestion to one source (e.g. on connect).

#### Parameters
- `src: integer`

### `Core.commands.list()` — server
Returns the registered commands as `{ name, help, permission }` entries.

#### Returns
- `table[]`

## Notes
- **Permission gating.** A command with a non-`user` permission is refused for a player who lacks it (console, `source == 0`, always passes). The check goes through `Core.permissions.hasPermission`, so `kora_core.`/`group.`/`command.` aces all count.
- **Arg-count gating.** With `argsRequired` and an `args` spec, the handler is skipped (with a notify) when the caller supplied fewer than `#args` arguments.
- **Owner-tracked auto-sweep.** Commands are tagged with the invoking resource and swept when it stops — the handler is dropped and `chat:removeSuggestion` is broadcast. This is the fix for legacy qb-core leaving orphaned command handlers after a resource restart.
- **Handlers are `pcall`-guarded** — a throwing command logs and doesn't crash the registration.
