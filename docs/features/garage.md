---
title: Garage storage
sidebar_position: 8
---

# Garage storage

`Core.garage` stores owned vehicles in `player_vehicles` for civilian garages and
job fleets. It has no UI and never touches money; garage, dealership and impound
resources build on it. All functions are server-side and yield (database access).

## API

| Export | Returns | Description |
| --- | --- | --- |
| `createVehicle(citizenid, model, plate, job, extra)` | `true` or `false, err` | Inserts a row. Pass `citizenid` for a civilian vehicle or `job` for a fleet vehicle (one of them is required, as is a plate). `extra` may set `fuel`, `engineHealth`, `bodyHealth`; defaults come from `Config.garage`. |
| `getByPlate(plate)` | row or `nil` | Active row with `mods` and `last_position` JSON-decoded. |
| `getByOwner(citizenid)` | array | Active rows of a citizen, ordered by `id`. |
| `storeVehicle(plate, snapshot)` | `true` or `false, err` | Marks the vehicle `garaged` and saves the given condition. See below. Does not delete the entity. |
| `spawnVehicle(src, plate, coords, heading, expectedOwner)` | network ID or `false, err` | Creates a networked server vehicle for a `garaged` row and marks it `out`. |
| `tagVehicle(entity, id)` | boolean | Sets the server-only `vehicleid` entity state bag to `player_vehicles.id`. |
| `impound(plate, fee, impoundLot)` | `true` or `false, err` | Sets `state = 'impounded'`, `impound_fee`, `impound_lot`, `impounded_at`. |
| `retrieveImpound(src, plate)` | `true` or `false, err` | Returns an impounded vehicle to `garaged`. For civilian rows `src` must own it. Charge the fee before calling. |
| `updateState(plate, patch)` | boolean | Partial condition update (`fuel`, `engineHealth`, `bodyHealth`, `mods`, `position`) without changing `state`. |
| `saveVehicleProperties(plate, properties)` | `true` or `false, err` | Saves a full `Kora.vehicle.getProperties` snapshot: fuel and health go to their columns, everything except plate/model/fuel/health goes to `mods`. Trusted server API; authorize and charge first. |
| `deleteVehicle(plate)` | boolean | Soft-deletes the row (`deleted_at`). |

### storeVehicle snapshot

`snapshot` may contain `fuel`, `engineHealth`, `bodyHealth`, `mods`, `position`,
`garageId` and `ownerCitizenId`.

- With `garageId` (1 to 50 characters) the update only succeeds when the row is
  currently `out` (and, with `ownerCitizenId`, still owned by that citizen); it sets
  `garage_id`. Errors: `invalid garage id`, `vehicle ownership changed`,
  `vehicle is no longer available`.
- Without `garageId` the row is set to `garaged` whatever its previous state,
  except that impounded vehicles are refused (`vehicle is impounded`).

### spawnVehicle

- Refuses unknown, impounded and already-`out` vehicles, a mismatching
  `expectedOwner`, and a second spawn of the same plate while one is in progress.
- Creates the vehicle with `CreateVehicle`, puts it in the requester's routing
  bucket, sets the plate and body health, waits up to
  `Config.garage.spawnNetworkIdTimeout` for a network ID, then switches the row from
  `garaged` to `out`; on any failure the entity is deleted.
- Tags the entity with `vehicleid` (disabled with the convar
  `kora:vehicleIdStateBag 0`).
- Sends `kora_core:client:vehicleCondition` to the requester, whose client waits up
  to 5 seconds for the entity, takes control and restores fuel and engine health.
  A failure there is only logged.
- `mods` are not applied; the calling garage resource applies them.

```lua
exports.kora_core:createVehicle(citizenid, 'sultan', plate, nil, { fuel = 100 })
local netId, err = exports.kora_core:spawnVehicle(source, plate, coords, heading)
exports.kora_core:storeVehicle(plate, { fuel = 87.5, engineHealth = 950.0 })
```

Vehicle state uses the strings `out`, `garaged` and `impounded`. For the stock
qb-core columns kept in sync on the same table, see
[`player_vehicles` compatibility](../vehicles-compat.md).
