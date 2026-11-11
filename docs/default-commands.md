# Stock qb-core default commands

`compat/server/qb-commands.lua` registers the 20 commands of qb-core
`server/commands.lua` through `QBCore.Commands.Add`, so they behave like any
other legacy command (owner tracking, chat suggestions, `command.<name>` ACE,
`QBCore:CallCommand`, `QBCore:Server:PreCommandExecution`).

Turn the whole set off with `Config.compat.defaultCommands = false` (default
`true`).

| command | level | what it does here |
|---|---|---|
| `/tp [id\|x y z\|location]` | admin | teleports through the stock `QBCore:Command:TeleportTo*` client events; target, location and coordinates validated server-side |
| `/tpm` | admin | `QBCore:Command:GoToMarker` |
| `/togglepvp` | admin | flips `QBCore.Config.Server.PVP`, broadcasts `QBCore:Client:PvpHasToggled`, and tells players who join while it is off |
| `/addpermission id level`, `/removepermission id level` | god | `Core.permissions` principals; `level` must be one of `QBCore.Config.Server.Permissions` (stock accepts any string) |
| `/openserver`, `/closeserver [reason]` | admin | flips `Config.Server.Closed`; closing kicks everyone without the whitelist permission. New connections are refused while closed |
| `/car model` | admin | spawns a **server-owned networked** vehicle (`QBCore.Functions.SpawnVehicle`), warps the admin in (deleting the vehicle they were in, as stock) and grants keys through `exports.kora_vehiclekeys:giveKeys` when that resource is started. The stock client-side local-only spawn is not used |
| `/dv` | admin | deletes the occupied vehicle, else vehicles within 5 m |
| `/dvall`, `/dvp`, `/dvo` | admin | delete all vehicles / peds / objects. `/dvp` spares player peds (stock would delete the players) |
| `/givemoney id type amount` | admin | `Core.money.addMoney` (untaxed, reason `Admin give money`); cash stays item-backed |
| `/setmoney id type amount` | admin | `Core.money.setMoney` |
| `/job`, `/gang` | user | show your job / gang |
| `/setjob id job [grade]`, `/setgang id gang [grade]` | admin | `Core.jobs.setJob/setGang`; the name is lower-cased and the grade is the stock zero-based number |
| `/ooc msg` | user | proximity OOC (20 m), opted-in admins see it everywhere |
| `/me msg` | user | `QBCore:Command:ShowMe3D` to players within 20 m |

There is no `/id` in qb-core's `commands.lua`, so none is registered.

## Behaviour notes

- **Logging.** Every use of a non-`user` command is written to
  `Core.logging.logEvent('admin', source, { command, args, ... })`, with the
  outcome (`ok`, `removed`, target, ...) for state-changing ones.
- **Name clashes.** A command already registered when this file loads (kora's
  own `/jail`, `/unjail`, another resource) is kept and a console line says so.
  A resource that registers the same name later replaces ours. Kora currently
  registers none of the 20 names itself.
- **Hook.** `QBCore.Commands.Add` now fires `QBCore:Server:PreCommandExecution(source, name, args, rawCommand)`
  before the callback of every legacy command; cancel it with `CancelEvent()`.
  `QBCore:CallCommand` still calls the stored callback directly, as stock does,
  and ignores non-table or oversized `args`. Every default command re-checks the
  invoker's permission level (`QBCore.Functions.HasPermission`) in its handler, so
  a holder of the per-command ACE who lacks the `admin`/`god` level is refused
  (and the attempt audited with `denied = true`) even via `QBCore:CallCommand`.
- **ACE.** Like stock, `Commands.Add` grants `command.<name>` to `kora_core.<level>`
  (not for `god`/`user`, `QBCore.Commands.IgnoreList`). Without that ACE
  `QBCore:CallCommand` and chat suggestions deny the command.
- **Arguments** are never trusted: ids must be online integers, money types must
  be configured accounts and amounts finite, model names `[%w_]{1,32}`,
  coordinates finite, `/setjob` and `/setgang` grades whole numbers >= 0 (a missing or invalid grade is rejected, not defaulted to 0). Console (`source 0`) can run the commands that do not need
  a player ped.

## Parity notes (`car`, `togglepvp`, `openserver`, `closeserver`, `addpermission`, `removepermission`)

Messages, permission levels and flows match stock. Deliberate differences: `/car` spawns server-side (no fuel/dirt reset);
`/togglepvp` also replies to the caller; `/closeserver` joins all words as the reason (stock uses the first);
`/addpermission` and `/removepermission` accept only `QBCore.Config.Server.Permissions`.

`QBCore.Commands.Add(name, help, args, argsRequired, cb, permission, ...)` accepts extra permission levels like stock
(`List[name].permission` is then an array); `List` keys are lower-cased and entries carry `arguments` (and `params`).
`QBCore:CallCommand` notifies `No access to this command` / `All arguments must be filled out!` like stock.
