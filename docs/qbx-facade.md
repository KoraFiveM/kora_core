# qbx facade (opt-in)

Lets stock `ox_inventory` run with `setr inventory:framework "qbx"` against
kora_core. Implementation: `compat/server/qbx.lua`. Off by default.

```
setr kora:qbxFacade true      # or Config.compat.qbxFacade = true
setr inventory:framework "qbx"
```

No resource named `qbx_core` / `qbx_vehicles` exists and kora_core does not
`provide` them (a fake qbx_core would flip third-party framework detection).
The export identities are published with the `__cfx_export_` hijack. The facade
refuses to start if a real `qbx_core` or `qbx_vehicles` resource exists. The
`lib.checkDependency('qbx_core', ...)` asserts in ox_inventory are satisfied by
the `ox_lib` shim (G-BR1), not here.

## Exports
| export | behaviour |
|---|---|
| `qbx_core:GetPlayer(src)` | QB player (`PlayerData` legacy view, `Functions.*`, and method forms `player.Fn()` / `player:Fn()`). Deviations below. `nil` if not loaded |
| `qbx_core:GetPlayersData()` | array of `PlayerData`, ordered by source |
| `qbx_core:CanUseItem(name)` | `function(source, data)` bound to the item's registered useable, else `nil` |
| `qbx_core:GetGroups(src)` | `{ [name] = zeroBasedGrade }`: active job + gang (`none` omitted). `nil` if not loaded |
| `qbx_core:IsGradeBoss(group, grade)` | zero-based grade; checks jobs then gangs registries |
| `qbx_vehicles:GetVehicleIdByPlate(plate)` | `player_vehicles.id` for the trimmed plate, `deleted_at IS NULL`; `nil` if none |

`GetPlayer` deviations: `Functions.SetPlayerData('items', t)` updates the
in-memory mirror only (no dirty flag, no delta, see "Inventory ownership"), and
`Functions.SetMoney` is a no-op when the balance already equals the amount.

## Events and state bags
- `qbx_core:server:playerLoggedOut(src)`: once per session, from `QBCore:Server:OnPlayerUnload` (logout and drop).
- `qbx_core:server:onGroupUpdate(src, group, grade)` and client `qbx_core:client:onGroupUpdate(group, grade)`: diff-based from `OnJobUpdate`/`OnGangUpdate`; a removed group is sent with a `nil` grade.
- client `qbx_core:client:setGroups(groups)`: once per load.
- `Player(src).state.loadInventory = true` (replicated) one tick after `Core.player.login` completes (`isLoggedIn` already true); set to `false` at logout/drop. `isLoggedIn` is the existing core bag.

## Inventory ownership (important)
With ox_inventory, ox owns `players.inventory`. The facade never marks that
column dirty, so kora's persistence does not overwrite ox's JSON. Do not run
the legacy kora inventory engine (`Core.inventory.addItem` fallback) alongside
it; that is the gateway work in plan item 1.7 (G-BR9).

## Not covered here
- Inactive kora_multijob roster entries are not groups.
- `Entity(veh).state.vehicleid` is not set; ox falls back to `GetVehicleIdByPlate`.
- Optional DDL: `sql/optional/qbx_vehicle_inventory_columns.sql` (unregistered, never auto-run; ox adds the columns itself).
