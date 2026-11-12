---
title: "Commands"
sidebar_position: 4
---


# Commands

Commands registered by Kora Core. The jail and language commands are native. The 20 stock qb-core commands are registered by the compatibility layer unless `Config.compat.defaultCommands` is `false`; a command whose name is already taken by another resource is left alone and a warning is printed. Every non-`user` default command is audited under the `admin` log category and re-checks its permission inside the handler.

## Built-in commands

### `/jail <id> <minutes> <reason...>`

Jails an online player: stores `metadata.jailed` (release time as a Unix timestamp), teleports them to `Config.jail.coords` and schedules the release. If a resource listed in `Config.jail.deferToResources` is started, it only fires `kora_core:server:onJailRequest` and does nothing else.

| Field | Details |
| --- | --- |
| Context | In-game or console · server command |
| Arguments | id — player server id (number). minutes — sentence length, must be positive. reason — all remaining words. All three are required: the command is registered with `argsRequired = true`, so fewer than three arguments answers "Missing arguments for /jail" even though the help text calls the reason optional. A non-numeric id or minutes returns silently. |
| Access | `admin` (ACE `command.jail` plus `hasPermission`). Source 0 (console) always passes. |

**Example**

```text
/jail 12 10 robbery
/jail 7 30 reckless driving
```

**Result**

The target is teleported to the prison yard and locked for the duration. `kora_core:server:playerJailed (src, minutes, reason)` fires.

### `/unjail <id>`

Releases a jailed player: zeroes `metadata.jailed` and `metadata.injail`, sends `kora_core:client:jailRelease` and fires `kora_core:server:playerReleased`.

| Field | Details |
| --- | --- |
| Context | In-game or console · server command |
| Arguments | id — player server id (number). A non-numeric id returns silently. |
| Access | `admin`. |

**Example**

```text
/unjail 12
```

**Result**

The player is released. Nothing happens if they were not jailed.

### `/language`

Opens the language selector menu (Kora Lib NUI). The chosen language is saved by Kora Lib in the client's key-value storage and applied immediately. `+language` does the same on key press; `-language` does nothing.

| Field | Details |
| --- | --- |
| Context | In-game · client command |
| Arguments | None. |
| Access | Everyone. The key binding defaults to `Config.locales.defaultKey` (`F10`); an empty string means no default key. Players can rebind it under Settings, Key Bindings, FiveM. |

**Example**

```text
/language
```

**Result**

A menu lists the available languages; selecting one shows a success or error notification.

### `/tp <id | x y z | location>`

Teleports the admin to a player (by id), to a named entry of `QBCore.Shared.Locations`, or to coordinates (optional fourth argument is the heading).

| Field | Details |
| --- | --- |
| Context | In-game · server command (compat default) |
| Arguments | id/x — player id, location name or X. y, z — coordinates (commas are stripped). Fewer than the needed arguments answers "Not every argument has been entered (x, y, z)". |
| Access | `admin`. Players only (the console is told to use the command in game). |

**Example**

```text
/tp 7
/tp 195.1 -933.7 30.7 144
/tp legion
```

**Result**

The admin is teleported. "Player not online" or "Location does not exist" otherwise.

### `/tpm`

Teleports the admin to their map waypoint (`QBCore:Command:GoToMarker`).

| Field | Details |
| --- | --- |
| Context | In-game · server command (compat default) |
| Arguments | None. |
| Access | `admin`. |

**Example**

```text
/tpm
```

**Result**

The admin is teleported to the marker.

### `/togglepvp`

Flips `QBCore.Config.Server.PVP` and broadcasts `QBCore:Client:PvpHasToggled` to everyone. Players who join while PVP is off are told on load.

| Field | Details |
| --- | --- |
| Context | Server command (compat default) |
| Arguments | None. |
| Access | `admin`. |

**Example**

```text
/togglepvp
```

**Result**

Replies "PVP enabled" or "PVP disabled".

### `/addpermission <id> <permission>`

Grants a permission principal to an online player through `addPermission` and refreshes their command list.

| Field | Details |
| --- | --- |
| Context | Server command (compat default) |
| Arguments | id — online player id. permission — one of `Config.Server.Permissions` (`god`, `admin`, `mod`); anything else is refused. |
| Access | `god`. |

**Example**

```text
/addpermission 12 mod
```

**Result**

Replies "Granted mod permission to player 12".

### `/removepermission <id> <permission>`

Removes a permission principal from an online player through `removePermission`.

| Field | Details |
| --- | --- |
| Context | Server command (compat default) |
| Arguments | id — online player id. permission — one of `god`, `admin`, `mod`. |
| Access | `god`. |

**Example**

```text
/removepermission 12 mod
```

**Result**

Replies "Removed mod permission from player 12".

### `/openserver`

Clears the closed flag so everyone can connect again.

| Field | Details |
| --- | --- |
| Context | Server command (compat default) |
| Arguments | None. |
| Access | `admin` (a caller without it is kicked). |

**Example**

```text
/openserver
```

**Result**

Replies "The server has been opened" or "The server is already open".

### `/closeserver [reason...]`

Closes the server: sets the closed flag and reason, kicks every online player who lacks the whitelist permission, and refuses new connections from players without it.

| Field | Details |
| --- | --- |
| Context | Server command (compat default) |
| Arguments | reason? — free text, up to 200 characters. Defaults to "No reason specified". |
| Access | `admin`. The whitelist permission is `Config.Server.WhitelistPermission` (`admin`). |

**Example**

```text
/closeserver restart in 5 minutes
```

**Result**

Replies "The server has been closed".

### `/car <model>`

Spawns a server-owned networked vehicle at the admin's feet, deletes the vehicle they were sitting in, and gives keys through `kora_vehiclekeys` when it is started.

| Field | Details |
| --- | --- |
| Context | In-game · server command (compat default) |
| Arguments | model — letters, digits and underscores only, at most 32 characters. |
| Access | `admin`. Players only. |

**Example**

```text
/car adder
```

**Result**

The vehicle appears and the admin is warped in. "Incorrect format" or "Unable to spawn that vehicle" otherwise.

### `/dv`

Deletes the vehicle the admin is in, or every vehicle within 5.0 m when on foot.

| Field | Details |
| --- | --- |
| Context | In-game · server command (compat default) |
| Arguments | None. |
| Access | `admin`. Players only. |

**Example**

```text
/dv
```

**Result**

The vehicles are removed; the count is written to the audit log.

### `/dvall, /dvp, /dvo`

Deletes every vehicle (`dvall`), every non-player ped (`dvp`) or every object (`dvo`) on the server.

| Field | Details |
| --- | --- |
| Context | Server command (compat default) |
| Arguments | None. |
| Access | `admin`. |

**Example**

```text
/dvall
```

**Result**

Replies "Deleted N entities".

### `/givemoney <id> <moneytype> <amount>`

Adds money to an online player with reason `Admin give money`. Not taxed (`ignoreTax = true`).

| Field | Details |
| --- | --- |
| Context | Server command (compat default) |
| Arguments | id — online player id. moneytype — one of `Config.money.types` (`cash`, `bank`, `crypto`). amount — a finite number. |
| Access | `admin`. |

**Example**

```text
/givemoney 12 bank 5000
```

**Result**

Silent on success. On failure replies "Could not give money: &lt;reason>".

### `/setmoney <id> <moneytype> <amount>`

Sets an account balance with reason `Admin set money`.

| Field | Details |
| --- | --- |
| Context | Server command (compat default) |
| Arguments | Same as `/givemoney`. |
| Access | `admin`. |

**Example**

```text
/setmoney 12 cash 0
```

**Result**

Silent on success. On failure replies "Could not set money: &lt;reason>", for example `below account floor`.

### `/job, /gang`

Shows the caller's own job (label, grade name, duty) or gang (label, grade name).

| Field | Details |
| --- | --- |
| Context | In-game · server command (compat default) |
| Arguments | None. |
| Access | Everyone. |

**Example**

```text
/job
```

**Result**

A notification such as "Job: Police | Grade: Officer | Duty: true".

### `/setjob <id> <job> <grade>, /setgang <id> <gang> <grade>`

Sets a player's job or gang. The grade argument is zero-based as in stock qb-core and is converted to Kora's one-based grades.

| Field | Details |
| --- | --- |
| Context | Server command (compat default) |
| Arguments | id — online player id. job / gang — name (letters, digits, `_`, `-`). grade — whole number, 0 or more. |
| Access | `admin`. |

**Example**

```text
/setjob 12 police 2
/setgang 12 ballas 0
```

**Result**

Silent on success. "Player not online", "Incorrect format" or "Could not set job: &lt;reason>" on failure.

### `/ooc <message...>`

Out-of-character chat to everyone within 20.0 m. Admins who have opted in and are farther away see it as "Proximity OOC" and it is logged.

| Field | Details |
| --- | --- |
| Context | In-game · server command (compat default) |
| Arguments | message — free text, up to 255 characters. An empty message answers "All arguments must be filled out!". |
| Access | Everyone. |

**Example**

```text
/ooc anyone know a good mechanic?
```

**Result**

A chat line `OOC | <name>: <message>` for nearby players.

### `/me <message...>`

Shows a floating 3D text above the player to everyone within 20.0 m (`QBCore:Command:ShowMe3D`). Colour codes like `~r~` are stripped.

| Field | Details |
| --- | --- |
| Context | In-game · server command (compat default) |
| Arguments | message — free text, up to 255 characters. |
| Access | Everyone. Players only. |

**Example**

```text
/me waves hello
```

**Result**

The text appears above the player for nearby players.

## How commands are protected

Commands registered through `addCommand` use `RegisterCommand(name, handler, false)`, so FiveM's own ACE check is bypassed and Kora Core checks the permission level itself: source 0 always passes, a denial notifies "You do not have permission for this command.", and a missing argument notifies "Missing arguments for /&lt;name>" when `argsRequired` is set. The legacy path `QBCore:CallCommand` checks the `command.<name>` ACE only, which is why the compat default commands check the permission level again in the handler.

## Add your own

Use `exports.kora_core:addCommand(name, help, args, argsRequired, handler, permission)`. The command is owned by the calling resource and removed when it stops. See the Permissions, commands and logging module.

## Quick reference (code-derived)

Permission levels are checked with `hasPermission` (ACE objects `kora_core.<level>`,
`group.<level>` or `command.<level>`); see
[Permissions](./api/permissions.md). The server console
(source 0) passes every permission check.

### kora_core commands

| Command | Realm | Arguments | Permission | Effect |
| --- | --- | --- | --- | --- |
| `/jail` | server | `id minutes [reason]` | `admin` | Jails the player (or hands off to an external prison). See [Jail](./api/jail.md). |
| `/unjail` | server | `id` | `admin` | Releases a player jailed by kora_core. |
| `/language` | client | none | everyone | Opens the language selector. |

### Key mappings

| Mapping | Command | Default key | Effect |
| --- | --- | --- | --- |
| Open language selector | `+language` | `Config.locales.defaultKey` (`F10`) | Opens the language selector. Players can rebind it in Settings, Key Bindings, FiveM. |

### Stock qb-core commands

With `Config.compat.defaultCommands = true` (default), kora_core registers the 20
commands from qb-core's `server/commands.lua` through `QBCore.Commands.Add`. A name
already registered by another resource when kora_core loads is skipped.

| Command | Arguments | Permission | Effect |
| --- | --- | --- | --- |
| `/tp` | `id` or `x y z [heading]` or a location name | `admin` | Teleport to a player, coordinates or a `QBCore.Shared.Locations` entry. |
| `/tpm` | none | `admin` | Teleport to the map waypoint. |
| `/togglepvp` | none | `admin` | Toggle `QBCore.Config.Server.PVP` for everyone. |
| `/addpermission` | `id permission` | `god` | Grant `god`, `admin` or `mod` for the session. |
| `/removepermission` | `id permission` | `god` | Revoke a level. |
| `/openserver` | none | `admin` | Reopen a closed server. |
| `/closeserver` | `[reason]` | `admin` | Close the server; kicks and refuses players without the whitelist permission (`admin`). |
| `/car` | `model` | `admin` | Spawn a server-owned networked vehicle and warp in. |
| `/dv` | none | `admin` | Delete the occupied vehicle, or vehicles within 5 m. |
| `/dvall` | none | `admin` | Delete all vehicles. |
| `/dvp` | none | `admin` | Delete all non-player peds. |
| `/dvo` | none | `admin` | Delete all objects. |
| `/givemoney` | `id moneytype amount` | `admin` | `addMoney`, untaxed. |
| `/setmoney` | `id moneytype amount` | `admin` | `setMoney`. |
| `/job` | none | `user` | Show your job. |
| `/gang` | none | `user` | Show your gang. |
| `/setjob` | `id job grade` | `admin` | Set a job (zero-based grade, like stock). |
| `/setgang` | `id gang grade` | `admin` | Set a gang (zero-based grade). |
| `/ooc` | `message` | `user` | Proximity OOC chat (20 m); opted-in admins see it everywhere. |
| `/me` | `message` | `user` | 3D text above you for players within 20 m. |

Validation, logging and differences from stock are documented on
[Default qb-core commands](./default-commands.md).

### Chat behaviour

A server `chatMessage` handler cancels chat messages that start with `/`, so typed
commands are not echoed to chat.
