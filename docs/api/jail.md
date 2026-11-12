---
title: "Jail"
sidebar_position: 9
---


# Jail

## Server

A minimal built-in jail. `jailPlayer` stores a release timestamp in the player's metadata, teleports them to `Config.jail.coords` and starts a server timer; the client holds them inside a 30 m containment sphere until release. If a real prison resource listed in `Config.jail.deferToResources` is running, core steps aside completely and only announces the request through an event.

Namespace: `exports.kora_core` · Source: `modules/jail/server.lua`

### How it works

The sentence is stored as a UNIX release timestamp in `metadata.jailed` (0 means not jailed), mirrored into `metadata.injail` for legacy scripts. It survives relogs: on `kora_core:server:playerLoaded` an active sentence is re-applied. The exports can be called by any resource with no permission check (the `/jail` and `/unjail` commands require `admin`). The release timer is an in-memory `SetTimeout` that is not persisted; it is re-created at login and checks that the stored timestamp still matches before releasing.

### Config.jail

Pass an options table as the final argument to a play function. Omit the table or any field to use its default. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `deferToResources?` | string[] | Resource names checked in order with `GetResourceState`. The first one that is `started` receives the request and core does nothing else. Default `{ 'xt-prison', 'qbx_prison' }`. |
| `coords?` | vector4 | Jail location sent to the client (x, y, z are used, the heading is not). Default `vector4(1651.86, 2570.13, 45.56, 22.0)` (Bolingbroke Penitentiary yard). |

### Commands

`/jail <id> <minutes> <reason...>` (permission `admin`) and `/unjail <id>` (permission `admin`) are registered through `Core.commands.addCommand`. Both are registered with `argsRequired = true`, which means all declared arguments must be supplied: `/jail` needs three words after the command (id, minutes and at least one word of reason), although the help text calls the reason optional; with fewer the sender gets the notification `Missing arguments for /jail`. A non-numeric id or minutes is silently ignored. The reason is everything from the third argument on, joined with spaces. Both commands call the exports and show nothing on failure.

### Events

Local server events: `kora_core:server:onJailRequest(src, minutes, reason, resourceName)` when a prison resource takes over; `kora_core:server:playerJailed(src, minutes, reason)` after core jails a player; `kora_core:server:playerReleased(src)` after core releases a player. Client events sent by core: `kora_core:client:jailTeleport(coords, remainingSeconds)` (on jailing and on relog) and `kora_core:client:jailRelease()`.

### Relogin handling

When a character loads with `metadata.jailed ~= 0`: if any `deferToResources` resource is started, nothing happens (that resource owns rejoin handling). Otherwise, if the sentence has run out core calls `release`; if not it re-sends `kora_core:client:jailTeleport` with the remaining seconds and reschedules the release timer.

### Functions

Functions exported by this realm.

#### `exports.kora_core:jailPlayer(src, minutes, reason?)`

Jails an online player. If a deferral resource is started it only fires `kora_core:server:onJailRequest` and returns `true` without jailing. Otherwise it sets `metadata.jailed` and `metadata.injail` to `os.time() + floor(minutes * 60)` (replacing any earlier sentence), sends the teleport event, fires `kora_core:server:playerJailed` and schedules the release.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `minutes` | number | Sentence length in minutes (fractions allowed; converted with floor of seconds). |
| `reason?` | string | Free text passed to the events. |

**Returns**

- **true** — jailed, or handed to a deferral resource (core applies nothing in that case).
- **false** — second return value is the reason: 'no such player'.
- **false, 'minutes must be positive'** — not a number or not above 0.

**Example**

```lua
local ok, err = exports.kora_core:jailPlayer(targetSrc, 10, 'Armed robbery')
if not ok then print(('jail failed: %s'):format(err)) end
```

**Representative console output**

```text
true  -- kora_core:client:jailTeleport(Config.jail.coords, 600)
```

#### `exports.kora_core:release(src)`

Releases a player jailed by core: resets `metadata.jailed` and `metadata.injail` to 0, sends `kora_core:client:jailRelease` and fires `kora_core:server:playerReleased`. It does not release players held by an external prison resource. Note the generic export name: it is `exports.kora_core:release`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |

**Returns**

- **true** — released.
- **false** — player not loaded, or not currently jailed by core (no reason string).

**Example**

```lua
if exports.kora_core:release(targetSrc) then
    print('released')
end
```

**Representative console output**

```text
released
```

#### `exports.kora_core:getRemaining(src)`

Seconds left on the sentence.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |

**Returns**

- **seconds** — integer (greater than 0) while a sentence is active.
- **0** — not jailed, expired but not yet released, or player not loaded.

**Example**

```lua
local left = exports.kora_core:getRemaining(src)
print(('%d seconds left'):format(left))
```

**Representative console output**

```text
412 seconds left
```

#### `exports.kora_core:isJailed(src)`

Whether the player has time remaining on a core sentence (`getRemaining(src) > 0`).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |

**Returns**

- **true** — active sentence.
- **false** — otherwise (including players held by an external prison).

**Example**

```lua
if exports.kora_core:isJailed(src) then return end
```

**Representative console output**

```text
false
```

### Common use cases

- A police resource sentences a player with `jailPlayer` and later checks `isJailed` before allowing actions.
- Dropping in xt-prison or qbx_prison without changing callers: `jailPlayer` forwards the request through `kora_core:server:onJailRequest`.
- An admin releases a player with `/unjail`.

### Limits and related APIs

The writes to `metadata.jailed` and `metadata.injail` are not checked: if one is refused (for example `player data is busy`) the teleport and events still happen. `jailPlayer` does not stop an existing sentence, it replaces it. The release timer is lost on a kora_core restart until the player next loads. External prison resources own their own release flow.

### Related guides

- [Sentence state lives in metadata](./metadata.md)
- [Player lifecycle events](./player.md)
- [Jail events](./events.md)
- [Config.jail](./configuration.md)

## Client

Renders the containment for a core jail sentence. It has no exports.

Namespace: `exports.kora_core` · Source: `modules/jail/client.lua`

### How it works

`kora_core:client:jailTeleport(coords, remainingSeconds)` clears any existing containment, teleports the ped to `coords`, creates a `Kora.zones.sphere` of radius 30.0 m (hard-coded) around it whose exit callback teleports the ped straight back, and shows an error notification `You have been jailed for N minutes.` with N = ceil(remainingSeconds / 60). `kora_core:client:jailRelease` removes the zone and shows `You have been released.`. The zone is also removed on `QBCore:Client:OnPlayerUnload`. There is no countdown UI or movement lock; a resource that wants one can read `exports.kora_core:getRemaining` on the server and send the value to its own UI. Both events are plain `RegisterNetEvent` handlers.

### Related guides

- [Jail events](./events.md)

## Implementation notes and quick reference

A minimal built-in jail: teleport, a 30 m containment sphere and a timed release.
If a dedicated prison resource from `Config.jail.deferToResources` is started,
kora_core hands the request to it instead.

### Server API

| Export | Returns | Description |
| --- | --- | --- |
| `jailPlayer(src, minutes, reason)` | `true` or `false, err` | Jails for a positive number of minutes, or defers to an external prison. Errors: `no such player`, `minutes must be positive`. |
| `release(src)` | boolean | Releases a player jailed by kora_core. `false` if not jailed by it. |
| `getRemaining(src)` | integer | Seconds left, `0` if not jailed or expired. |
| `isJailed(src)` | boolean | `getRemaining(src) > 0`. |

```lua
exports.kora_core:jailPlayer(targetSource, 15, 'Assault on an officer')
```

### Behaviour

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

### Commands

| Command | Permission | Effect |
| --- | --- | --- |
| `/jail id minutes [reason]` | `admin` | `jailPlayer(id, minutes, reason)`. |
| `/unjail id` | `admin` | `release(id)`. |
