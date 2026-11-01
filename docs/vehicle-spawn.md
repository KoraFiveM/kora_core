# Stock vehicle spawn callbacks

`compat/server/qb-vehicles.lua` registers qb-core's `QBCore:Server:SpawnVehicle` and
`QBCore:Server:CreateVehicle` callbacks (`model, coords, warp` -> `netId`, or `nil` when refused).
Stock lets any client spawn any model anywhere; here the server validates and creates the entity.

`Config.compat.vehicleSpawnCallbacks`:

| mode | who | checks |
|---|---|---|
| `off` | nobody (callbacks not registered) | - |
| `admin` | kora admin permission | well-formed model name/hash and finite coords; audited |
| `limited` (default) | any loaded player | model in `QBCore.Shared.Vehicles` / `VehicleHashes` or `vehicleSpawn.allowModels`; coords within `maxDistance` (75 m) of the caller; `cooldownMs` between requests; at most `maxLive` (2) live vehicles per player, the oldest is deleted; audited under category `vehicle` |

`vehicleSpawn.grantKeys` gives the requester keys through `exports.kora_vehiclekeys:giveKeys(src, plate)` when that
resource is started. `deleteOnDrop` removes a player's compat-spawned vehicles when they leave.
`CreateVehicle` uses the `automobile` server setter, like stock `CreateAutomobile`.

Client `QBCore.Functions.SpawnVehicle(model, cb, coords, isnetworked, teleportInto)` and `QBCore:Command:SpawnVehicle`:
when `isnetworked ~= false` the request goes through `QBCore:Server:SpawnVehicle` and the returned entity is networked.
If the server refuses (mode `off`, model not allowed, too far, rate limit) it falls back to a local, non-networked vehicle
as before. Client-created networked entities are not used: strict OneSync entity lockdown deletes them.
