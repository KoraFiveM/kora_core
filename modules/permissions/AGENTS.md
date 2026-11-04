# permissions module guide

## Purpose
Map the legacy QBCore permission vocabulary (`user`/`mod`/`admin`/`god`) onto FiveM's ace system, so permission checks are real ace checks rather than a hand-rolled admin table. Server only.

## Public API
- `Core.permissions.getPermission(src)` — highest level the player satisfies (`user` floor).
- `Core.permissions.hasPermission(src, permission)` — ace check across `kora_core.`/`group.`/`command.` objects.
- `Core.permissions.addPermission(src, permission)` — runtime grant via `add_principal`.
- `Core.permissions.isOptin(src)` — "above user" convenience.

## Implementation notes
- **`LEVELS` is ordered most-privileged first** (`god`, `admin`, `mod`, `user`); `getPermission` returns the first match, so a god also passing admin still reports `god`. `user` is the unconditional floor — the loop returns `user` without an ace check.
- **Two object namespaces per level.** `getPermission` checks both `kora_core.<level>` and `group.<level>`; `hasPermission` additionally checks `command.<level>`. This lets qbcore-native aces, group-based configs, and command-grant aces all satisfy checks — which is why the commands module can gate on a permission name that's really a command ace.
- **Runtime grants target the primary identifier.** `addPermission` resolves `Core.identity.primary(src)`, strips the `kind:` prefix, and runs `add_principal identifier.<primaryIdentifier>:<value> kora_core.<permission>`. It returns `false` if the identifier can't be resolved (offline/edge case).
- **Grants are session-scoped.** `add_principal` is not written to disk here; persisting an admin roster is intentionally out of scope.
- **The legacy `QBCore.Functions.GetPermission` is a DIFFERENT shape.** Native `getPermission` returns one level string; upstream qb-core returns a set of every configured group the player holds (`{ god = true, admin = true }`) which callers index by name (`if perms['admin'] then`). The compat wrapper builds that set from `QBCore.Config.Server.Permissions`, so never point it straight at `getPermission` — legacy scripts index the result and a string silently misbehaves or errors. Same file: `QBCore.Functions.HasPermission` also accepts an array of permissions (any match passes), which the native single-string `hasPermission` asserts against.
- **No `CoreInternal.permissions` table.** `LEVELS` is file-local; all functions are public. Internals elsewhere use `CoreInternal.<module>`; `build/finalise.lua` walks only `Core.<module>` and skips `_`-prefixed functions.

## Best practices
- Gate commands and admin features on `hasPermission`, not on `getPermission == 'admin'`, so `command.`/`group.` aces are honoured.
- For durable admin, add the principal to `server.cfg`; use `addPermission` for temporary/runtime elevation.
