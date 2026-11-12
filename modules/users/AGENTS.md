# users module guide

## Purpose
One row per identity (license), tracking an optional per-license override for the multichar character-slot cap on top of the global `Config.identity.maxCharacters` default. This is the ONLY thing this module owns today -- it is not a general "account" table, and it does not duplicate anything `player_identifiers`/`players` already track.

## Public API
Server:
- `Core.users.getMaxCharacters(license)` -- the effective cap for a license (override or global default). Ensures a `users` row exists as a side effect.
- `Core.users.setMaxCharacters(license, maxCharacters)` -- sets or clears (`nil`) the override.

## Design
`Core.player.createCharacter` (`modules/player/server.lua`) is the sole enforcement point: it reads `getMaxCharacters(license)`, lists the license's existing characters, and either validates an explicit `cid` against that cap or computes the next free slot itself. A client-supplied `cid` from `qb-multicharacter:server:createCharacter` (`compat/server/qb-multicharacter.lua`) is deliberately NOT forwarded to `createCharacter` -- trusting it would let a client bypass the limit outright by always sending an "available" slot number regardless of how many characters they actually have.

## Implementation notes
- `users(license PK, max_characters NULL, created_at, last_seen)` -- declared in `modules/persistence/schema.lua` and created by `Kora.sql.ensureTables`.
- `getMaxCharacters` ensures the row exists via `INSERT IGNORE` rather than `INSERT ... ON DUPLICATE KEY UPDATE`, since a read shouldn't bump `last_seen`; nothing currently reads `last_seen` at all, it exists for future use (e.g. inactivity reporting).
- No module-local state, no `CoreInternal.users` table -- both functions are pure DB round-trips.

## Best practices
- Never read `Config.identity.maxCharacters` directly to decide whether a license can create another character -- always go through `Core.users.getMaxCharacters`, or a per-license override silently won't apply.
- Don't grow this into a general per-player settings table without a real second use case -- a one-column override table is the right size for what exists today.
