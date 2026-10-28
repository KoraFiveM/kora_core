# Permissions module

## Overview
Thin wrappers over FiveM's ace permission system, mapping the legacy QBCore vocabulary (`user`/`mod`/`admin`/`god`) onto ace principals. Runtime grants add an ace principal for the player's primary identifier. Server only. Functions are defined on `Core.permissions` and exported flat as `exports.kora_core:<fn>`.

## API

### `Core.permissions.getPermission(src)`
Returns the player's highest permission level: the first of `god`, `admin`, `mod`, `user` they satisfy (checked against both `kora_core.<level>` and `group.<level>` ace objects). Everyone is at least `user`.

#### Parameters
- `src: integer`

#### Returns
- `string` — `'god'` | `'admin'` | `'mod'` | `'user'`.

#### Example
```lua
if exports.kora_core:getPermission(src) == 'god' then
    -- highest tier
end
```

### `Core.permissions.hasPermission(src, permission)`
Returns whether the player has a given permission. `'user'` is always true; otherwise checks `kora_core.<permission>`, `group.<permission>`, and `command.<permission>` ace objects.

#### Parameters
- `src: integer`
- `permission: string`

#### Returns
- `boolean`

### `Core.permissions.addPermission(src, permission)`
Grants a runtime permission by adding an ace principal for the player's primary identifier (`add_principal identifier.<kind>:<value> kora_core.<permission>`).

#### Parameters
- `src: integer`
- `permission: string`

#### Returns
- `boolean` — `false` if the primary identifier couldn't be resolved, else `true`.

### `Core.permissions.isOptin(src)`
Returns whether the player is opted into admin/dev features — defined here as "has any permission above `user`".

#### Parameters
- `src: integer`

#### Returns
- `boolean`

## Notes
- **Legacy vocabulary → ace principals.** `god`/`admin`/`mod`/`user` are checked against `kora_core.<level>` and `group.<level>` so both qbcore-native and group-based server configs work.
- **`hasPermission` also honours `command.<permission>`**, so an ace that grants a command implicitly satisfies the same-named permission check — this is what the commands module leans on.
- **Runtime grants are not persisted by this module** — `add_principal` lives for the server session (or until written into `server.cfg`). Persisting an admin list is out of scope here.

## Automatic txAdmin admins

With the included bridge installed, txAdmin's master account and accounts with
`all_permissions` automatically inherit `group.admin`. Their Cfx.re or Discord
identifier must be linked in txAdmin's Admin Manager. Limited-access txAdmin
accounts receive no automatic grant. Existing manual identifier grants continue
to work independently.

Add these lines before starting kora_core (the framework recipe includes them):

```cfg
add_ace group.admin group.admin allow
add_ace group.admin qbcore.admin allow
add_principal qbcore.txadmin group.admin
add_ace resource.kora_core command.add_principal allow
add_ace resource.kora_core command.remove_principal allow
```

Keep the server's existing `group.admin` permissions, such as `command allow`.
`qbcore.txadmin` is reserved for this integration. kora_core owns only the temporary
`player.<id> -> qbcore.txadmin` links and removes them on disconnect or resource
shutdown; it never edits manual identifier grants or txAdmin's admin list.

From the kora_core resource directory, install the helper before a **full server
startup**:

```sh
bash tools/install-txadmin-bridge.sh /absolute/path/to/citizen/system_resources/monitor
```

The installer copies `integrations/txadmin.lua` to
`monitor/resource/qbcore_bridge.lua` and appends its `server_script` entry to
monitor's manifest. Re-running it is safe; include it in the launch script so
replacing server artifacts restores the helper. On Windows, copy the same file
and append `server_script 'resource/qbcore_bridge.lua'` manually. Do not restart
monitor by itself: txAdmin clears its private authentication token after startup.
To uninstall, remove that entry and helper, then perform a full server startup.

The helper exposes only the server export
`exports.monitor:qbcoreCheckFullAdmin(src, callback)`, accepting calls from
kora_core. The callback receives `(allowed, reason?)`; identifiers come from the
server and the intercom token stays inside monitor. It uses txAdmin's existing
`/auth/self` contract, verified against the installed txAdmin 8.0.1. Check this
contract when upgrading txAdmin.

`modules/permissions/txadmin.lua` reacts to joins and
`txAdmin:events:adminsUpdated`. Updates revoke automatic grants before fresh
lookups finish, including removed accounts, and invalidate earlier responses.
There are no polling threads or timers, only finite event/startup/cleanup
iteration. Missing bridges and failed lookups grant nothing and emit diagnostics.

On changes, kora_core emits the local server event
`qbcore:server:txAdminPermissionChanged(src)`. kora_admin uses its existing resolver
to refresh the menu, including any explicitly selected Discord-only policy.
The public kora_core permission exports and their return shapes are unchanged.
