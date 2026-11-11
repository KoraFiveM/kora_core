---
title: Commands
sidebar_position: 4
---

# Commands

Permission levels are checked with `hasPermission` (ACE objects `kora_core.<level>`,
`group.<level>` or `command.<level>`); see
[Permissions](./features/permissions-commands-logging.md). The server console
(source 0) passes every permission check.

## kora_core commands

| Command | Realm | Arguments | Permission | Effect |
| --- | --- | --- | --- | --- |
| `/jail` | server | `id minutes [reason]` | `admin` | Jails the player (or hands off to an external prison). See [Jail](./features/jail.md). |
| `/unjail` | server | `id` | `admin` | Releases a player jailed by kora_core. |
| `/language` | client | none | everyone | Opens the language selector. |

## Key mappings

| Mapping | Command | Default key | Effect |
| --- | --- | --- | --- |
| Open language selector | `+language` | `Config.locales.defaultKey` (`F10`) | Opens the language selector. Players can rebind it in Settings, Key Bindings, FiveM. |

## Stock qb-core commands

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

## Chat behaviour

A server `chatMessage` handler cancels chat messages that start with `/`, so typed
commands are not echoed to chat.
