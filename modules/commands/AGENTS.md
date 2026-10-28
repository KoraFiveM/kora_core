# commands module guide

## Purpose
A permission-gated, chat-suggesting wrapper over `RegisterCommand`, with owner-tracked cleanup so command handlers don't outlive the resource that registered them. Server owns registration; the client file is intentionally empty.

## Public API
- `Core.commands.add(name, help, args, argsRequired, handler, permission)` — register (default permission `'user'`).
- `Core.commands.remove(name)` — deregister + withdraw the suggestion.
- `Core.commands.refresh(src)` — resend all suggestions to one source.
- `Core.commands.list()` — `{ name, help, permission }` entries.

## Implementation notes
- **Owner-tracked auto-sweep via `QB.resources.serverRegistry`.** Each command records its invoking `resource`; the sweep callback removes every command owned by a stopping resource and broadcasts `chat:removeSuggestion` for each. Legacy qb-core leaves the underlying `RegisterCommand` handler live after a resource restart (FiveM has no deregister), causing "ghost" commands and double-handling — the ownership map + sweep is the fix. (The FiveM handler itself can't be unregistered, but the wrapper's dispatch checks `commands[name]` first and returns early when the entry is gone, so a swept command is inert.)
- **Permission gating through `Core.permissions.hasPermission`.** Console (`source == 0`) always passes; a non-`user` permission is enforced for players, honouring `kora_core.`/`group.`/`command.` aces. A refusal notifies via `QBCore:Notify`.
- **Arg-count gating.** With `argsRequired` and an `args` spec, the wrapper refuses (notify) when `#rawArgs < #def.args` before calling the handler.
- **Handlers are `pcall`-guarded** so a throwing command logs rather than erroring out of the command dispatch.
- **Chat suggestions.** `add` broadcasts `chat:addSuggestion` to all clients; `refresh` targets one source (for (re)connects); `remove`/the sweep broadcast `chat:removeSuggestion`.
- **Client file is a deliberate stub.** There is no client-side command registration API today; `client.lua` defines no functions and exists for symmetry and as a clear place to add them.
- **Internals.** The `commands` table and `cmdRegistry` are file-local; no `CoreInternal.commands` table. Internals elsewhere use `CoreInternal.<module>`; `build/finalise.lua` walks only `Core.<module>` and skips `_`-prefixed functions.

## Best practices
- Register through `Core.commands.add` rather than raw `RegisterCommand`, so you get permission gating, suggestions, and automatic cleanup on resource stop.
- Give real `args` specs — they drive both the arg-count gate and the chat autocomplete.
