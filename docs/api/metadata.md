---
title: "Metadata, needs and development mode"
sidebar_position: 5
---


# Metadata, needs and development mode

## Server

Three small server systems. Metadata is the free-form `PlayerData.metadata` table (hunger, thirst, stress, jailed, licences, ...) with get, set and clamped increment. Needs is the server-owned clock that decays hunger and thirst. Development mode is an ephemeral per-player flag that makes the client invincible and fast and pauses needs decay. Metadata writes go through `Core.player.setPath`, so they persist and replicate like other PlayerData.

Namespace: `exports.kora_core` · Source: `modules/metadata/server.lua, modules/needs/server.lua, modules/development/server.lua`

### How it works

All exports run on the server and can be called by any resource. The metadata exports have no key allow-list on the server side: a key is any string. The legacy client-writable path (`QBCore:Server:SetMetaData`) is restricted separately by `Config.compat.clientMetadataKeys`, which defaults to `hunger`, `thirst` and `stress` (numeric, clamped to 0..100); that rule lives in the compat layer, not in this module. `setDevMode` has no permission or resource check: gate it in the calling resource.

### Terms used on this page

| Term | Meaning |
| --- | --- |
| Metadata defaults | A new character starts with `hunger = 100, thirst = 100, stress = 0, armor = 0, isdead = false, inlaststand = false, ishandcuffed = false, jailed = 0, injail = 0, licences = { driver = true, weapon = false }, phone = {}, bloodtype = 'O+'` plus a generated `fingerprint` and `walletid`. |
| Needs decay | The server subtracts `Config.needs.hungerDecay` and `thirstDecay` every `Config.needs.tickInterval` ms and clamps to 0..100. Stress is deliberately not decayed. |
| Development mode | Ephemeral state held per source in memory. It is not persisted, is cleared when the player drops and is re-announced to the client on every `kora_core:server:playerLoaded` (a character switch keeps the same source). |

### Config.needs and Config.development

Defined in config.lua. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `Config.needs.tickInterval?` | number (ms) | Time between hunger/thirst decay ticks. Default 60000. Read before each wait. |
| `Config.needs.hungerDecay?` | number | Hunger removed per tick. Default 1. |
| `Config.needs.thirstDecay?` | number | Thirst removed per tick. Default 1. |
| `Config.needs.hungerDamage?` | number (health) | Damage the client applies to the ped on each replicated hunger update while hunger is 0. Default 5. 0 or below disables. Read once when the client script loads. |
| `Config.needs.thirstDamage?` | number (health) | Same for thirst. Default 5. Stacks with hunger damage when both are 0. |
| `Config.development.walkSpeed?` | number (multiplier) | Value passed each frame to `SetPedMoveRateOverride` while development mode is active (1.0 is normal speed). Default 1.75. Must be a positive number or the client script asserts at load. Read once at load. |

### Events

`QBCore:Server:OnMetaDataChange(src, key, value)` is a local server event fired after every successful `setMetaData` and `incrementMetaData`, even if the value did not change. `hud:client:UpdateNeeds(hunger, thirst)` is sent to a player after each decay tick with the post-decay values, to keep stock qb-hud bars moving (values are nil if the increment failed). `kora_core:client:setDevMode(enabled)` is sent to the client when development mode changes and again when a character loads. `kora_core:server:devModeChanged(src, enabled)` is a local server event fired when development mode actually changes.

### Needs loop

The decay loop starts automatically when kora_core starts. Each tick, for every loaded player not in development mode, core calls `incrementMetaData` for hunger and thirst with the configured negative delta clamped to 0..100, then sends `hud:client:UpdateNeeds`. The tick runs inside a pcall; errors are printed as `[kora_core:needs] tick errored: ...`. On the client, hunger/thirst deltas at or below 0 apply `ApplyDamageToPed(ped, damage, false)`, except in development mode, with a dead ped, or when `metadata.isdead` or `metadata.inlaststand` is true.

### Development mode client behaviour

While active the client sets the ped invincible, applies `SetPedMoveRateOverride` with `Config.development.walkSpeed` and refills stamina every frame, and restores invincibility off and move rate 1.0 when it ends, when the ped changes and when the resource stops. The local client event `kora_core:client:devModeChanged(enabled)` is fired on change. The client event `kora_core:client:setDevMode` is a plain `RegisterNetEvent` with no source guard, so a client script can switch its own client-side effects on locally; the server flag, and therefore the needs pause, only changes through `setDevMode`.

### Functions

Functions exported by this realm.

#### `exports.kora_core:getMetaData(src, key?)`

Reads one metadata value, or the whole metadata table.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `key?` | string | Metadata key. When nil the whole table is returned. |

**Returns**

- **value** — the stored value for that key.
- **metadata** — the whole metadata table when `key` is nil.
- **nil** — player not loaded, or the key is not set.

**Example**

```lua
local hunger = exports.kora_core:getMetaData(src, 'hunger')
if hunger and hunger < 20 then print('hungry') end
```

**Representative console output**

```text
85
```

#### `exports.kora_core:setMetaData(src, key, value)`

Writes a metadata value and fires `QBCore:Server:OnMetaDataChange(src, key, value)`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `key` | string | Metadata key. |
| `value` | any | New value (must be serialisable to persist). |

**Returns**

- **true** — written.
- **false** — second return value is the reason: 'no such player'.
- **false** — second return value is the reason: 'metadata key must be a string'.
- **false, &lt;setPath reason>** — e.g. 'player logout is in progress', 'player data is busy'.

**Example**

```lua
local ok, err = exports.kora_core:setMetaData(src, 'callsign', 'A-12')
if not ok then print(err) end
```

**Representative console output**

```text
true
```

#### `exports.kora_core:incrementMetaData(src, key, delta, min?, max?)`

Adds `delta` to a numeric metadata value, clamps it and writes it. A missing or non-numeric current value counts as 0 and a non-numeric `delta` counts as 0. `min` is applied first and `max` second, so `max` wins if `min` is above it. Fires `QBCore:Server:OnMetaDataChange` with the new value.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `key` | string | Metadata key. |
| `delta` | number | Amount to add (negative to subtract). |
| `min?` | number | Lower clamp. |
| `max?` | number | Upper clamp. |

**Returns**

- **newValue** — the stored number after clamping.
- **nil** — second return value is the reason: 'no such player'.
- **nil, &lt;setPath reason>** — the write was refused.

**Example**

```lua
-- a stressful event: +10 stress, never above 100
local stress = exports.kora_core:incrementMetaData(src, 'stress', 10, 0, 100)
```

**Representative console output**

```text
30
```

#### `exports.kora_core:startNeedsDecay()`

Starts the server hunger/thirst decay loop (it already starts with kora_core). Calling it while running is a no-op.

**Parameters**



**Returns**

- **nil** — no return value.

**Example**

```lua
exports.kora_core:startNeedsDecay()
```

**Representative console output**

```text
nil
```

#### `exports.kora_core:stopNeedsDecay()`

Stops the decay loop. The sleeping thread exits at its next wake-up without running another tick.

**Parameters**



**Returns**

- **nil** — no return value.

**Example**

```lua
-- freeze needs during a scripted scene
exports.kora_core:stopNeedsDecay()
```

**Representative console output**

```text
nil
```

#### `exports.kora_core:reset(src)`

Resets one player's hunger and thirst to 100 and stress to 0 (the legacy `hospital:server:resetHungerThirst` behaviour). Call it from a respawn or heal flow; core does not hook death itself. Each key is written through `setMetaData`, so `OnMetaDataChange` fires three times. Failures are ignored. Note the generic export name: it is `exports.kora_core:reset`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |

**Returns**

- **nil** — no return value, even if the player is not loaded or a write was refused.

**Example**

```lua
AddEventHandler('myems:server:revived', function(src)
    exports.kora_core:reset(src)
end)
```

**Representative console output**

```text
nil
```

#### `exports.kora_core:isDevMode(src)`

Whether development mode is on for a player (server state).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |

**Returns**

- **enabled** — boolean, false when off or unknown.

**Example**

```lua
if exports.kora_core:isDevMode(src) then return end
```

**Representative console output**

```text
false
```

#### `exports.kora_core:setDevMode(src, enabled)`

Turns development mode on or off for a loaded player. On a change it sends `kora_core:client:setDevMode(enabled)` to the client and fires the local event `kora_core:server:devModeChanged(src, enabled)`; setting the current value again returns `true` and does nothing. There is no permission check and no resource restriction: any server resource can call it, so protect your own callers (for example with an ace check).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. Must be a number of a loaded player. |
| `enabled` | boolean | Strictly a boolean. |

**Returns**

- **true** — applied, or already in that state.
- **false, 'player is not loaded'** — src is not a number or has no loaded character.
- **false** — second return value is the reason: 'enabled must be a boolean'.

**Example**

```lua
RegisterCommand('devmode', function(src, args)
    if src == 0 or not IsPlayerAceAllowed(src, 'command.devmode') then return end
    local ok, err = exports.kora_core:setDevMode(src, args[1] == 'on')
    if not ok then print(err) end
end, false)
```

**Representative console output**

```text
true
```

### Common use cases

- Storing small per-character flags such as a callsign or custom status in metadata.
- Applying stress from a job script with a clamped `incrementMetaData`.
- Resetting needs after a hospital respawn with `reset`.
- Pausing needs decay and making an admin invincible for testing with `setDevMode`.

### Limits and related APIs

Metadata keys on the server are not validated beyond being a string for `setMetaData`; `incrementMetaData` does not even check the key type. `getMetaData` with no key returns the whole table, which is serialised across the export boundary. Development state is per source in memory and is not cleared on character unload, only on drop. Client damage is applied per replicated update, not per tick of the server clock.

### Related guides

- [PlayerData and setPath](./player.md)
- [Jail stores state in metadata](./jail.md)
- [Client mirror of metadata](./replication.md)
- [Metadata and hud events](./events.md)
- [Config.needs, Config.development, Config.compat](./configuration.md)

## Client

Client half of needs and development mode. It applies the physical consequences of server-owned state and exposes the local development flag. It never decides decay or the mode itself.

Namespace: `exports.kora_core` · Source: `modules/needs/client.lua, modules/development/client.lua`

### How it works

Needs: subscribes to `metadata.hunger` and `metadata.thirst` changes in the replicated PlayerData and damages the ped when a value is at or below 0 (see the server realm for conditions). Development: `kora_core:client:setDevMode(enabled)` toggles invincibility, `Config.development.walkSpeed` movement rate and per-frame stamina refill, and fires the local event `kora_core:client:devModeChanged(enabled)`. The effects are local natives, so they are not enforced by the server.

### Functions

Functions exported by this realm.

#### `exports.kora_core:isDevMode()`

Whether development mode is active on this client.

**Parameters**



**Returns**

- **enabled** — boolean, true while the client effects are running.

**Example**

```lua
if exports.kora_core:isDevMode() then
    return -- skip fall damage and similar while testing
end
```

**Representative console output**

```text
false
```

### Related guides

- [Replicated metadata](./replication.md)
- [Client PlayerData access](./player.md)

## Implementation notes and quick reference

### Metadata

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

### Needs

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
stress for the sender; see [Compatibility](./compatibility.md#stress-events).

### Development mode

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
