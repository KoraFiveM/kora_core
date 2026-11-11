---
title: Jail
sidebar_position: 7
---

# Jail

A minimal built-in jail: teleport, a 30 m containment sphere and a timed release.
If a dedicated prison resource from `Config.jail.deferToResources` is started,
kora_core hands the request to it instead.

## Server API

| Export | Returns | Description |
| --- | --- | --- |
| `jailPlayer(src, minutes, reason)` | `true` or `false, err` | Jails for a positive number of minutes, or defers to an external prison. Errors: `no such player`, `minutes must be positive`. |
| `release(src)` | boolean | Releases a player jailed by kora_core. `false` if not jailed by it. |
| `getRemaining(src)` | integer | Seconds left, `0` if not jailed or expired. |
| `isJailed(src)` | boolean | `getRemaining(src) > 0`. |

```lua
exports.kora_core:jailPlayer(targetSource, 15, 'Assault on an officer')
```

## Behaviour

- The sentence is stored as a UNIX release timestamp in both `metadata.jailed` and
  `metadata.injail`, so it survives relog without extra tables. Release sets both
  to 0.
- If any resource in `Config.jail.deferToResources` (default `xt-prison`,
  `qbx_prison`) is started, `jailPlayer` only fires
  `kora_core:server:onJailRequest(src, minutes, reason, resourceName)` and returns
  `true`; that resource owns the sentence and its release.
- Otherwise the player is teleported to `Config.jail.coords`, the client gets a
  30 m `Kora.zones` sphere that snaps the player back when they leave it, and
  `kora_core:server:playerJailed(src, minutes, reason)` fires. Release sends
  `kora_core:client:jailRelease` and fires `kora_core:server:playerReleased(src)`.
- A player who logs in with time remaining is teleported back and the release is
  rescheduled (unless an external prison is started); an expired sentence is
  released at login.
- There is no countdown UI; build one on `getRemaining`.

## Commands

| Command | Permission | Effect |
| --- | --- | --- |
| `/jail id minutes [reason]` | `admin` | `jailPlayer(id, minutes, reason)`. |
| `/unjail id` | `admin` | `release(id)`. |
