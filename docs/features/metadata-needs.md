---
title: Metadata, needs and development mode
sidebar_position: 6
---

# Metadata, needs and development mode

## Metadata

`PlayerData.metadata` holds hunger, thirst, stress, armor, death and jail state,
licences and any custom keys. All functions are server-side.

| Export | Returns | Description |
| --- | --- | --- |
| `getMetaData(src, key)` | value | One key, or the live metadata table when `key` is `nil` (treat as read-only). `nil` for an unknown player. |
| `setMetaData(src, key, value)` | `true` or `false, err` | Writes through the funnel and fires `QBCore:Server:OnMetaDataChange(src, key, value)`. Errors: `no such player`, `metadata key must be a string`. |
| `incrementMetaData(src, key, delta, min, max)` | new value or `nil, err` | Adds `delta` to the numeric value (missing or non-numeric counts as 0), clamps to `min`/`max` when given, writes and fires `OnMetaDataChange`. |

```lua
local hunger = exports.kora_core:incrementMetaData(source, 'hunger', -5, 0, 100)
exports.kora_core:setMetaData(source, 'isdead', true)
```

Clients can only write metadata through the legacy `QBCore:Server:SetMetaData`
event, and only keys allowed by `Config.compat.clientMetadataKeys` (default
hunger, thirst and stress, numeric and clamped to 0..100). `starterItems` is always
refused.

## Needs

A server loop started with the resource runs every `Config.needs.tickInterval` and,
for each loaded player not in development mode:

- lowers hunger by `Config.needs.hungerDecay` and thirst by `Config.needs.thirstDecay`
  (clamped to 0..100);
- sends `hud:client:UpdateNeeds(hunger, thirst)` to that player.

Stress is never decayed automatically. Errors in a tick are printed and do not stop
the loop.

On the client, each replicated hunger or thirst update whose value is 0 applies
`Config.needs.hungerDamage` or `Config.needs.thirstDamage` to the ped with
`ApplyDamageToPed`. No damage is applied while the ped is dead, while
`metadata.isdead` or `metadata.inlaststand` is true, or in development mode.

| Export | Description |
| --- | --- |
| `startNeedsDecay()` | Start the loop (no-op if running). Called automatically on start. |
| `stopNeedsDecay()` | Stop the loop. |
| `reset(src)` | Set hunger and thirst to 100 and stress to 0 (for respawn/heal flows; kora_core does not hook death itself). |

The legacy `hud:server:GainStress` and `hud:server:RelieveStress` events change
stress for the sender; see [Compatibility](../compatibility.md#stress-events).

## Development mode

Development mode is an ephemeral per-player state, enabled only from the server so
the calling resource can enforce its own permission policy:

```lua
-- server, after your own permission check
local ok, err = exports.kora_core:setDevMode(source, true)
local enabled = exports.kora_core:isDevMode(source)
exports.kora_core:setDevMode(source, false)
```

```lua
-- client
local enabled = exports.kora_core:isDevMode()
```

While it is enabled for a player:

- the player's ped is invincible;
- stamina is restored every frame;
- the walk rate is overridden with `Config.development.walkSpeed` every frame;
- the needs tick skips the player and zero-need damage is not applied.

Explicit metadata changes from other resources still apply. Disabling restores the
normal move rate and invincibility immediately. The state is cleared on disconnect
and on a kora_core restart, is re-sent to the client at login, and is never
persisted.

`setDevMode(src, enabled)` returns `false, 'player is not loaded'` or
`false, 'enabled must be a boolean'` on bad input. Each change fires the server
event `kora_core:server:devModeChanged(src, enabled)` and the client event
`kora_core:client:devModeChanged(enabled)`.
