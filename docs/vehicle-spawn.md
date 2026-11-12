---
title: Vehicle spawn callbacks
sidebar_position: 9
---

# Stock vehicle spawn callbacks

`compat/server/qb-vehicles.lua` registers qb-core's `QBCore:Server:SpawnVehicle` and
`QBCore:Server:CreateVehicle` callbacks (`model, coords, warp`, answered with a
network ID, or `nil` when refused). Stock qb-core lets any client spawn any model
anywhere; here the server validates the request and creates the entity.

`Config.compat.vehicleSpawnCallbacks`:

| Mode | Who | Checks |
| --- | --- | --- |
| `off` | nobody (callbacks not registered) | none |
| `admin` | players with the `admin` permission | well-formed model name or hash; finite coordinates within 10000 on each axis; audited |
| `limited` (default) | any loaded player | model in `QBCore.Shared.Vehicles`/`VehicleHashes` or `vehicleSpawn.allowModels`; coordinates within `maxDistance` (75 m) of the caller; `cooldownMs` between requests; at most `maxLive` (2) live vehicles per player, the oldest is deleted; audited |

Every request (accepted or refused, with the reason) is logged with
`logEvent('vehicle', source, ...)`. `vehicleSpawn.grantKeys` gives the requester
keys through `exports.kora_vehiclekeys:giveKeys(source, plate)` when that resource
is started. `deleteOnDrop` removes a player's tracked vehicles when they leave.
`SpawnVehicle` uses `QBCore.Functions.SpawnVehicle` (server `CreateVehicle`, waits
until the requester owns the entity); `CreateVehicle` uses the `automobile` server
setter, like stock `CreateAutomobile`.

Client `QBCore.Functions.SpawnVehicle(model, cb, coords, isnetworked, teleportInto)`
and the `QBCore:Command:SpawnVehicle` client event: when `isnetworked ~= false` the
request goes through `QBCore:Server:SpawnVehicle` and the returned entity is
networked. If the server refuses (mode `off`, model not allowed, too far, rate
limit), the client falls back to a local, non-networked vehicle and prints a
one-time warning. Client-created networked vehicles are not used because strict
OneSync entity lockdown deletes them.
