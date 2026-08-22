# Multichar module

## Overview
The character-select lifecycle: list, select, delete. **No NUI is shipped.** A character-select UI resource (or the `qb-multicharacter` compat events) drives this via net events and the exports below. On a bare server with no UI, the client module runs a **default auto-select flow** so a player still spawns. Server owns the character operations; the client provides the default flow and the request/select/create helpers. Functions are defined on `Core.multichar` and exported flat as `exports.qbcore:<fn>`.

**Character creation is not part of this module's public API.** Use `Core.player.createCharacter` (`exports.qbcore:createCharacter`) directly — it is the single public creator (multichar's create was removed to avoid a flat-export name collision). The server's `qbcore:server:createCharacter` net event calls it under the hood.

## API

### `Core.multichar.getCharacters(src)` — server
Lists a source's characters (by their primary identifier), with `charinfo`/`money`/`job` decoded. **Yields.**

#### Parameters
- `src: integer`

#### Returns
- `table[]` — Summaries: `{ citizenid, cid, name, charinfo, money, job }`.

### `Core.multichar.selectCharacter(src, citizenid)` — server
Loads and logs in an existing character, after verifying it belongs to this source's identifier. **Yields.**

#### Parameters
- `src: integer`
- `citizenid: string`

#### Returns
- `boolean`
- `string | nil` — Failure reason (a load error, or `'character does not belong to this player'`).

### `Core.multichar.deleteCharacter(src, citizenid)` — server
Soft-deletes a character (after an ownership check), logging the player out first if they're currently on it. **Yields.**

#### Parameters
- `src: integer`
- `citizenid: string`

#### Returns
- `boolean`
- `string | nil` — Failure reason (`'not your character'`).

### `Core.multichar.request()` — client
Asks the server for this player's characters (fires `qbcore:server:requestCharacters`; the reply arrives as `qbcore:client:receiveCharacters`).

### `Core.multichar.select(citizenid)` — client
Selects an existing character by citizenid.

#### Parameters
- `citizenid: string`

### `Core.multichar.create(charinfo, cid)` — client
Requests creation of a new character (fires `qbcore:server:createCharacter`, which the server routes to `Core.player.createCharacter`).

#### Parameters
- `charinfo: table`
- `cid: integer | nil`

### `Core.multichar.claimUI()` — client
Suppresses the built-in default auto-select/auto-create flow (see "Default auto-select flow" below). A character-select UI resource calls this, as `exports.qbcore:claimUI()`, before it starts driving selection itself — and before qbcore's own ~500ms kick-off timer fires, or the default flow may already have run.

## Net-event surface (for a UI resource)
Server listens for: `qbcore:server:requestCharacters`, `qbcore:server:selectCharacter`, `qbcore:server:createCharacter`, `qbcore:server:deleteCharacter`.
Server replies with: `qbcore:client:receiveCharacters`, `qbcore:client:characterSelected` (`ok, err`).

## Notes
- **Creation lives on `Core.player`.** There is no `Core.multichar.createCharacter`; call `Core.player.createCharacter(src, charinfo, cid)` server-side, or drive it through the `qbcore:server:createCharacter` net event / the client `create` helper.
- **Default auto-select flow.** On load, the client waits briefly then requests characters and, on receiving them, selects slot 1 — or creates a default "John Doe" character (via the create net event) if none exist — so a bare server spawns the player with no UI.
- **A UI resource overrides the default flow** by calling `Core.multichar.claimUI()` (as `exports.qbcore:claimUI()`, which suppresses the auto-select) and handling the same events / calling `request`/`select`/`create` itself. This is a real cross-resource export rather than a shared global — every resource (client and server alike) runs in its own isolated Lua VM, so nothing written to `_G` in one resource's script is ever visible from another's.
- **Ownership is verified server-side.** `selectCharacter`/`deleteCharacter` check the character's `license` against the source's primary identifier — a client can't select or delete a character that isn't theirs.
