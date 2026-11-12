---
title: "Garage and owned vehicles"
sidebar_position: 8
---


# Garage and owned vehicles

## Server

SQL-persisted vehicle ownership. Civilian garage vehicles and job duty-fleet vehicles share the `player_vehicles` table; a row is expected to have exactly one of `citizenid` or `job` (convention, not enforced by SQL). `spawnVehicle` creates a real networked entity visible to everyone. Vehicle `mods` are stored and returned as opaque JSON and are not applied automatically.

Namespace: `exports.kora_core` · Source: `modules/garage/server.lua`

### Config.garage

config.lua defaults.

| Key | Default | Meaning |
| --- | --- | --- |
| defaultFuel | 100 | Fuel stored for a new row when `extra.fuel` is nil. |
| defaultEngineHealth | 1000 | Engine health stored when `extra.engineHealth` is nil. |
| defaultBodyHealth | 1000 | Body health stored when `extra.bodyHealth` is nil. |
| spawnNetworkIdTimeout | 1000 | Milliseconds `spawnVehicle` waits (polling every 50 ms) for a positive network id before failing with `failed to network vehicle`. |

### How it works

Every function waits up to 60000 ms for the `player_vehicles` table to exist (`Kora.sql.awaitTables`) and yields on SQL. `plate` has a unique index (`uk_vehicles_plate`), which soft-deleted rows still occupy.

### Terms used on this page

| Term | Meaning |
| --- | --- |
| State | Enum column `state`: `garaged` (default for new rows), `out` (spawned in the world), `impounded`. |
| vehicleid state bag | `Entity(entity).state.vehicleid` holds `player_vehicles.id`, set with replication false (server only) so stock ox_inventory can read it. Applied by `spawnVehicle` through `tagVehicle` after the database row moved to `out`. Never cleared on despawn. |
| ConVar kora:vehicleIdStateBag | Default 1. Set to 0 and `tagVehicle` returns false without touching the entity. Read on each call with `GetConvarInt`. |
| Config.garage | `defaultFuel` 100, `defaultEngineHealth` 1000, `defaultBodyHealth` 1000 (used by `createVehicle` when `extra` omits them), `spawnNetworkIdTimeout` 1000 ms (how long `spawnVehicle` polls for a positive network id). |

### Spawn lifecycle

`spawnVehicle` normalises the plate (trim, uppercase) and takes a per-plate lock, loads the row, refuses `impounded` and `out`, creates the entity with `CreateVehicle` (networked, not a mission entity), puts it in the caller's routing bucket, sets plate text and body health, then waits for a network id. Only then does it run `UPDATE ... SET state = 'out' WHERE state = 'garaged'`; if that affects exactly one row it tags the vehicle and sends `kora_core:client:vehicleCondition` to the caller. Any failure after creation deletes the entity, so durable state never says `out` for a vehicle that does not exist.

### kora_core:client:vehicleCondition

Fuel and engine setters are client natives, so the server sends `(networkId, fuel, engineHealth)` to the spawning player. The client handler ignores the event unless `source == 65535` (a server-originated net event) and `netId` is a positive integer and both values are finite numbers. It waits up to 5000 ms for the entity to stream, requires it to be a vehicle (entity type 2), requests control for 1000 ms and then applies `SetVehicleFuelLevel` and `SetVehicleEngineHealth`. Values are not clamped. Failures print `[kora_core] Could not stream the garage vehicle ...` or `[kora_core] Could not restore garage vehicle condition: <reason>`.

### storeVehicle: two paths

With `snapshot.garageId` set it is the strict path: atomic update that requires `state = 'out'` and optionally the owner, sets `garage_id`, and ignores `position`. Without `garageId` it is the loose path: any non-impounded row becomes `garaged`, `garage_id` is untouched, `position` is stored in `last_position`, and there is no state or owner precondition.

### Functions

Server only. None of these are callable by clients. Callers must authorise the player and charge fees themselves.

#### `exports.kora_core:createVehicle(citizenid, model, plate, job, extra)`

Insert a `player_vehicles` row in state `garaged`. `model` is stored in both the `model` and `vehicle` columns (a number is stored as its string form). Yields.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `citizenid` | string\|nil | Owner for a civilian vehicle. At least one of citizenid or job is required. |
| `model` | string\|number | Model name or hash. |
| `plate` | string | Non-empty plate. The column is varchar(15) and unique. |
| `job?` | string | Job name for a duty-fleet vehicle. |
| `extra?` | table | `{fuel?, engineHealth?, bodyHealth?}`; defaults from `Config.garage`. |

**Returns**

- **true** — row inserted.
- **false, reason** — `reason` is the error from waiting on the table (60000 ms) or the SQL error string, for example a duplicate plate.
- **error** — Raises an error (assert) with `Core.garage.createVehicle requires citizenid or job.` or `Core.garage.createVehicle requires a plate.`; these are programmer errors and are not returned.

**Example**

```lua
local ok, err = exports.kora_core:createVehicle(citizenid, 'sultan', 'ABC123', nil, { fuel = 80 })
if not ok then print('createVehicle: ' .. tostring(err)) end
```

**Representative console output**

```text
-- ok = true
```

#### `exports.kora_core:getByPlate(plate)`

Fetch one non-deleted row by plate. Yields.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `plate` | string | Plate, matched by SQL equality (the table collation is case-insensitive); not normalised here. |

**Returns**

- **row** — the full `player_vehicles` row with `mods` and `last_position` JSON-decoded (nil when null or undecodable).
- **nil** — no matching non-deleted row, the table did not become ready, or the query failed.

**Example**

```lua
local row = exports.kora_core:getByPlate('ABC123')
if row then print(row.state, row.garage_id) end
```

**Representative console output**

```text
garaged   legion_a
```

#### `exports.kora_core:getByOwner(citizenid)`

All non-deleted vehicles of a character, ordered by `id`. Yields.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `citizenid` | string | Owner citizenid. |

**Returns**

- **rows** — array of hydrated rows; empty table when none or the table is not ready. Never nil.

**Example**

```lua
for _, row in ipairs(exports.kora_core:getByOwner(citizenid)) do
    print(row.plate, row.state)
end
```

**Representative console output**

```text
ABC123   garaged
```

#### `exports.kora_core:storeVehicle(plate, snapshot)`

Mark a vehicle garaged and snapshot its condition. Does not delete the live entity: the caller does that after success. Yields.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `plate` | string | Plate. |
| `snapshot?` | table | `{fuel?, engineHealth?, bodyHealth?, mods?, position?, garageId?, ownerCitizenId?}`. Absent condition fields keep the stored value (COALESCE). `mods` and `position` are JSON-encoded. `garageId` (string, 1 to 50 chars) selects the strict path; `ownerCitizenId` only applies there; `position` only applies on the loose path. |

**Returns**

- **true** — row updated.
- **false, 'unknown vehicle'** — no row for the plate.
- **false** — second return value is the reason: 'vehicle is impounded'.
- **false, 'invalid garage id'** — strict path: not a string or length outside 1 to 50.
- **false, 'vehicle ownership changed'** — strict path: `ownerCitizenId` differs from the row's `citizenid`.
- **false, 'vehicle is no longer available'** — strict path: no row matched `state = out` (already garaged, or concurrent change).
- **false, err** — SQL error string.

**Example**

```lua
local ok, err = exports.kora_core:storeVehicle(plate, {
    garageId = 'legion_a',
    ownerCitizenId = citizenid,
    fuel = fuel,
    engineHealth = engineHealth,
    bodyHealth = bodyHealth,
})
if ok then DeleteEntity(vehicle) end
```

**Representative console output**

```text
-- ok = true
```

#### `exports.kora_core:tagVehicle(entity, id)`

Set the server-only `vehicleid` state bag on a spawned owned vehicle. Call only after the entity exists and the row moved to `out`. `spawnVehicle` already calls this.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entity` | integer | Server entity handle of an existing entity. |
| `id` | integer | `player_vehicles.id`, a positive integer. |

**Returns**

- **true** — state bag set (`Entity(entity).state:set('vehicleid', id, false)`).
- **false** — ConVar `kora:vehicleIdStateBag` is 0; `id` is not a positive integer; `entity` is not a non-zero number or does not exist. No reason string.

**Example**

```lua
local tagged = exports.kora_core:tagVehicle(vehicle, row.id)
```

**Representative console output**

```text
true
```

#### `exports.kora_core:spawnVehicle(src, plate, coords, heading, expectedOwner)`

Spawn an owned or fleet vehicle as a networked entity and mark it `out`. Yields (SQL and polling).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player the vehicle is spawned for: its routing bucket is used and it receives the condition event. |
| `plate` | string | Plate; trimmed and uppercased before lookup. |
| `coords` | table | `vector3` or `{x, y, z}`. Not validated. |
| `heading?` | number | Default 0.0. |
| `expectedOwner?` | string | Owner precondition (citizenid) for trusted callers such as property providers. Checked on load and again in the UPDATE. |

**Returns**

- **networkId** — positive integer, the vehicle is out in the world.
- **false, 'invalid plate'** — not a string or empty after trimming.
- **false, 'vehicle spawn already in progress'** — another spawn of the same normalised plate is running.
- **false** — second return value is the reason: 'unknown vehicle'.
- **false, 'vehicle ownership changed'** — `expectedOwner` differs.
- **false, 'vehicle is impounded'** — retrieve it first with `retrieveImpound`.
- **false** — second return value is the reason: 'vehicle is already out'.
- **false** — second return value is the reason: 'failed to create vehicle'.
- **false, 'failed to network vehicle'** — no positive network id within `Config.garage.spawnNetworkIdTimeout` ms; the entity is deleted.
- **false, 'vehicle is no longer available' or the SQL error** — the conditional update to `out` did not affect one row; the entity is deleted.
- **false, message** — the body raised an error (for example nil `coords`); the entity is deleted and the error text is returned.

**Example**

```lua
local networkId, err = exports.kora_core:spawnVehicle(src, 'ABC123', vector3(215.8, -810.1, 30.7), 160.0, citizenid)
if not networkId then
    TriggerClientEvent('QBCore:Notify', src, err or 'could not spawn', 'error')
end
```

**Representative console output**

```text
-- networkId = 4821
```

#### `exports.kora_core:impound(plate, fee, impoundLot)`

Set a vehicle to `impounded` with a fee, lot and timestamp. Does not despawn a live entity and does not check the previous state. Yields.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `plate` | string | Plate. |
| `fee` | number | Fee stored in `impound_fee` (unsigned int column). Not validated here. |
| `impoundLot?` | string | Lot name (varchar(50)); nil stores NULL. |

**Returns**

- **true** — updated.
- **false** — second return value is the reason: 'unknown vehicle'.
- **false, err** — SQL error string.

**Example**

```lua
local ok, err = exports.kora_core:impound('ABC123', 500, 'davis_lot')
```

**Representative console output**

```text
-- ok = true
```

#### `exports.kora_core:retrieveImpound(src, plate)`

Clear the impound flag and return the vehicle to `garaged`. The caller must charge the fee beforehand. Yields.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Requesting player. For civilian rows their citizenid must equal the row's owner; job-fleet rows (no citizenid) do not check `src`. |
| `plate` | string | Plate. |

**Returns**

- **true** — state is now `garaged`; `impound_fee`, `impound_lot` and `impounded_at` are cleared.
- **false** — second return value is the reason: 'unknown vehicle'.
- **false** — second return value is the reason: 'vehicle is not impounded'.
- **false, 'not your vehicle'** — civilian row and the caller's citizenid differs (also when the caller is not logged in).
- **false, 'vehicle is no longer impounded'** — concurrent change.
- **false, err** — SQL error string.

**Example**

```lua
if exports.kora_core:removeMoney(src, 'bank', fee, 'impound fee') then
    local ok, err = exports.kora_core:retrieveImpound(src, plate)
end
```

**Representative console output**

```text
-- ok = true
```

#### `exports.kora_core:updateState(plate, patch)`

Partial condition update for periodic autosave of an `out` vehicle. Unlike `storeVehicle` it does not change `state` and does not refuse an impounded vehicle. Absent fields keep their stored value. Yields.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `plate` | string | Plate. |
| `patch` | table | `{fuel?, engineHealth?, bodyHealth?, mods?, position?}`; `mods` and `position` are JSON-encoded. Required: a nil patch raises an error. |

**Returns**

- **true** — statement ran.
- **false** — unknown plate or SQL failure. No reason string.

**Example**

```lua
exports.kora_core:updateState(plate, {
    fuel = fuel,
    engineHealth = engineHealth,
    position = { x = coords.x, y = coords.y, z = coords.z },
})
```

**Representative console output**

```text
-- true
```

#### `exports.kora_core:saveVehicleProperties(plate, properties)`

Persist a full vehicle-properties snapshot (the result of `Kora.vehicle.getProperties`) without changing state. Server only: authorise and charge for tuning first. The keys `plate`, `model`, `fuelLevel`, `engineHealth` and `bodyHealth` are removed from the stored `mods`; `fuelLevel`, `engineHealth` and `bodyHealth` go to their dedicated columns. The `mods` column is overwritten as a whole.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `plate` | string | Plate. |
| `properties` | table | Properties snapshot. |

**Returns**

- **true** — saved.
- **false** — second return value is the reason: 'vehicle properties must be a table'.
- **false, 'unknown vehicle'** — also returned when the SQL update failed.

**Example**

```lua
local ok, err = exports.kora_core:saveVehicleProperties(plate, properties)
```

**Representative console output**

```text
-- ok = true
```

#### `exports.kora_core:deleteVehicle(plate)`

Soft-delete a vehicle row (`deleted_at = NOW()`). Does not delete a live entity and does not free the plate for a new `createVehicle`, because the unique index includes soft-deleted rows. Yields.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `plate` | string | Plate. |

**Returns**

- **true** — the statement ran, even if no row matched.
- **false** — SQL failure. No reason string.

**Example**

```lua
if exports.kora_core:deleteVehicle('ABC123') then
    print('vehicle removed from garage records')
end
```

**Representative console output**

```text
vehicle removed from garage records
```

### Common use cases

- Dealership resource: `createVehicle` after payment.
- Garage resource: `spawnVehicle` on take-out, `storeVehicle` with `garageId` and `ownerCitizenId` on store, `updateState` on a timer.
- Impound job: `impound` then `retrieveImpound` after the fee is paid.

### Limits and related APIs

No function validates the player's position or the fee. The loose `storeVehicle` path and `impound` have no state precondition. Unsigned SQL columns (`fuel`, `engine_health`, `body_health`) may reject out-of-range values with an SQL error string.

### Related guides

- [Player: getPlayerData](./player.md)
- [Money: charging fees](./money.md)
- [Persistence](./persistence.md)
- [Config.garage](./configuration.md)

## Client

One net event, no exports: apply a server-committed fuel and engine health to a freshly spawned vehicle.

Namespace: `exports.kora_core` · Source: `modules/garage/client.lua`

### Terms used on this page

| Term | Meaning |
| --- | --- |
| kora_core:client:vehicleCondition | `(netId, fuel, engineHealth)`. Ignored unless the event source is 65535 (server). `netId` must be a positive integer; fuel and engine health finite numbers. Waits up to 5000 ms for the entity, requires a vehicle, requests control for 1000 ms, then calls `SetVehicleFuelLevel` and `SetVehicleEngineHealth`. |

### Limits and related APIs

Other clients and resources cannot make this handler run for arbitrary vehicles from the client side: the source check drops it.

### Related guides

- [Garage server realm](./garage.md)

## Implementation notes and quick reference

`Core.garage` stores owned vehicles in `player_vehicles` for civilian garages and
job fleets. It has no UI and never touches money; garage, dealership and impound
resources build on it. All functions are server-side and yield (database access).

### API

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

#### storeVehicle snapshot

`snapshot` may contain `fuel`, `engineHealth`, `bodyHealth`, `mods`, `position`,
`garageId` and `ownerCitizenId`.

- With `garageId` (1 to 50 characters) the update only succeeds when the row is
  currently `out` (and, with `ownerCitizenId`, still owned by that citizen); it sets
  `garage_id`. Errors: `invalid garage id`, `vehicle ownership changed`,
  `vehicle is no longer available`.
- Without `garageId` the row is set to `garaged` whatever its previous state,
  except that impounded vehicles are refused (`vehicle is impounded`).

#### spawnVehicle

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
