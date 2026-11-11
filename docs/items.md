---
title: Items and seed data
sidebar_position: 8
---

# Items and seed data

kora_core seeds its [shared registries](./features/shared-registries.md) at boot. You
do not need to add any item to another resource for kora_core to work. Other
resources add or replace records at runtime with `registerShared` (or
`Kora.shared.register` on the server).

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
    image = 'water_bottle.png',     -- legacy file name
    imageUrl = 'https://...',       -- optional browser-ready URL
    -- optional:
    container = true,               -- e.g. backpack
    ammoType = 'AMMO_PISTOL',       -- ammo items
    rounds = 30,                    -- ammo items
    effect = { hungerDelta = 10, thirstDelta = -5, stressDelta = -2 }, -- consumable effects hook
}
```

`effect` is read by the consumable effects hook (see
[Inventory](./features/inventory.md#consumable-effects)); none of the seeded items
set it.

## Seeded items

- `shared/items.lua`: Kora's own items, including food and drink (`water_bottle`,
  `sandwich`, `bread`, `soda`, `beer`, `whiskey`, `chocolate_bar`), identity and
  utility items (`phone`, `id_card`, `vehiclekey`, `lockpick`, `backpack`,
  `weaponlicense`), physical `cash`, crafting materials (`metalscrap`, `plastic`,
  `copper`, `rubber`, `iron`, `aluminum`, `steel`, `glass`, ...), and items used by
  Kora job and activity resources (fishing, metal detecting, mining, robberies).
  `imageUrl` values point to an external image repository for the items listed in
  `KoraCoreSeed.itemImagePaths`.
- Ammo items built by the `ammo()` helper: `pistol_ammo`, `smg_ammo`,
  `shotgun_ammo`, `rifle_ammo`, `mg_ammo`, `snp_ammo`, `taser_cartridge`,
  `flare_ammo`, `musket_ammo`, `rpg_ammo`, `grenade_launcher_ammo`,
  `smoke_grenade_ammo`, `minigun_ammo`, `firework_ammo`, `railgun_ammo`,
  `homing_missile`, `emp_round`. `KoraCoreSeed.ammoItems` maps GTA ammo types to
  these names.
- `shared/upstream/items.lua`: the stock qb-core item list. A stock item is added
  only when Kora does not define it; when it does, the stock record only fills
  fields Kora left empty. Stock items with `type = 'weapon'` go to the `weapons`
  registry instead.

Starter items (`QBCore.Shared.StarterItems`): `phone`, `id_card`,
`driver_license`, one each. kora_core only records them in
`metadata.starterItems` of new characters; granting is left to the inventory
provider.

## Weapons

`shared/weapons.lua` defines the `weapons` registry: GTA weapons with `name`
(for example `weapon_pistol`), `label`, `weight`, `type = 'weapon'`,
`weapontype`, `ammotype`, `ammoItem` (the matching ammo item), `damageModifier`,
`disableCriticalHits`, `image`, `imageUrl`, `unique = true`, and a few special
weapon items (`weapon_bread`, `weapon_briefcase`, `weapon_handcuffs`, ...). Stock
qb-core weapon items fill gaps. Weapons always count as unique in the fallback
inventory. The legacy `QBCore.Shared.Weapons` view is keyed by weapon hash and adds
stock `weapontype`/`damagereason` fields.

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

Stock qb-core jobs that Kora does not define are added from
`shared/upstream/jobs.lua`: `bus`, `judge`, `lawyer`, `news`, `trucker`,
`garbage`, `vineyard`, `hotdog`, `realestate`, `taxi`, `cardealer`, `beeker`,
`bennys`. Jobs without a `type` get `none`.

Gangs: `none`, `ballas`, `vagos` from `shared/gangs.lua`, plus stock `lostmc`,
`cartel`, `families` and `triads`.

## Locations

`shared/locations.lua` seeds the `locations` registry (key `key`):
`spawn_legion`, `spawn_pillbox`, `garage_legion`, each with `label`, `x`, `y`, `z`,
`h`. The legacy view is `QBCore.Shared.Locations`, used by `/tp <location>`.

## Generating an ox_inventory item file

`tools/ox_items/generate.lua` is an offline Lua 5.4 script that builds a stock
ox_inventory `data/items.lua` from the kora_core registry, with a name mapping and
a report of items referenced in code but missing from the registry. See its
[README](https://github.com/KoraFiveM/kora_core/blob/dev/tools/ox_items/README.md).
