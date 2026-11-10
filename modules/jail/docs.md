# Jail module

## Overview
A minimal built-in jail (teleport + movement containment + timed release), used unless a real prison resource is running. Functions are defined on `Core.jail` and exported flat as `exports.kora_core:<fn>` (server realm). The client realm has no exported API — it only reacts to server pushes.

## API (server)

### `Core.jail.jailPlayer(src, minutes, reason)`
Jails `src` for `minutes`, or defers to an external prison resource (`Config.jail.deferToResources`) if one is currently running.

#### Parameters
- `src: integer`
- `minutes: number` — must be positive.
- `reason: string | nil`

#### Returns
- `boolean`, `string | nil` — `false, 'no such player'` / `false, 'minutes must be positive'` on refusal.

#### Example
```lua
exports.kora_core:jailPlayer(src, 15, 'Assault on an officer')
```

### `Core.jail.release(src)`
Releases `src` from Core.jail's own jail. Does not affect a sentence an external prison resource is managing.

#### Returns
- `boolean` — `false` if the player wasn't jailed by this module.

### `Core.jail.getRemaining(src)`
#### Returns
- `integer` — seconds remaining, `0` if not jailed or the sentence already expired.

### `Core.jail.isJailed(src)`
#### Returns
- `boolean`

## Events

- `kora_core:server:onJailRequest(src, minutes, reason, resourceName)` — fired instead of jailing internally when `resourceName` (from `Config.jail.deferToResources`) is running.
- `kora_core:server:playerJailed(src, minutes, reason)` — fired after an internal jail.
- `kora_core:server:playerReleased(src)` — fired after an internal release.
- `kora_core:client:jailTeleport(coords, remainingSeconds)` (client) — teleport + start containment.
- `kora_core:client:jailRelease` (client) — clear containment.

## Notes
- **State lives in `metadata.jailed`** as a UNIX release timestamp — survives relog with no extra schema. Read it directly if you need the raw timestamp; prefer `getRemaining`/`isJailed` otherwise.
- **External prison resources take over entirely.** If any resource named in `Config.jail.deferToResources` is `started`, `jailPlayer` fires `kora_core:server:onJailRequest` and does nothing else — no `metadata.jailed` write, no teleport push. That resource's own release flow is expected to run independently of `Core.jail.release`.
- **Rejoin mid-sentence re-teleports automatically** (on `kora_core:server:playerLoaded`), unless an external prison resource is now running.
- **Client containment** is a 30m `Kora.zones` sphere around the jail coords; leaving it snaps the player back. No built-in countdown UI — build one against `getRemaining` if you need it.
