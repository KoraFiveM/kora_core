# multichar module guide

## Purpose
The character-select lifecycle (list/select/delete), server-authoritative, with a minimal client-side **default flow** so a server with no character-select UI still spawns players. A real UI resource (or the `qb-multicharacter` compat) overrides the default and drives selection itself. Character *creation* is not owned here — it lives on `Core.player.createCharacter`.

## Public API
Server:
- `Core.multichar.getCharacters(src)` — decoded character summaries (yields).
- `Core.multichar.ownsCharacter(src, citizenid)` — pre-login ownership check (yields).
- `Core.multichar.selectCharacter(src, citizenid)` — ownership-checked load + login (yields). `(true)`/`(false, err)`.
- `Core.multichar.deleteCharacter(src, citizenid)` — ownership-checked soft-delete, logs out if active (yields).

Client:
- `Core.multichar.request()` / `select(citizenid)` / `create(charinfo, cid)` — thin `TriggerServerEvent` helpers.
- `Core.multichar.claimUI()` — suppresses the built-in default auto-select/auto-create flow; a UI resource calls this (as `exports.qbcore:claimUI()`) before it starts driving selection itself.

Creation: use **`Core.player.createCharacter(src, charinfo, cid)`** (`exports.qbcore:createCharacter`). There is deliberately no `Core.multichar.createCharacter` — it was removed so two modules don't define the same `createCharacter` flat-export name (which `build/finalise.lua` treats as a boot-time collision). The `qbcore:server:createCharacter` net event calls `Core.player.createCharacter` directly.

## Design — default flow vs UI override
The client (`client.lua`) kicks off ~500ms after load: unless a UI has called `Core.multichar.claimUI()`, it calls `request()`. When `qbcore:client:receiveCharacters` arrives (and no UI claimed it, and it isn't already selecting), it auto-selects `characters[1]` or, if there are none, `create()`s a default "John Doe" character in slot 1. That's the entire bare-server spawn path.

A UI resource takes over by:
1. Calling `exports.qbcore:claimUI()` (suppresses the auto-select in both the timed kick-off and the receive handler). This is a real cross-resource export, not a `_G` flag — every resource gets its own isolated Lua VM (client and server alike), so a `_G` write in a UI resource's own script would never be visible to qbcore's script.
2. Handling `qbcore:client:receiveCharacters` / `qbcore:client:characterSelected` itself and calling `request`/`select`/`create` (or the server net events directly) from its own UI.

## Implementation notes
- **Ownership is enforced server-side, every time.** `selectCharacter` loads the row (via `Core.persistence._load`) and compares `data.license` to `Core.identity.primary(src)`; `deleteCharacter` does the same. A client sending an arbitrary citizenid can't hijack another player's character.
- **`deleteCharacter` logs out an active character first** (`Core.player.logout` if the citizenid is currently online) so the delete doesn't strand a live handle, then calls `Core.persistence._deleteCharacterRow`.
- **Creation is routed, not duplicated.** The `qbcore:server:createCharacter` handler calls `Core.player.createCharacter` and replies with `qbcore:client:characterSelected`. Keeping a single creator avoids the flat-export collision and keeps the fresh-data/insert/adopt path in one place.
- **Net-event surface mirrors the exports** so the compat `qb-multicharacter` events and any UI can drive the same operations: request/select/create/delete inbound, `receiveCharacters`/`characterSelected` outbound.
- **No `provide 'qb-multicharacter'`.** Per `fxmanifest.lua`, qbcore deliberately does *not* claim that resource name — the compat is event-level only, so a server keeps its real character-select UI. See the manifest comment.
- **Internals.** The `selecting` guard and `dec` decoder are file-local; the module has no `CoreInternal.multichar` table. Internals elsewhere use `CoreInternal.<module>`; `build/finalise.lua` walks only `Core.<module>` and skips `_`-prefixed functions.

## Best practices
- A UI resource must call `exports.qbcore:claimUI()` early (before the ~500ms kick-off) or the default flow may auto-select before the UI opens.
- Do character operations through these exports/events so ownership checks and the login/logout lifecycle run — don't call `Core.persistence` directly to load a character.
- Create characters via `Core.player.createCharacter` (or the create net event), not by looking for a multichar creator that no longer exists.
