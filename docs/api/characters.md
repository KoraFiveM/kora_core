---
title: "Characters and multicharacter"
sidebar_position: 6
---


# Characters and multicharacter

## Server

The character-select lifecycle. kora_core ships no NUI: a character-select UI resource drives it through the net events below or the exports. Characters are keyed by the player's primary identifier (`Config.identity.primaryIdentifier`, default `license`). Every net event derives the identity from `source`; the client only ever supplies a citizenid, charinfo or slot hint, and ownership is checked server-side before anything loads or deletes.

Namespace: `exports.kora_core` · Source: `modules/multichar/server.lua`

### Net events (server side)

All are registered with RegisterNetEvent and use the engine-provided `source`. None of them are rate limited in this module; `createCharacter` has a per-source in-progress lock.

| Event | Arguments | Server behaviour |
| --- | --- | --- |
| kora_core:server:requestCharacters | (none) | Replies `kora_core:client:receiveCharacters` to the caller with `getCharacters(source)`. |
| kora_core:server:selectCharacter | citizenid | Runs `selectCharacter(source, citizenid)` and replies `kora_core:client:characterSelected` with `(ok, err)`, where `ok` is `true` or `false`. |
| kora_core:server:createCharacter | charinfo, cid? | Runs `exports.kora_core:createCharacter(source, charinfo, cid)`. Replies `characterSelected(true)` or `characterSelected(false, err)`. A client-supplied `cid` is honoured only if it is between 1 and the character limit and free, otherwise the reason is `requested character slot is unavailable`; without `cid` the next free slot is used or the reason is `character limit reached`. |
| kora_core:server:deleteCharacter | citizenid | Runs `deleteCharacter(source, citizenid)`, ignores its result, then replies `kora_core:client:receiveCharacters` with a fresh list. The client learns of a refused delete only by the character still being listed. |
| kora_core:client:receiveCharacters | characters | Server to client. Array of summaries `{citizenid, cid, name, charinfo, money, job, gang}` ordered by `cid`. |
| kora_core:client:characterSelected | ok, err? | Server to client. On success the player is logged in; on failure `err` is the reason string. |

### How it works

Creation itself is not in this module: `kora_core:server:createCharacter` calls `exports.kora_core:createCharacter` (player module), which validates charinfo and enforces the slot limit. Selecting calls the player module `login` after the ownership check.

### Terms used on this page

| Term | Meaning |
| --- | --- |
| Primary identifier | `Core.identity.primary(src)`: the identifier named by `Config.identity.primaryIdentifier`. A player without it gets an empty character list and cannot own anything. |
| maxCharacters | `Config.identity.maxCharacters` (default 5) unless the license has a `users.max_characters` override (`Core.users.getMaxCharacters`). It is enforced by `createCharacter`, not by the select exports. |
| Soft delete | Deleting sets `players.deleted_at = NOW()`. The row stays; list and load queries filter `deleted_at IS NULL`. |

### Ownership validation

`selectCharacter` loads the row, then compares `data.license` with the caller's primary identifier and refuses with `character does not belong to this player`. `deleteCharacter` does the same with `not your character`, and `ownsCharacter` returns `false`. A forged citizenid for someone else's character therefore never logs in, never deletes, and reveals nothing beyond a failure string.

### Delete of a logged-in character

If the target citizenid is currently online, `deleteCharacter` first calls `exports.kora_core:logout(player.source)` so the final save is durable, and aborts with the logout error if that fails. The row is soft-deleted only afterwards. `_deleteCharacterRow` itself refuses an online citizenid with `player is online`.

### Client-driven slot hint

The default client sends `cid = 1` when creating. The server does not ignore a client `cid`: it honours it when in bounds and free (see the table above). Do not rely on it for limits; the limit check still applies to the count when `cid` is nil.

### Functions

All four exports yield (SQL). Resource-side callers pass the player server id as `src`. Soft failures return `false, reason`; nothing here throws on bad input except unexpected runtime errors.

#### `exports.kora_core:getCharacters(src)`

List the characters that belong to a connected player's primary identifier. Also records the player's Discord id on their `users` row when `Config.identity.saveDiscord` is true. Yields.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |

**Returns**

- **characters** — array of `{citizenid, cid, name, charinfo, money, job, gang}`, ordered by `cid`. `charinfo`, `money`, `job` and `gang` are decoded from JSON; a column that fails to decode becomes `{}`.
- **empty table** — returned when the player has no primary identifier, or has no non-deleted characters. Never nil.

**Example**

```lua
local characters = exports.kora_core:getCharacters(src)
for _, character in ipairs(characters) do
    print(character.cid, character.citizenid, character.charinfo.firstname)
end
```

**Representative console output**

```text
1   AB12CD34   John
```

#### `exports.kora_core:ownsCharacter(src, citizenid)`

Check that a citizenid belongs to the player's primary identifier without logging the character in. Intended for pre-login integrations such as a selector fetching a saved appearance. Yields.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `citizenid` | string | Character to check. |

**Returns**

- **true** — the character exists, is not deleted, and its license equals the caller's primary identifier.
- **false** — citizenid is not a non-empty string, the player has no primary identifier, the row could not be loaded (not found, deleted, or persistence busy), or it belongs to another license. No reason string is returned.

**Example**

```lua
RegisterNetEvent('myselector:requestAppearance', function(citizenid)
    local src = source
    if not exports.kora_core:ownsCharacter(src, citizenid) then return end
    local appearance = exports.myselector:loadAppearance(citizenid)
    TriggerClientEvent('myselector:appearance', src, appearance)
end)
```

**Representative console output**

```text
true
```

#### `exports.kora_core:selectCharacter(src, citizenid)`

Load an existing character and log the player in as it. Yields. This is what `kora_core:server:selectCharacter` calls.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `citizenid` | string | Character to load. |

**Returns**

- **true** — the character is loaded and the player is logged in (result of `login`).
- **false, reason** — the load failed. `reason` is the persistence error (`not found`, `player data is busy`, or a SQL/persistence message; when none is given `reason` is nil).
- **false, 'character does not belong to this player'** — the row's license differs from the caller's primary identifier.
- **false, reason** — from the player module `login`: `source already logged in`, `character already logged in`, `player data is busy`, or a persistence availability error.

**Example**

```lua
local ok, err = exports.kora_core:selectCharacter(src, citizenid)
if not ok then
    print(('select failed for %s: %s'):format(src, tostring(err)))
end
```

**Representative console output**

```text
select failed for 12: character already logged in
```

#### `exports.kora_core:deleteCharacter(src, citizenid)`

Soft-delete one of the caller's characters, logging it out first if it is online. Yields.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `citizenid` | string | Character to delete. |

**Returns**

- **true** — `deleted_at` was set.
- **false, 'character not found'** — no loadable non-deleted row (also when the load failed).
- **false, 'player session changed'** — the caller's primary identifier changed while the call yielded.
- **false, 'not your character'** — the row belongs to another license.
- **false, reason** — the character is online and `logout` failed; `reason` is the logout error or `character logout failed`.
- **false, 'player is online'** — the character came online during the call.
- **false** — no reason: the row is busy with a durable column operation, persistent columns are unavailable, or the UPDATE failed.

**Example**

```lua
local ok, err = exports.kora_core:deleteCharacter(src, citizenid)
if not ok then
    TriggerClientEvent('QBCore:Notify', src, err or 'could not delete character', 'error')
end
```

**Representative console output**

```text
-- ok = false, err = 'not your character'
```

### Common use cases

- Build a character-select UI: listen for `kora_core:client:receiveCharacters`, draw the list, then trigger `kora_core:server:selectCharacter` or `kora_core:server:createCharacter`.
- Gate a pre-login endpoint (appearance preview) with `ownsCharacter`.
- Admin tooling that removes a character through the same safe logout-then-soft-delete path.

### Limits and related APIs

No NUI is shipped. The delete net event reports nothing to the client about failures. `selectCharacter` and `deleteCharacter` return `false` (not nil) on failure. Creation rules (name length, birthdate, gender, nationality, phone) live in the player module `createCharacter`: the phone is always generated server-side and any client value is ignored.

### Related guides

- [Player: createCharacter, login, logout](./player.md)
- [Persistence](./persistence.md)
- [Permissions](./permissions.md)
- [Config.identity](./configuration.md)

## Client

A minimal default flow so a bare server with no character-select UI still spawns the player: about 500 ms after the kora_core client scripts start it requests the character list, selects slot 1 and creates a default character when the list is empty. A real UI resource calls `claimUI` to suppress this and drives the events itself.

Namespace: `exports.kora_core` · Source: `modules/multichar/client.lua`

### Auto flow versus claimUI

1. **Start** — A thread in kora_core waits 500 ms. If `claimUI` has not been called by then it calls `request()`.
2. **Receive** — The default `kora_core:client:receiveCharacters` handler does nothing when the UI has claimed, or when a selection is already in progress.
3. **Pick** — If the list has a first entry it calls `select(characters[1].citizenid)` (lowest `cid`). If the list is empty it calls `create` with John Doe, `1990-01-01`, gender 0, nationality USA, a random seven digit phone and `cid` 1. The server ignores the phone and validates the rest.
4. **Result** — On `kora_core:client:characterSelected(ok, err)` with `ok` falsy it prints `[kora_core:multichar] character select failed: <err>` and allows another attempt. On success the in-progress flag stays set.

### Terms used on this page

| Term | Meaning |
| --- | --- |
| claimUI window | Call `claimUI` before about 500 ms after kora_core's own client scripts start. After that the default `request()` has already been sent. A late claim still stops the default handler from selecting or creating, but your UI must then handle the reply itself. |
| Claim scope | The flag lives in kora_core's Lua VM and lasts until kora_core restarts. There is no unclaim export. |

### Functions

All four are thin wrappers around TriggerServerEvent and return nothing. The server replies through the events described in the server realm. A resource wanting to bypass the exports can trigger the same net events directly.

#### `exports.kora_core:claimUI()`

Tell kora_core a character-select UI is running, which disables the default auto select/create flow, including the initial request.

**Parameters**



**Returns**

- **nil** — returns nothing.

**Example**

```lua
-- client script of your multicharacter UI, as early as possible
exports.kora_core:claimUI()
AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    exports.kora_core:request()
end)
```

**Representative console output**

```text
-- no output; the default flow will not fire
```

#### `exports.kora_core:request()`

Ask the server for this player's character list (`kora_core:server:requestCharacters`).

**Parameters**



**Returns**

- **nil** — returns nothing. The list arrives later via `kora_core:client:receiveCharacters(characters)`.

**Example**

```lua
RegisterNetEvent('kora_core:client:receiveCharacters', function(characters)
    SendNUIMessage({ action = 'characters', characters = characters })
end)
exports.kora_core:request()
```

**Representative console output**

```text
-- later: receiveCharacters fires with { { citizenid = 'AB12CD34', cid = 1, ... } }
```

#### `exports.kora_core:select(citizenid)`

Select an existing character (`kora_core:server:selectCharacter`).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `citizenid` | string | Character to load. The server checks that it belongs to the player. |

**Returns**

- **nil** — returns nothing. The outcome arrives as `kora_core:client:characterSelected(ok, err)`.

**Example**

```lua
RegisterNUICallback('selectCharacter', function(data, cb)
    exports.kora_core:select(data.citizenid)
    cb('ok')
end)
```

**Representative console output**

```text
-- characterSelected(true) on success, characterSelected(false, 'character does not belong to this player') on a forged id
```

#### `exports.kora_core:create(charinfo, cid)`

Create a new character (`kora_core:server:createCharacter`). The server validates everything and generates the phone.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `charinfo` | table | `{firstname, lastname, birthdate?, gender?, nationality?}`. Firstname and lastname are 1 to 24 characters; birthdate is `YYYY-MM-DD`, not in the future, default `1990-01-01`; gender is 0 or 1, default 0; nationality is 2 to 32 characters, default `USA`. |
| `cid?` | integer | Preferred slot. Honoured only when it is between 1 and the character limit and free; omit to let the server pick the next free slot. |

**Returns**

- **nil** — returns nothing. The outcome arrives as `kora_core:client:characterSelected(true)` or `(false, err)`; the creating call logs the player in on success.

**Example**

```lua
RegisterNUICallback('createCharacter', function(data, cb)
    exports.kora_core:create({
        firstname = data.firstname,
        lastname = data.lastname,
        birthdate = data.birthdate,
        gender = data.gender,
        nationality = data.nationality,
    })
    cb('ok')
end)
```

**Representative console output**

```text
-- characterSelected(false, 'character limit reached') when the player already has maxCharacters
```

### Limits and related APIs

Client exports only send events; all validation is server-side. `Config.identity.maxCharacters` is not readable here as a guarantee: the server decides.

### Related guides

- [Player: createCharacter, login](./player.md)
- [Replication](./replication.md)

## Identity, users and character slots (code-derived)

### Identity (server)

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

### Users

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
