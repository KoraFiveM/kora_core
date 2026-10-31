# identity module guide

## Purpose
Identifier extraction and citizenid generation, server-side only. Establishes the two-level identity model the rest of the framework assumes: the **primary identifier** (default `license`) keys a *player* across characters; a **citizenid** keys a single *character*.

## Public API
- `Core.identity.getIdentifiers(src)` — All identifiers as a flat `kind → value` table (plus `ip`).
- `Core.identity.primary(src)` — The primary-identifier value, or `nil`.
- `Core.identity.generateCitizenId()` — A *candidate* citizenid (prefix + random alnum).
- `Core.identity.recordIdentifiers(citizenid, ids)` — Persist a character's identifiers for alt detection (fire-and-forget).
- `Core.identity.findByIdentifier(kind, value)` — Citizenids that ever used an identifier (yields).

## Implementation notes
- **`getIdentifiers` dedupes by kind, first wins.** FiveM can report `license` and `license2`; only the first of each `kind` is kept. `ip` is not an identifier entry, so it's fetched with `GetPlayerEndpoint` and merged in — handy, but weaker as a ban key than a hardware/license identifier.
- **`generateCitizenId` does not guarantee uniqueness.** It's a pure random generator (`Core.util.randomAlnum` + configured prefix/length). The actual guarantee is the DB UNIQUE index on `citizenid`; `Core.persistence.insertNew` uses a plain INSERT so a collision raises and can be retried, rather than an upsert that would silently overwrite.
- **`recordIdentifiers` writes through `Kora.sql.enqueueMany`** with a composite PK `(citizenid, kind)` in `assign` mode — an idempotent upsert of one row per identifier, off the hot path.
- **`findByIdentifier` yields.** It's a live query, meant for admin/ban tooling, not per-frame use.
- **No `CoreInternal.identity` table.** All functions are public. Internals in other modules live on `CoreInternal.<module>` and are never exported; `build/finalise.lua` walks only `Core.<module>` and skips `_`-prefixed functions.

## Best practices
- Resolve identity through `Core.identity.primary(src)` rather than reading FiveM identifiers ad hoc — it honours `Config.identity.primaryIdentifier`, which a server may repoint (e.g. to `discord`).
- Treat `citizenid` as the character key everywhere; treat the primary identifier as the account key. Never persist `license`/`cid` as mutable player data (the persistence layer refuses them).
