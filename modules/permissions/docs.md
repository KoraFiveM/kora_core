# Permissions module

## Overview
Thin wrappers over FiveM's ace permission system, mapping the legacy QBCore vocabulary (`user`/`mod`/`admin`/`god`) onto ace principals. Runtime grants add an ace principal for the player's primary identifier. Server only. Functions are defined on `Core.permissions` and exported flat as `exports.qbcore:<fn>`.

## API

### `Core.permissions.getPermission(src)`
Returns the player's highest permission level: the first of `god`, `admin`, `mod`, `user` they satisfy (checked against both `qbcore.<level>` and `group.<level>` ace objects). Everyone is at least `user`.

#### Parameters
- `src: integer`

#### Returns
- `string` — `'god'` | `'admin'` | `'mod'` | `'user'`.

#### Example
```lua
if exports.qbcore:getPermission(src) == 'god' then
    -- highest tier
end
```

### `Core.permissions.hasPermission(src, permission)`
Returns whether the player has a given permission. `'user'` is always true; otherwise checks `qbcore.<permission>`, `group.<permission>`, and `command.<permission>` ace objects.

#### Parameters
- `src: integer`
- `permission: string`

#### Returns
- `boolean`

### `Core.permissions.addPermission(src, permission)`
Grants a runtime permission by adding an ace principal for the player's primary identifier (`add_principal identifier.<kind>:<value> qbcore.<permission>`).

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
- **Legacy vocabulary → ace principals.** `god`/`admin`/`mod`/`user` are checked against `qbcore.<level>` and `group.<level>` so both qbcore-native and group-based server configs work.
- **`hasPermission` also honours `command.<permission>`**, so an ace that grants a command implicitly satisfies the same-named permission check — this is what the commands module leans on.
- **Runtime grants are not persisted by this module** — `add_principal` lives for the server session (or until written into `server.cfg`). Persisting an admin list is out of scope here.
