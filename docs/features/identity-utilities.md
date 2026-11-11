---
title: Identity, users and utilities
sidebar_position: 11
---

# Identity, users and utilities

## Identity (server)

| Export | Returns | Description |
| --- | --- | --- |
| `getIdentifiers(src)` | map | `[kind] = value` for every identifier (first one wins for repeated kinds), plus `ip` from the player endpoint. Values have no `kind:` prefix. |
| `primary(src)` | string or `nil` | The `Config.identity.primaryIdentifier` value. |
| `generateCitizenId()` | string | `citizenIdPrefix` plus `citizenIdLength` random uppercase letters/digits. Uniqueness is enforced by the `players.citizenid` unique index, not here. |
| `recordIdentifiers(citizenid, ids)` | | Queues upserts into `player_identifiers` (one row per kind). Called at character creation. |
| `findByIdentifier(kind, value)` | string array | Yields. Every citizen ID recorded with that identifier (alt detection). |

```lua
local ids = exports.kora_core:getIdentifiers(source)
local alts = exports.kora_core:findByIdentifier('discord', ids.discord)
```

## Users

One `users` row per license, separate from characters.

| Export | Description |
| --- | --- |
| `getMaxCharacters(license)` | Yields. The license's `max_characters` override, or `Config.identity.maxCharacters`. Creates the row if missing. |
| `setMaxCharacters(license, max)` | Yields. Sets the override; `nil` clears it. |
| `recordDiscord(src)` | Yields. Saves the Discord ID when `Config.identity.saveDiscord` is on and it changed. Runs automatically when characters are listed or created. |
| `getDiscord(license)` | Yields. Stored Discord ID or `nil`. |

```lua
-- grant a VIP an extra slot
exports.kora_core:setMaxCharacters(license, 6)
```

## Utilities (both realms)

| Export | Returns | Description |
| --- | --- | --- |
| `round(value, places)` | number | Rounds half up; `0` for non-numbers. |
| `trim(value)` | string | Strips surrounding whitespace; non-strings are returned unchanged. |
| `splitStr(str, delimiter)` | string array | Splits on a single (escaped) character. |
| `randomStr(length)` | string | Random uppercase letters. |
| `randomInt(length)` | string | Random digits, returned as a string (legacy behaviour). |
| `randomAlnum(length)` | string | Random uppercase letters and digits. |
| `deepClone(value)` | any | Recursive copy without metatables or cycle handling. |
| `pathGet(t, path)` | any | Value at a key-array path or `nil`. |
| `pathSet(t, path, value)` | any | Writes the value (creating tables) and returns the previous value. |

## Language selector (client)

`openSelector()` (also `/language` and the "Open language selector" key mapping,
default `Config.locales.defaultKey`) opens a kora_lib NUI menu listing
`Kora.locale.getLanguages()`. The choice is stored by kora_lib on the client (KVP),
not in PlayerData, so it survives character changes.

`shared/locale.lua` is a copy of qb-core's `Locale` class (with `extend`, `clear`,
`replace`, `locale`, `has`, `delete`, the flat `phrases` field, `fallbackLang`
and `warnOnMissing` defaulting to true). It is listed in the manifest `files` so a
`[compat]/qb-core` resource can serve `@qb-core/shared/locale.lua` to legacy
resources.

## Pause-menu title (client)

When `Config.server.name` is a non-empty string, the pause-menu header shows it.

## Vehicle air control (client)

With `Config.vehicleAirControl.disable` on, the driver of a vehicle whose class is
not in `exemptClasses` cannot use controls 59 to 64 (steer, pitch, roll) while the
vehicle is in the air and not on all wheels. Grounded vehicles, including upside
down ones, are never affected. Settings are read when the driver seat or vehicle
changes.

## Dependency supervisor (server)

When `Config.dependencySupervisor.enabled` is on, the start of a resource listed as
a key in `map` triggers `restart` of each listed dependent that is already started,
at most once per `cooldownMs` per dependent. It is meant for legacy resources (for
example `qb-banking`) that cannot re-register after kora_core, kora_inventory,
kora_target or PolyZone restart. See [Configuration](../configuration.md#configdependencysupervisor).
