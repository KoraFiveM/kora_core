# Users module

## Overview
One row per identity (license), separate from a character -- a single license owns several `players` rows via `Core.multichar`. Currently the only thing tracked here is an optional per-license override for the character-slot cap, layered on top of the global `Config.identity.maxCharacters` default (e.g. a VIP allowance). Functions are defined on `Core.users` and exported flat as `exports.qbcore:<fn>`.

## API

### `Core.users.getMaxCharacters(license)` — server
Returns this license's character-slot cap: its own `users.max_characters` override if one is set, `Config.identity.maxCharacters` otherwise. Ensures a `users` row exists for the license along the way (`INSERT IGNORE`, so a concurrent first-call race just no-ops on the loser). **Yields.**

#### Parameters
- `license: string`

#### Returns
- `integer`

### `Core.users.setMaxCharacters(license, maxCharacters)` — server
Sets (or clears, with `nil`) a per-license character-slot override. **Yields.**

#### Parameters
- `license: string`
- `maxCharacters: integer | nil`

## Notes
- `Core.player.createCharacter` is the enforcement point: it calls `getMaxCharacters` and computes the next free slot itself (or validates an explicit `cid`) against it. A `users` row with no override (`max_characters IS NULL`) is indistinguishable from "no row yet" for read purposes -- both fall back to `Config.identity.maxCharacters`.
- No client-side API: this is a server-authoritative account setting, not something a character-select UI reads directly (it learns the effective cap via `qb-multicharacter:server:GetNumberOfCharacters`, same as before).
