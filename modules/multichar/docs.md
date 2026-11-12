# Multichar module

## Overview
The character-select lifecycle: list, select, delete. **No NUI is shipped.** A character-select UI resource (or the `qb-multicharacter` compat events) drives this via net events and the exports below. On a bare server with no UI, the client module runs a **default auto-select flow** so a player still spawns. Server owns the character operations; the client provides the default flow and the request/select/create helpers. Functions are defined on `Core.multichar` and exported flat as `exports.kora_core:<fn>`.

**Character creation is not part of this module's public API.** Use `Core.player.createCharacter` (`exports.kora_core:createCharacter`) directly — it is the single public creator (multichar's create was removed to avoid a flat-export name collision). The server's `kora_core:server:createCharacter` net event calls it under the hood.

## API

### `Core.multichar.getCharacters(src)` — server
Lists a source's characters (by their primary identifier), with `charinfo`/`money`/`job`/`gang` decoded. **Yields.**

#### Parameters
- `src: integer`

#### Returns
- `table[]` — Summaries: `{ citizenid, cid, name, charinfo, money, job, gang }`.

### `Core.multichar.ownsCharacter(src, citizenid)` — server
Performs an ownership check without logging the character in. This is intended
for pre-login integrations such as a character preview fetching appearance.
Soft-deleted or foreign characters return `false`.

### `Core.multichar.selectCharacter(src, citizenid)` — server
Loads and logs in an existing character, after verifying it belongs to this source's identifier. **Yields.**

#### Parameters
- `src: integer`
- `citizenid: string`

#### Returns
- `boolean`
- `string | nil` — Failure reason (a load error, or `'character does not belong to this player'`).

### `Core.multichar.deleteCharacter(src, citizenid)` — server
Soft-deletes a character after an ownership check, logging the player out first if they are currently on it. **Yields.** A failed logout aborts deletion. The row cannot be deleted while a player is online or a durable provider operation is pending; ownership is rechecked after the initial storage wait.

#### Parameters
- `src: integer`
- `citizenid: string`

#### Returns
- `boolean`
- `string | nil` — Failure reason (`'not your character'`).

### `Core.multichar.request()` — client
Asks the server for this player's characters (fires `kora_core:server:requestCharacters`; the reply arrives as `kora_core:client:receiveCharacters`).

### `Core.multichar.select(citizenid)` — client
Selects an existing character by citizenid.

#### Parameters
- `citizenid: string`

### `Core.multichar.create(charinfo, cid)` — client
Requests creation of a new character (fires `kora_core:server:createCharacter`, which the server routes to `Core.player.createCharacter`).

#### Parameters
- `charinfo: table`
- `cid: integer | nil`

### `Core.multichar.claimUI()` — client
Suppresses the built-in default auto-select/auto-create flow (see "Default auto-select flow" below). A character-select UI resource calls this, as `exports.kora_core:claimUI()`, before it starts driving selection itself — and before kora_core's own ~500ms kick-off timer fires, or the default flow may already have run.

## Net-event surface (for a UI resource)
Server listens for: `kora_core:server:requestCharacters`, `kora_core:server:selectCharacter`, `kora_core:server:createCharacter`, `kora_core:server:deleteCharacter`.
Server replies with: `kora_core:client:receiveCharacters`, `kora_core:client:characterSelected` (`ok, err`).

## Notes
- **Creation lives on `Core.player`.** There is no `Core.multichar.createCharacter`; call `Core.player.createCharacter(src, charinfo, cid)` server-side, or drive it through the `kora_core:server:createCharacter` net event / the client `create` helper.
- **Default auto-select flow.** On load, the client waits briefly then requests characters and, on receiving them, selects slot 1 — or creates a default "John Doe" character (via the create net event) if none exist — so a bare server spawns the player with no UI.
- **A UI resource overrides the default flow** by calling `Core.multichar.claimUI()` (as `exports.kora_core:claimUI()`, which suppresses the auto-select) and handling the same events / calling `request`/`select`/`create` itself. This is a real cross-resource export rather than a shared global — every resource (client and server alike) runs in its own isolated Lua VM, so nothing written to `_G` in one resource's script is ever visible from another's.
- **Ownership is verified server-side.** `selectCharacter`/`deleteCharacter` check the character's `license` against the source's primary identifier — a client can't select or delete a character that isn't theirs.
