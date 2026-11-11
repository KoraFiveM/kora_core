---
title: kora_core
sidebar_position: 1
---

# kora_core

kora_core is the player/framework core of the Kora FiveM resource set. It owns the
character lifecycle, PlayerData, money, jobs and gangs, metadata, the shared
item/vehicle/job/gang/weapon/location registries and the gateway to the inventory
provider. Every player mutation goes through one funnel (`Core.player.setPath`),
which marks the database column dirty, queues a client delta and fires change
subscribers. Data is saved with minimum writes through
[kora_sql](https://github.com/KoraFiveM/kora_sql), and helpers come from
[kora_lib](https://github.com/KoraFiveM/kora_lib). kora_core also ships a
compatibility layer for legacy `qb-core` resources (`provide 'qb-core'`), so most
QBCore resources run unmodified.

New code uses flat exports such as `exports.kora_core:getPlayer(source)`. Legacy
code keeps using `exports['qb-core']:GetCoreObject()`.

## Features

| Feature | What it does | Page |
| --- | --- | --- |
| Player data and lifecycle | Server-authoritative PlayerData cache, the single mutation funnel, change subscriptions, login/logout/drop, character creation and selection, resource-owned replicated fields. | [Player](./features/player.md) |
| Delta replication | Sends each client only the changed paths (coalesced per frame, sequenced, auto-resync) and keeps a live local PlayerData mirror. | [Player](./features/player.md#client-mirror) |
| Persistence | Dirty-column tracking, byte-identical change gate, coalesced flushes every `Config.persistence.interval`, immediate flush on drop/logout/shutdown, offline character reads/writes, durable provider fences. | [Player](./features/player.md#persistence) |
| Money | `cash`/`bank`/`crypto` accounts, optional transaction tax into a banking account, physical cash owned by the inventory provider, offline credits, compound transactions with rollback. | [Money](./features/money.md) |
| Jobs, gangs and duty | Registry-backed jobs/gangs, duty toggling, O(1) job and job-type indexes, on-duty rosters, `GlobalState.OnDuty`, paychecks and job-targeted dispatch alerts. | [Jobs and gangs](./features/jobs-gangs.md) |
| Shared registries | Live, runtime-updatable lists (items, vehicles, jobs, gangs, weapons, locations) mirrored into every resource through `@kora_core/init.lua`. | [Shared registries](./features/shared-registries.md) |
| Inventory gateway | Forwards inventory calls to kora_inventory; a legacy slot-based fallback for staged rollouts; useable items, stashes, ground drops. | [Inventory](./features/inventory.md) |
| Metadata, needs and development mode | Metadata get/set/increment, hunger/thirst decay with zero-need damage, per-player development mode. | [Metadata and needs](./features/metadata-needs.md) |
| Jail | Minimal built-in jail with timed release, or hand-off to an external prison resource. | [Jail](./features/jail.md) |
| Garage storage | `player_vehicles` ownership, store/spawn/impound, condition and property snapshots. | [Garage](./features/garage.md) |
| Permissions, commands and logging | ACE-backed `god`/`admin`/`mod`/`user` levels, owner-tracked command registration, ring-buffer event log. | [Permissions, commands and logging](./features/permissions-commands-logging.md) |
| Callbacks | Server and client callbacks on both the Kora and the legacy QBCore wire. | [Callbacks](./features/callbacks.md) |
| Identity, users and utilities | Identifier extraction, citizen IDs, per-license character slots and Discord IDs, string/path helpers, language selector, pause-menu title, vehicle air control, dependency supervisor. | [Identity and utilities](./features/identity-utilities.md) |
| Legacy qb-core compatibility | `QBCore` core object and direct `qb-core` exports in both realms, player objects, legacy events, 20 stock commands, stock vehicle-spawn callbacks, optional qbx facade. | [Compatibility](./compatibility.md) |

## Requirements

- [kora_lib](https://github.com/KoraFiveM/kora_lib) (manifest dependency; also provides `progressbar`, notify, zones, callbacks, NUI menu)
- [kora_sql](https://github.com/KoraFiveM/kora_sql) (manifest dependency; schema creation and all queries)
- MariaDB 10.2 or later for the `player_vehicles` sync triggers and generated columns (see [Database](./database.md))
- OneSync (server-side position sampling and server-created vehicles use server entity natives)

Optional integrations, used only when the resource is started:

- [kora_inventory](https://github.com/KoraFiveM/kora_inventory): inventory authority (`Config.inventory.provider`), physical cash, consumable effects hook
- [kora_vehiclekeys](https://github.com/KoraFiveM/kora_vehiclekeys): keys for `/car` and the vehicle-spawn callbacks
- [kora_banking](https://github.com/KoraFiveM/kora_banking) or `qb-banking`: transaction tax deposits (`Config.money.tax.provider`) and durable money operations
- `kora_housing`: the only external resource allowed to pass an exterior position to `logout`
- A character-select UI such as [kora_multichar](https://github.com/KoraFiveM/kora_multichar)

## Installation

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
   compatibility triggers. See [Database](./database.md).
4. No items need to be added. kora_core seeds its own item, weapon, vehicle, job,
   gang and location registries at boot (see [Items](./items.md)).
5. Review [Configuration](./configuration.md) (`config.lua`), especially
   `Config.money`, `Config.inventory.provider` and the `Config.compat` flags.

To read the shared registries in another resource, add the mirror after kora_lib's
init file:

```lua
shared_script '@kora_lib/init.lua'
shared_script '@kora_core/init.lua'
```

## Quick examples

```lua
-- server: give a starting kit
exports.kora_core:addMoney(source, 'cash', 500, 'starting-kit')
exports.kora_core:addItem(source, 'water_bottle', 2)

-- server: react to bank balance changes
exports.kora_core:onChange({ 'money', 'bank' }, function(src, path, value)
    print(('player %d bank is now %s'):format(src, value))
end)

-- client: read the local mirror (no network round trip)
local job = exports.kora_core:getPlayerData({ 'job' })
print(job.label, job.grade.level)
```

```lua
-- legacy resource, unmodified
local QBCore = exports['qb-core']:GetCoreObject()
local Player = QBCore.Functions.GetPlayer(source)
Player.Functions.AddMoney('cash', 500, 'reason')
Player.Functions.SetJob('police', 2) -- zero-based grade, like stock qb-core
```

## Reference pages

- [Configuration](./configuration.md): every `config.lua` option
- [Commands](./commands.md): chat commands and key mappings
- [Exports](./exports.md): every client and server export
- [Events](./events.md): events you can listen to, and the guarded net events
- [Database](./database.md): tables, columns, triggers and generated columns
- [Items](./items.md): the seeded item, weapon and ammo registries and the item record shape
- [Compatibility](./compatibility.md): the legacy `qb-core` surface
  - [Default qb-core commands](./default-commands.md)
  - [qbx facade](./qbx-facade.md)
  - [Vehicle spawn callbacks](./vehicle-spawn.md)
  - [`player_vehicles` compatibility](./vehicles-compat.md)
- [Troubleshooting](./troubleshooting.md)

## Durability

The periodic save bounds worst-case data loss on a hard crash to roughly one
`Config.persistence.interval` (60 seconds by default, with jitter). Player drop,
logout, txAdmin shutdown, a txAdmin scheduled restart within 60 seconds and the
resource stop all flush immediately, but FXServer does not guarantee that a yield
in `onResourceStop` completes, so this bounds loss rather than eliminating it.
