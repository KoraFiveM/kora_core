---
title: Default qb-core commands
sidebar_position: 7
---

# Stock qb-core default commands

`compat/server/qb-commands.lua` registers the 20 commands of qb-core's
`server/commands.lua` through `QBCore.Commands.Add`, so they behave like any other
legacy command (owner tracking, chat suggestions, `command.<name>` ACE,
`QBCore:CallCommand`, `QBCore:Server:PreCommandExecution`).

Turn the whole set off with `Config.compat.defaultCommands = false` (default
`true`).

| Command | Level | What it does here |
| --- | --- | --- |
| `/tp [id or x y z or location]` | admin | Teleports through the stock `QBCore:Command:TeleportToPlayer`/`TeleportToCoords` client events; target, location (`QBCore.Shared.Locations`) and coordinates are validated server-side. An optional fourth number is the heading. |
| `/tpm` | admin | `QBCore:Command:GoToMarker`. |
| `/togglepvp` | admin | Flips `QBCore.Config.Server.PVP`, broadcasts `QBCore:Client:PvpHasToggled`, replies to the caller, and tells players who log in while it is off. |
| `/addpermission id level`, `/removepermission id level` | god | `QBCore.Functions.AddPermission`/`RemovePermission`; `level` must be one of `QBCore.Config.Server.Permissions` (`god`, `admin`, `mod`). The target's command suggestions are refreshed. |
| `/openserver`, `/closeserver [reason]` | admin | Flips `QBCore.Config.Server.Closed`; closing kicks everyone without the whitelist permission (`admin`). New connections without it are refused while closed. |
| `/car model` | admin | Spawns a networked vehicle with `QBCore.Functions.SpawnVehicle` on the server, warps the admin in (deleting the vehicle they were in, as stock) and grants keys through `exports.kora_vehiclekeys:giveKeys` when that resource is started. |
| `/dv` | admin | Deletes the occupied vehicle, else vehicles within 5 m. |
| `/dvall`, `/dvp`, `/dvo` | admin | Delete all vehicles, peds or objects. `/dvp` spares player peds (stock would delete them). |
| `/givemoney id type amount` | admin | `addMoney` (untaxed, reason `Admin give money`). |
| `/setmoney id type amount` | admin | `setMoney` (reason `Admin set money`). |
| `/job`, `/gang` | user | Show your job (label, grade, duty) or gang. |
| `/setjob id job grade`, `/setgang id gang grade` | admin | `setJob`/`setGang`; the name is lower-cased and the grade is the stock zero-based number. |
| `/ooc message` | user | Proximity OOC (20 m); opted-in admins see it everywhere (logged through `qb-log:server:CreateLog`). |
| `/me message` | user | `QBCore:Command:ShowMe3D` to players within 20 m. |

There is no `/id` in qb-core's `commands.lua`, so none is registered.

## Behaviour notes

- **Logging.** Every use of a non-`user` command is written with
  `logEvent('admin', source, { command, args, ... })`; state-changing commands
  add the outcome (`ok`, `removed`, target, ...). Denied attempts are logged with
  `denied = true`.
- **Name clashes.** A command already registered when this file loads (for example
  by another resource) is kept and a console line says so. A resource that
  registers the same name later replaces this one. kora_core's own `/jail` and
  `/unjail` do not clash.
- **Hook.** `QBCore.Commands.Add` fires
  `QBCore:Server:PreCommandExecution(source, name, args, rawCommand)` before the
  callback of every legacy command; cancel it with `CancelEvent()`.
  `QBCore:CallCommand` calls the stored callback directly, as stock does, and
  ignores non-table or oversized (more than 16) `args`. Every default command
  re-checks the caller's level with `QBCore.Functions.HasPermission` in its handler,
  so a holder of the per-command ACE who lacks the `admin`/`god` level is refused,
  including through `QBCore:CallCommand`.
- **ACE.** Like stock, `Commands.Add` grants `command.<name>` to
  `kora_core.<level>` (not for `god`/`user`, `QBCore.Commands.IgnoreList`).
  Without that ACE, `QBCore:CallCommand` denies the command.
- **Arguments** are never trusted: IDs must be online integers, money types must be
  configured accounts and amounts finite, model names `[%w_]` with at most 32
  characters, coordinates finite, and `/setjob`/`/setgang` grades whole numbers of
  0 or more (a missing or invalid grade is rejected, not defaulted). The console
  (source 0) can run the commands that do not need a player ped.

## Differences from stock

Messages, permission levels and flows match stock, except:

- `/car` spawns server-side (no client fuel/dirt reset).
- `/togglepvp` also replies to the caller.
- `/closeserver` joins all words as the reason (stock uses the first).
- `/addpermission` and `/removepermission` accept only
  `QBCore.Config.Server.Permissions`.

`QBCore.Commands.Add(name, help, args, argsRequired, cb, permission, ...)` accepts
extra permission levels like stock (`List[name].permission` is then an array);
`List` keys are lower-cased and entries carry `arguments` (and `params`).
`QBCore:CallCommand` notifies `No access to this command` and
`All arguments must be filled out!` like stock.
