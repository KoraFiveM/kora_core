# Identity module

## Overview
Identifier extraction and citizenid generation. Server only. The **primary identifier** (`Config.identity.primaryIdentifier`, default `'license'`) keys a player across all their characters; a **citizenid** keys a single character. All functions are defined on `Core.identity` and exported flat as `exports.kora_core:<fn>`.

## API

### `Core.identity.getIdentifiers(src)`
Extracts every identifier FiveM exposes for a source into a flat `kind → value` table (`license`, `discord`, `steam`, `ip`, …). For a kind that appears more than once (`license`/`license2`), the first is kept. The endpoint IP is fetched separately and stored under `ip`.

#### Parameters
- `src: integer` — Server source id.

#### Returns
- `table<string, string>`

#### Example
```lua
local ids = exports.kora_core:getIdentifiers(src)
print(ids.license, ids.discord)
```

### `Core.identity.primary(src)`
Returns the primary identifier value for `src` (the `Config.identity.primaryIdentifier` kind), or `nil` if it can't be resolved.

#### Parameters
- `src: integer`

#### Returns
- `string | nil`

### `Core.identity.generateCitizenId()`
Generates a candidate citizenid: `Config.identity.citizenIdPrefix` plus a random alphanumeric string of `Config.identity.citizenIdLength`. Uniqueness is **not** guaranteed here — it is enforced by the DB's UNIQUE index, and the persistence layer retries on collision.

#### Returns
- `string`

### `Core.identity.recordIdentifiers(citizenid, ids)`
Records a character's identifiers into `player_identifiers` (one row per `(citizenid, kind)`), fire-and-forget through the coalescing SQL queue. Used for ban/alt detection.

#### Parameters
- `citizenid: string`
- `ids: table<string, string>` — Typically the result of `getIdentifiers`.

### `Core.identity.findByIdentifier(kind, value)`
Looks up every citizenid that has ever used a given identifier. **Yields** (runs a DB query).

#### Parameters
- `kind: string` — e.g. `'discord'`, `'ip'`.
- `value: string`

#### Returns
- `string[]` — Matching citizenids.

#### Example
```lua
local alts = exports.kora_core:findByIdentifier('ip', someIp)
```

## Notes
- `getIdentifiers` folds `ip` (the endpoint) in alongside the real identifier entries, even though FiveM does not expose it as an identifier — convenient, but remember it is not a stable ban key on its own.
- `generateCitizenId` is a *candidate* generator, not a uniqueness guarantee; always go through `Core.persistence.insertNew`, which relies on the DB UNIQUE index and retries.
- `recordIdentifiers` and `findByIdentifier` are the alt-detection surface: write on character create, query when investigating.
