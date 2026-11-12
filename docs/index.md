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
| Player data and lifecycle | Server-authoritative PlayerData cache, the single mutation funnel, change subscriptions, login/logout/drop, character creation and selection, resource-owned replicated fields. | [Player](./api/player.md) |
| Delta replication | Sends each client only the changed paths (coalesced per frame, sequenced, auto-resync) and keeps a live local PlayerData mirror. | [Player](./api/replication.md#client-mirror-code-derived) |
| Persistence | Dirty-column tracking, byte-identical change gate, coalesced flushes every `Config.persistence.interval`, immediate flush on drop/logout/shutdown, offline character reads/writes, durable provider fences. | [Player](./api/persistence.md#persistence-behaviour-code-derived) |
| Money | `cash`/`bank`/`crypto` accounts, optional transaction tax into a banking account, physical cash owned by the inventory provider, offline credits, compound transactions with rollback. | [Money](./api/money.md) |
| Jobs, gangs and duty | Registry-backed jobs/gangs, duty toggling, O(1) job and job-type indexes, on-duty rosters, `GlobalState.OnDuty`, paychecks and job-targeted dispatch alerts. | [Jobs and gangs](./api/jobs.md) |
| Shared registries | Live, runtime-updatable lists (items, vehicles, jobs, gangs, weapons, locations) mirrored into every resource through `@kora_core/init.lua`. | [Shared registries](./api/registry.md) |
| Inventory gateway | Forwards inventory calls to kora_inventory; a legacy slot-based fallback for staged rollouts; useable items, stashes, ground drops. | [Inventory](./api/inventory.md) |
| Metadata, needs and development mode | Metadata get/set/increment, hunger/thirst decay with zero-need damage, per-player development mode. | [Metadata and needs](./api/metadata.md) |
| Jail | Minimal built-in jail with timed release, or hand-off to an external prison resource. | [Jail](./api/jail.md) |
| Garage storage | `player_vehicles` ownership, store/spawn/impound, condition and property snapshots. | [Garage](./api/garage.md) |
| Permissions, commands and logging | ACE-backed `god`/`admin`/`mod`/`user` levels, owner-tracked command registration, ring-buffer event log. | [Permissions, commands and logging](./api/permissions.md) |
| Callbacks | Server and client callbacks on both the Kora and the legacy QBCore wire. | [Callbacks](./api/events.md) |
| Identity, users and utilities | Identifier extraction, citizen IDs, per-license character slots and Discord IDs, string/path helpers, language selector, pause-menu title, vehicle air control, dependency supervisor. | [Identity and utilities](./api/system.md) |
| Legacy qb-core compatibility | `QBCore` core object and direct `qb-core` exports in both realms, player objects, legacy events, 20 stock commands, stock vehicle-spawn callbacks, optional qbx facade. | [Compatibility](./api/compatibility.md) |

## Documentation map

- [Installation](./installation.md): requirements, install steps, manifest, start-up troubleshooting
- [How to use](./how-to-use.md): worked examples, call selection, security and common mistakes
- [Commands](./commands.md): every command, key mappings, stock qb-core commands, adding your own
- [API reference](./api/index.md): module index and export quick reference
  - [Player data and lifecycle](./api/player.md)
  - [Money, accounts and transactions](./api/money.md)
  - [Jobs, gangs, duty, paycheck and dispatch](./api/jobs.md)
  - [Metadata, needs and development mode](./api/metadata.md)
  - [Characters and multicharacter](./api/characters.md)
  - [Inventory gateway, usable items and consumables](./api/inventory.md)
  - [Garage and owned vehicles](./api/garage.md)
  - [Jail](./api/jail.md)
  - [Permissions, commands and logging](./api/permissions.md)
  - [Shared registries and utilities](./api/registry.md)
  - [Persistence and schema](./api/persistence.md): includes the database tables and durability
  - [Replication and the client mirror](./api/replication.md)
  - [Events, callbacks and state bags](./api/events.md)
  - [Configuration](./api/configuration.md): every `Config` option
  - [Compatibility](./api/compatibility.md): the legacy `qb-core` surface
  - [Compatibility helper exports](./api/compat-helpers.md)
  - [Locales, pause menu and other client systems](./api/system.md)
- [Items and seed data](./items.md): seeded item, weapon and ammo registries
- [Default qb-core commands](./default-commands.md)
- [qbx facade](./qbx-facade.md)
- [Vehicle spawn callbacks](./vehicle-spawn.md)
- [`player_vehicles` compatibility](./vehicles-compat.md)
- [Troubleshooting](./troubleshooting.md)
