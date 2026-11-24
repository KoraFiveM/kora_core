---
title: Items and seed data
sidebar_position: 6
---

# Items and seed data

kora_core ships the full item and weapon catalogue and seeds its
[shared registries](./api/registry.md) at boot. The catalogue is available
with or without kora_inventory. Clients receive their live records through the
registry snapshot.

Edit the seed files below and restart kora_core to reload them. Server resources
can add or replace records at runtime with `registerShared` or
`Kora.shared.register`.

## Item record

```lua
{
    name = 'water_bottle',          -- registry key
    label = 'Water',
    weight = 500,                   -- grams
    type = 'item',                  -- 'item' or 'weapon'
    unique = false,                 -- unique items never stack
    useable = true,
    shouldClose = true,             -- close the inventory UI on use
    description = 'Refreshing.',
    image = 'water_bottle.png',     -- image file name resolved by the inventory
    -- optional:
    gridWidth = 1,                 -- width in inventory cells
    gridHeight = 1,                -- height in inventory cells
    dropProp = 'prop_ld_flow_bottle', -- optional model for trunk cargo
    container = true,               -- e.g. backpack
    ammoType = 'AMMO_PISTOL',       -- ammo items
    rounds = 30,                    -- ammo items
    effect = { hungerDelta = 10, thirstDelta = -5, stressDelta = -2 }, -- consumable effects hook
}
```

`effect` is read by the consumable effects hook (see
[Inventory](./api/inventory.md#consumable-effects)); none of the seeded items
set it.

## Seeded items

- `shared/items.lua` contains identity and utility items, physical `cash`,
  crafting materials, and items used by Kora jobs and activities. It also
  contains food, drinks, weapon attachments, supplies, and ammo such as
  `pistol_ammo`, `smg_ammo`,
  `shotgun_ammo`, `rifle_ammo`, `mg_ammo`, `snp_ammo`, `taser_cartridge`,
  `flare_ammo`, `musket_ammo`, `rpg_ammo`, `grenade_launcher_ammo`,
  `smoke_grenade_ammo`, `minigun_ammo`, `firework_ammo`, `railgun_ammo`,
  `homing_missile`, `emp_round`. `KoraCoreSeed.ammoItems` maps GTA ammo types to
  these names.
- `shared/weapons.lua` contains GTA weapon items and QBCore damage metadata.
  The native catalogue includes the stock QBCore definitions Core previously
  shipped separately.

kora_inventory resolves artwork from each definition's `image` filename,
local `kora_inventory/images` files, and its configured CDN fallback.

Starter items (`QBCore.Shared.StarterItems`): `phone`, `id_card`,
`driver_license`, one each. kora_core only records them in
`metadata.starterItems` of new characters; granting is left to the inventory
provider.

## Weapons

Edit `shared/weapons.lua` to change the bundled GTA weapon items,
including `weapon_pistol`, `weapon_bread`, `weapon_briefcase`, and
`weapon_handcuffs`. Core places records with `type = 'weapon'` in its live
`weapons` registry and keeps ammunition, supplies, and attachments in `items`.
The usable weapon definitions carry `weapontype` and `ammotype` as applicable,
and Core fills in the matching `ammoItem`, `damageModifier`, and
`disableCriticalHits` defaults. Weapons always count as unique in Core's fallback
inventory.

Core also owns the static damage metadata used by the hash-keyed
`QBCore.Shared.Weapons` view.

## Vehicles

`shared/vehicles.lua` seeds the `vehicles` registry (key `model`) with GTA vehicles:
`model`, `name`, `brand`, `price`, `category`. The vehicle-spawn callbacks in
`limited` mode only allow models found here (or in
`Config.compat.vehicleSpawn.allowModels`).

## Jobs and gangs

Kora jobs (`shared/jobs.lua`, one-based grade arrays):

| Job | Label | Type | Default duty | Grades |
| --- | --- | --- | --- | --- |
| `unemployed` | Civilian | `civ` | on | Freelancer (10) |
| `police` | Law Enforcement | `leo` | off | Cadet, Officer, Sergeant, Lieutenant, Chief (boss) |
| `ambulance` | EMS | `ems` | off | Recruit, EMT, Paramedic, Supervisor, Chief (boss) |
| `mechanic` | Mechanic | `automotive` | off | Apprentice, Mechanic, Boss (boss) |
| `roadside` | Roadside Assistance | `automotive` | off | Responder, Technician, Supervisor (boss) |
| `bodyshop` | Bodyshop | `bodyshop` | off | Detailer, Painter, Owner (boss) |
| `tow` | Recovery | `recovery` | off | Driver, Operator, Owner (boss) |

The same job file includes `bus`, `judge`, `lawyer`, `news`, `trucker`, `garbage`,
`vineyard`, `hotdog`, `realestate`, `taxi`, `cardealer`, `mechanic2`, `mechanic3`,
`beeker` and `bennys`. Jobs without a `type` get `none`.

`shared/gangs.lua` includes `none`, `ballas`, `vagos`, `cartel`, `families`,
`lostmc` and `triads`.

## Locations

`shared/locations.lua` seeds the `locations` registry (key `key`):
`spawn_legion`, `spawn_pillbox`, `garage_legion`, each with `label`, `x`, `y`, `z`,
`h`. The legacy view is `QBCore.Shared.Locations`, used by `/tp <location>`.

## Importing a former qb-core catalogue

Copy any of `items.lua`, `jobs.lua`, `gangs.lua`, `vehicles.lua` or `weapons.lua`
from your former qb-core `shared/` directory into `kora_core/shared/upstream/`
and restart kora_core. This also accepts the keyed `QBCoreUpstream` files from
earlier kora_core installs. Each file may define its corresponding table using
`QBCore.Shared`, `QBShared` or `QBCoreUpstream`.

Imports run once on the server at startup. They add new records and fill
missing top-level fields. Values already present in the native catalogue,
including `false` flags and complete job or gang grade tables, take precedence.
Each job's default duty comes from its `defaultDuty` field. Edit the native
seed to change a bundled value.

To add a grantable weapon, define it as an item with `type = "weapon"` in
`items.lua`. Optional `weapons.lua` records supplement matching weapon entries
with metadata. Core's built-in damage causes remain visible in the legacy weapon
view.

An absent file is optional. Core logs an invalid file with its path and reason
and continues loading the native catalogue and other imports. The resulting
registries are synchronized to clients through the usual snapshot.

## Generating an ox_inventory item file

`tools/ox_items/generate.lua` is an offline Lua 5.4 script that builds a stock
ox_inventory `data/items.lua` from the kora_core registry, with a name mapping and
a report of items referenced in code but missing from the registry. See its
[README](https://github.com/KoraFiveM/kora_core/blob/dev/tools/ox_items/README.md).
