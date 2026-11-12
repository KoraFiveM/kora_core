---
title: qbx facade (opt-in)
sidebar_position: 8
---

# qbx facade (opt-in)

Lets stock `ox_inventory` run with `setr inventory:framework "qbx"` against
kora_core. Implementation: `compat/server/qbx.lua`. Off by default; while off it
registers nothing.

```cfg
setr kora:qbxFacade true      # or Config.compat.qbxFacade = true
setr inventory:framework "qbx"
```

No resource named `qbx_core` or `qbx_vehicles` exists and kora_core does not
`provide` them (a fake `qbx_core` would change third-party framework detection).
The export identities are published with kora_lib's export bridge. The facade
stays off, with a console message, if a real `qbx_core` or `qbx_vehicles` resource
exists. ox_inventory's `lib.checkDependency('qbx_core', ...)` checks are not
handled here; they must be satisfied by the `ox_lib` shim in use.

## Exports

| Export | Behaviour |
| --- | --- |
| `qbx_core:GetPlayer(src)` | QB player (legacy `PlayerData`, `Functions.*`, and method forms `player.Fn()` / `player:Fn()`). Deviations below. `nil` if not loaded. |
| `qbx_core:GetPlayersData()` | Array of legacy `PlayerData` copies, ordered by source. |
| `qbx_core:CanUseItem(name)` | `function(source, data)` bound to the item's registered useable, else `nil`. |
| `qbx_core:GetGroups(src)` | `[name] = zeroBasedGrade` for the active job and gang (gang `none` omitted). `nil` if not loaded. |
| `qbx_core:IsGradeBoss(group, grade)` | Zero-based grade; checks the jobs registry, then gangs. |
| `qbx_vehicles:GetVehicleIdByPlate(plate)` | `player_vehicles.id` for the plate as given or trimmed and upper-cased, ignoring deleted rows; `nil` if none. |

`GetPlayer` deviations: `Functions.SetPlayerData('items', t)` updates the in-memory
legacy view and the live `items` table only (no dirty flag, no delta; see
"Inventory ownership"), and `Functions.SetMoney` is a no-op when the balance
already equals the amount.

## Events and state bags

- `qbx_core:server:playerLoggedOut(src)`: once per session, from
  `QBCore:Server:OnPlayerUnload` (logout and drop).
- `qbx_core:server:onGroupUpdate(src, group, grade)` and client
  `qbx_core:client:onGroupUpdate(group, grade)`: diff-based, from
  `QBCore:Server:OnJobUpdate`/`OnGangUpdate`; a removed group is sent with a `nil`
  grade.
- Client `qbx_core:client:setGroups(groups)`: once per load.
- `Player(src).state.loadInventory = true` (replicated) once `isLoggedIn` is true
  after login (retried every 50 ms, up to 40 times); set to `false` at logout and
  drop.
- At login a missing `metadata.licences` table is created, because ox_inventory
  reads it.

## Inventory ownership

With ox_inventory, ox owns the `players.inventory` JSON. The facade never marks
that column dirty, so kora_core's persistence does not overwrite ox's data. Do not
run kora_core's legacy fallback inventory (`Config.inventory.allowLegacyFallback`)
alongside it.

## Not covered

- Inactive kora_multijob roster entries are not groups.
- The facade does not set `Entity(veh).state.vehicleid`; `Core.garage.spawnVehicle`
  and `tagVehicle` do, and otherwise ox falls back to `GetVehicleIdByPlate`.
- ox_inventory adds its own vehicle inventory columns; kora_core ships no extra SQL
  for them.
