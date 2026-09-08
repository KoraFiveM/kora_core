# Garage module

## Overview
SQL-persisted vehicle ownership shared by civilian garages and job duty fleets. Server only. Functions are defined on `Core.garage` and exported flat as `exports.qbcore:<fn>`.

## API

### `Core.garage.createVehicle(citizenid, model, plate, job, extra)`
Inserts a new `player_vehicles` row.

#### Parameters
- `citizenid: string | nil` — set for a civilian-owned vehicle.
- `model: string | number`
- `plate: string`
- `job: string | nil` — set for a job duty-fleet vehicle. Exactly one of `citizenid`/`job` is expected.
- `extra: table | nil` — `{fuel?, engineHealth?, bodyHealth?}`, defaults from `Config.garage`.

#### Returns
- `boolean`, `string | nil` — success, error.

### `Core.garage.getByPlate(plate)`
#### Returns
- `table | nil` — the row (`mods`/`last_position` JSON-decoded), or `nil` if not found/deleted.

### `Core.garage.getByOwner(citizenid)`
#### Returns
- `table[]` — every non-deleted row owned by `citizenid`, ordered by `id`.

### `Core.garage.storeVehicle(plate, snapshot)`
Marks the vehicle `garaged` and snapshots its condition. Does not delete the live entity — the caller (which has the entity handle) does that itself after this succeeds.

#### Parameters
- `plate: string`
- `snapshot: table | nil` — `{fuel?, engineHealth?, bodyHealth?, mods?, position?}`. Omitted fields are left unchanged.

#### Returns
- `boolean`, `string | nil` — `false, 'unknown vehicle'` / `false, 'vehicle is impounded'` on refusal.

### `Core.garage.spawnVehicle(src, plate, coords, heading)`
Spawns `plate` as a real, networked entity and marks it `out`. Refuses an impounded vehicle — retrieve it via `retrieveImpound` first.

#### Parameters
- `src: integer`
- `plate: string`
- `coords: vector3 | {x, y, z}`
- `heading: number`

#### Returns
- `integer | false` — the spawned vehicle's network id, or `false`.
- `string | nil` — error.

### `Core.garage.impound(plate, fee, impoundLot)`
#### Parameters
- `plate: string`, `fee: number`, `impoundLot: string | nil`

#### Returns
- `boolean`, `string | nil`

### `Core.garage.retrieveImpound(src, plate)`
Clears the impound flag. Charging the fee is the caller's responsibility, done before calling this.

#### Parameters
- `src: integer`, `plate: string`

#### Returns
- `boolean`, `string | nil` — `false, 'not your vehicle'` if `src` doesn't own a civilian-owned row.

### `Core.garage.updateState(plate, patch)`
Generic partial condition update, for periodic autosave of a vehicle that's currently `out`. Unlike `storeVehicle`, does not change `state` or refuse an impounded vehicle.

#### Parameters
- `plate: string`
- `patch: table` — `{fuel?, engineHealth?, bodyHealth?, mods?, position?}`

#### Returns
- `boolean`

### `Core.garage.saveVehicleProperties(plate, properties)`
Persists a complete `QB.vehicle.getProperties` snapshot without changing the
vehicle's state. Fuel, engine health, and body health are saved in their
dedicated columns; all other mutable properties are saved in `mods` and are
restored by `qbgarages` when the vehicle is taken out.

This is a **trusted server-resource API**. Call it only after the resource has
validated ownership and completed any tuning/payment logic. The normal garage
store callback continues to accept only safe cosmetic properties from a client.

#### Parameters
- `plate: string`
- `properties: table` — result of `QB.vehicle.getProperties(vehicle)`.

#### Returns
- `boolean`, `string | nil` — `false, 'unknown vehicle'` when no active row exists.

### `Core.garage.deleteVehicle(plate)`
Soft-deletes a vehicle row.

#### Returns
- `boolean`

#### Example
```lua
exports.qbcore:createVehicle(citizenid, 'sultan', plate, nil, { fuel = 100 })
local netId = exports.qbcore:spawnVehicle(src, plate, coords, heading)
exports.qbcore:storeVehicle(plate, { fuel = 87.5, engineHealth = 950.0 })

-- In a server-side tuning resource, after authorization/payment:
exports.qbcore:saveVehicleProperties(plate, properties)
```

## Notes
- **`mods` are opaque JSON**, never auto-applied to a spawned vehicle — apply them yourself if your garage UI has a tuning system.
- **`spawnVehicle` uses `CreateVehicle` directly**, not `QB.entities` — the vehicle must be visible to every player, not just the spawner.
- **This module never touches money.** Charge/refund the impound fee via `Core.money` before calling `impound`/`retrieveImpound`.
