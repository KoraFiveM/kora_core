# development module guide

## Purpose
Runtime, per-player conveniences for development and testing. The server export
owns activation state; the client makes the selected player's ped invincible
and applies the configured fast walk rate, while the server-owned needs module
skips passive hunger/thirst decay for that player.

## Public API
- `Core.development.setDevMode(src, enabled)` (server) — activate/deactivate one
  loaded player; returns `(true)` or `(false, err)`.
- `Core.development.isDevMode(src)` (server) — read one player's state.
- `Core.development.isDevMode()` (client) — read the local player's state.

## Implementation notes
- **Ephemeral and per-player.** State lives only for the connection and is
  cleared on player drop or kora_core restart. It is never persisted in PlayerData.
- **One activation path.** Server resources call the `setDevMode` export; the
  core sends its internal client event and re-announces state after character
  switches. Client resources do not own an activation export.
- **The movement override is frame-scoped.** `_tick` re-applies
  `SetPedMoveRateOverride` every frame. The default `1.75` matches the fast move
  rate used by FiveM's bundled txAdmin player mode.
- **Ped swaps are cleaned up.** When a respawn/model change yields a new local
  ped, the old ped is restored before the new ped receives the overrides.
  Resource teardown restores both invincibility and the normal `1.0` move rate.
- **Needs remain server-owned.** `modules/needs/server.lua` skips only active
  sources rather than having the client forge or continuously refill metadata.
  Direct metadata changes from consumables or other resources still work.
- **`Core.development._tick` is internal.** Its underscore prefix keeps it out
  of the flat export namespace while allowing deterministic smoke coverage.

## Best practices
- Permission-gate any UI/command that calls `setDevMode`; core exposes the
  capability but does not decide who is an administrator.
- Keep developer-only ped natives here so the production paths remain inert
  when the mode is disabled.
