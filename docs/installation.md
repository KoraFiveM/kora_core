---
title: "Installation"
sidebar_position: 2
---


# Installation

Kora Core is the player and framework core of the Kora stack: characters, PlayerData, money, jobs and gangs, metadata, shared item/job/vehicle registries, persistence and a qb-core compatibility layer. It is built on Kora Lib and persists through Kora SQL. Every public function is a flat export: `exports.kora_core:name(...)`.

## Requirements

- `kora_lib` and `kora_sql`, both declared with `dependency` in the manifest. `kora_core` will not start without them.
- A MySQL database reachable through the `mysql_connection_string` convar (read by Kora SQL). The tables are created on boot, so no SQL import is needed.
- `lua54 'yes'` (already set in the manifest) and a FiveM server build that supports it.
- OneSync, because vehicles are created with server-side natives (`CreateVehicleServerSetter`, `CreateVehicle` with the networked flag).
- `kora_inventory` is the default inventory provider (`Config.inventory.provider`). Without a started provider the legacy in-resource inventory engine answers instead, as long as `Config.inventory.allowLegacyFallback` is `true` (the default).

## Install Kora Core

1. **Add the folder** — Place `kora_core` in your resources directory (on the Kora dev server: `resources/[pre]/kora_core`). Keep the folder name unchanged: other resources call `exports.kora_core` and import `@kora_core/init.lua`.

2. **Check the database convar** — Make sure the connection string is set before any resource starts:

   ```bash title="server.cfg"
   set mysql_connection_string "mysql://user:password@localhost/kora?charset=utf8mb4"
   ```

3. **Start it in order** — Kora Core must start after Kora Lib and Kora SQL, and before any resource that calls its exports:

   ```bash title="server.cfg"
   ensure kora_lib
   ensure kora_sql
   ensure kora_inventory
   ensure kora_core
   ensure [kora]
   ```

4. **Grant the ACEs** — Permission levels are ACE principals named `kora_core.god`, `kora_core.admin` and `kora_core.mod`. The resource itself needs the `command` ACE because `addPermission` and `removePermission` run `add_principal` / `remove_principal` through `ExecuteCommand`:

   ```bash title="server.cfg"
   add_ace resource.kora_core command allow
   add_ace kora_core.god command allow
   add_principal kora_core.god kora_core.admin
   add_principal kora_core.admin kora_core.mod

   # make yourself a god (identifier from your own license)
   add_principal identifier.license:YOUR_LICENSE kora_core.god
   ```

5. **Declare it in your own resource** — A resource that calls Kora Core should depend on it so FiveM starts it first. Add the shared registry mirror only if you read `Kora.shared.*` in your own VM (load it after `@kora_lib/init.lua`):

   ```lua title="fxmanifest.lua"
   dependency 'kora_core'

   shared_script '@kora_lib/init.lua'
   shared_script '@kora_core/init.lua'
   ```

6. **Restart and join** — Watch the console for `[kora_core:schema] schema up to date.` and join the server. With no character-select resource running, the built-in flow picks character slot 1 (or creates a default `John Doe` character if you have none) and logs you in.

## What the manifest sets up

- `provide 'qb-core'` satisfies another resource's `dependency` check for that name. `qb-multicharacter` and `qbx_core` are deliberately not provided.
- `build/finalise.lua` runs last in each realm and exports every function that is stored on `Core.<module>.<fn>` and does not start with an underscore. The export name is the function name alone (no module prefix), so two modules cannot define the same name: a collision aborts the load of that realm with an assertion.
- Shared scripts load in a fixed, explicit order (config, `Core` table, shared data, util, registry, player, inventory shapes, compat skeleton). Server modules load registry, identity, users, replication, persistence, player, then the wrappers (money, jobs, metadata, inventory, ...) and finally the compat files.
- `init.lua` and `shared/locale.lua` are listed under `files` only. `init.lua` is for other resources that import it with `shared_script '@kora_core/init.lua'`; Kora Core does not load it itself.
- On the first start the persistence module creates `players`, `player_identifiers`, `inventories`, `bans`, `users`, `player_vehicles` and `kora_core_player_column_operations` and adds two `player_vehicles` compatibility triggers. See the Persistence module for details.

## If it does not start or players cannot join

- A red `[kora_core:schema]` console line (`schema setup failed`) means the tables could not be created. Fix the connection string or the database user rights and restart; the boot does not retry after a failure.
- An assertion about a duplicate export name means two modules define the same function name. Rename one of them, or prefix it with `_` to keep it private.
- Players stuck on loading: the default multichar flow only runs when no UI resource calls `exports.kora_core:claimUI()` within about 500 ms of Kora Core's client scripts starting. A character-select resource must claim the UI early enough or both flows run.
- `add_ace resource.kora_core command allow` missing: `addPermission` and `removePermission` silently have no effect because the `add_principal` command is not allowed.
- Inventory calls return `nil` and a message such as `kora_inventory is not started`: the configured provider is not running and `Config.inventory.allowLegacyFallback` is `false`. Ensure `kora_inventory` before Kora Core consumers, or allow the fallback.

## Requirements and optional integrations (code-derived)

- [kora_lib](https://github.com/KoraFiveM/kora_lib) (manifest dependency; also provides `progressbar`, notify, zones, callbacks, NUI menu)
- [kora_sql](https://github.com/KoraFiveM/kora_sql) (manifest dependency; schema creation and all queries)
- MariaDB 10.2 or later for the `player_vehicles` sync triggers and generated columns (see [Database](./api/persistence.md#database-tables-and-columns-code-derived))
- OneSync (server-side position sampling and server-created vehicles use server entity natives)

Optional integrations, used only when the resource is started:

- [kora_inventory](https://github.com/KoraFiveM/kora_inventory): inventory authority (`Config.inventory.provider`), physical cash, consumable effects hook
- [kora_vehiclekeys](https://github.com/KoraFiveM/kora_vehiclekeys): keys for `/car` and the vehicle-spawn callbacks
- [kora_banking](https://github.com/KoraFiveM/kora_banking) or `qb-banking`: transaction tax deposits (`Config.money.tax.provider`) and durable money operations
- `kora_housing`: the only external resource allowed to pass an exterior position to `logout`
- A character-select UI such as [kora_multichar](https://github.com/KoraFiveM/kora_multichar)

## Installation summary (code-derived)

1. Create the database and point kora_sql at it.
2. Ensure the resources in this order in `server.cfg`:

```cfg
set mysql_connection_string "mysql://user:pass@localhost/kora?charset=utf8mb4"

ensure kora_sql
ensure kora_lib
ensure kora_core
# then kora_inventory and the rest of the Kora resources
```

3. Start the server. There is no SQL file to import: on boot kora_core creates or
   extends its tables from `modules/persistence/schema.lua` through
   `Kora.sql.ensureTables` (additive only) and installs the `player_vehicles`
   compatibility triggers. See [Database](./api/persistence.md).
4. No items need to be added. kora_core seeds its own item, weapon, vehicle, job,
   gang and location registries at boot (see [Items](./items.md)).
5. Review [Configuration](./api/configuration.md) (`config.lua`), especially
   `Config.money`, `Config.inventory.provider` and the `Config.compat` flags.

To read the shared registries in another resource, add the mirror after kora_lib's
init file:

```lua
shared_script '@kora_lib/init.lua'
shared_script '@kora_core/init.lua'
```
