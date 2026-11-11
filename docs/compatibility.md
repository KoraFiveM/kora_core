---
title: qb-core compatibility
sidebar_position: 9
---

# qb-core compatibility

kora_core declares `provide 'qb-core'`, which satisfies other resources'
`dependency 'qb-core'`. The `qb-core` exports themselves are published with
kora_lib's export bridge (`Kora.compat.provideExport`). `provide` does not make
`@qb-core/...` file includes resolve; a separate `[compat]/qb-core` resource does
that (kora_core ships `shared/locale.lua` in its `files` for it). kora_core does
not provide `qb-multicharacter` or `qb-inventory`.

The legacy layer calls the native modules directly, so legacy and native calls
share validation, persistence, replication and events.

## Exports

```lua
local QBCore = exports['qb-core']:GetCoreObject()
local subset = exports['qb-core']:GetCoreObject({ 'Functions', 'Shared' })
```

Both realms export `GetCoreObject(filters)`, `GetShared(namespace, key)`,
`GetSharedItems`, `GetSharedVehicles`, `GetSharedJobs`, `GetSharedGangs`,
`GetSharedWeapons`, and every function in `QBCore.Functions` under its own name
(for example `exports['qb-core']:GetPlayer(source)` on the server,
`exports['qb-core']:SpawnVehicle(...)` on the client). `GetShared` accepts the
namespace in any case (`items`, `Items`, `vehiclehashes`, `starteritems`, ...).
On the server these exports are published only while
`Config.compat.coreObjectExport` is `true`. Functions added later with
`QBCore.Functions.SetMethod` are exported too. The client also exports
`DrawText`, `ChangeText`, `HideText` and `KeyPressed`.

## Core object

| Field | Contents |
| --- | --- |
| `QBCore.Functions` | Legacy helpers (lists below). |
| `QBCore.Player` | `Login`, `Logout`, `Save`, `SaveOffline`, `CreatePlayer`, `DeleteCharacter`, `ForceDeleteCharacter`, `CheckPlayerData`, `ForceUpdatePlayerData`, `GetOfflinePlayer`, `GetPlayerByLicense`, `GetOfflinePlayerByLicense`, `CreateCitizenId`, `CreateFingerId`, `CreateWalletId`, `CreateSerialNumber` (server). |
| `QBCore.Players` | `[source] = Player` for loaded players (server). |
| `QBCore.PlayersByCitizenId` | `[citizenid] = Player`, filled on login and lookup (server). |
| `QBCore.PlayerData` | Client: legacy view of the local mirror, updated in place. |
| `QBCore.Shared` | Live registry views `Items`, `Vehicles`, `VehicleHashes`, `Jobs`, `Gangs`, `Weapons`, `Locations`; `StarterItems`, `MaleNoGloves`, `FemaleNoGloves`, `ForceJobDefaultDutyAtLogin = true`; helpers `Round`, `Trim`, `SplitStr`, `RandomStr`, `RandomInt`, `FirstToUpper`, `IsFunction`; client `ChangeVehicleExtra`, `SetDefaultVehicleExtras`. |
| `QBCore.Config` | Stock shape built from kora_core settings: `MaxPlayers` (`sv_maxclients`), `DefaultSpawn`, `Money` (`MoneyTypes` = `Config.money.default`, `DontAllowMinus`, `MinusLimit`), `Player` (`MaxWeight`, `MaxInvSlots`, `Bloodtypes`, `PlayerDefaults`), `Server` (`Closed`, `ClosedReason`, `Whitelist = false`, `WhitelistPermission = 'admin'`, `PVP = true`, `Discord` from the `kora_discord` convar, `Permissions = { 'god', 'admin', 'mod' }`), `Commands.OOCColor`, `Notify`. |
| `QBCore.Commands` | `Add`, `Refresh`, `List`, `IgnoreList` (server). |
| `QBCore.UsableItems` | `[name] = { func, resource }` (server). |
| `QBCore.ServerCallbacks`, `QBCore.ClientCallbacks` | Pending callback bookkeeping. |
| `QBCore.Player_Buckets`, `QBCore.Entity_Buckets` | Routing-bucket tracking (server). |
| `QBCore.Debug`, `QBCore.ShowError`, `QBCore.ShowSuccess` | Print helpers. |

`QBCore.Shared.*` maps are rebuilt from the registries. New code should use
`getShared`/`allShared` or `Kora.shared.*` and must not cache or write those maps.

## Player object (server)

`QBCore.Functions.GetPlayer(source)` returns a cached object with a `PlayerData`
legacy view and `Functions`. Every function is also available as a method:
`Player.Functions.AddMoney(...)`, `Player.AddMoney(...)` and `Player:AddMoney(...)`
all work. Calls on an object whose character is no longer loaded return
`false, 'player is no longer loaded'`.

| Method | Native call |
| --- | --- |
| `GetName`, `GetPlayerData` | Legacy view. |
| `SetJob(name, grade)`, `SetGang(name, grade)` | `setJob`/`setGang` with the name lower-cased and the zero-based grade converted. |
| `SetJobDuty(onDuty)` | `setJobDuty`. |
| `SetJobData(key, value)`, `SetGangData(key, value)` | Writes one field; `SetJobData('onduty', v)` goes through `setJobDuty`. |
| `AddMoney(type, amount, reason, ignoreTax)`, `RemoveMoney(...)` | `addMoney`/`removeMoney`; account lower-cased; amount 0 is accepted as a no-op. |
| `SetMoney(type, amount, reason)`, `GetMoney(type)` | `setMoney`/`getMoney`. |
| `AddItem`, `RemoveItem`, `GetItemByName`, `GetItemsByName`, `GetItemBySlot`, `ClearInventory`, `SetInventory`, `HasItem` | Inventory gateway. |
| `SetMetaData(key, value)`, `GetMetaData(key)` | Metadata; hunger/thirst clamped to 0..100. |
| `SetCharInfo(key, value)`, `SetCreditCard(number)` | Writes `charinfo`. |
| `SetPlayerData(key, value)` | Writes a root. Immutable roots are refused. A root with no database column is written in memory only (with a warning when `Config.compat.warnOnUnknownRoot`). |
| `UpdateClient(key, ...)` / `UpdatePlayerData` | Applies changes made directly to `Player.PlayerData` back through the funnel, then fires `QBCore:Server:OnPlayerUpdated` and `QBCore:Client:OnPlayerUpdated`. |
| `Save()` | Reconciles and queues an immediate save. |
| `Logout()` | `logout`. |
| `Notify(text, type, length)` | `QBCore:Notify` to the player. |
| `AddJobReputation(amount)` / `AddJobRep` | `metadata.jobrep[job]`. |
| `GetRep`, `AddRep`, `RemoveRep` | `metadata.rep`, never below 0. |
| `AddMethod(name, fn)`, `AddField(name, value)` | Extend this object. |

Important differences:

- An object returned to another resource carries a `PlayerData` copy made at call
  time; call `Player.Functions.GetPlayerData()` for fresh data.
- The legacy view uses zero-based `grade.level` and adds `grade.payment` and
  `grade.isboss`, `position.w` beside `h`, `optin` (default true), `items` always a
  table, and the stock `CheckPlayerData` metadata/charinfo defaults
  (`criminalrecord`, `phonedata`, `inside`, `rep`, `callsign`,
  `licences.business`, ...). Missing `charinfo.account`, `metadata.bloodtype`,
  `fingerprint`, `walletid` and `phonedata.SerialNumber` are derived
  deterministically from the citizen ID. None of these defaults are saved.
- Physical cash: when the inventory provider owns cash, `PlayerData.money.cash`
  shows the real item balance. Writing `SetPlayerData('money', t)` applies the
  cash difference against the balance the script saw, through `addMoney`/
  `removeMoney` (reason `qb-compat-setplayerdata`, untaxed); a removal larger than
  the real balance refuses the whole write.

Offline objects (`GetOfflinePlayerByCitizenId`, `GetOfflinePlayerByLicense`,
`QBCore.Player.CreatePlayer(data, true)`) have the same method names working on an
in-memory copy; `Save()` writes it with `QBCore.Player.SaveOffline`, and `Logout`
and `Notify` do nothing.

## QBCore.Functions (server)

- Players: `GetPlayer` (source or identifier), `GetPlayerByCitizenId`,
  `GetPlayerByPhone`, `GetPlayerByAccount`, `GetPlayerByCharInfo`,
  `GetPlayerByLicense` (falls back to the offline lookup), `GetOfflinePlayerByCitizenId`,
  `GetOfflinePlayerByLicense`, `GetPlayers`, `GetQBPlayers`, `GetIdentifier`,
  `GetSource`, `IsLicenseInUse`. Identifier lookups accept `license:xxx` or the
  bare value.
- Jobs: `GetPlayersByJob(job, checkOnDuty)` (matches the job name or job type;
  returns sources and count),
  `GetPlayersOnDuty`, `GetDutyCount`, `PaycheckInterval`.
- Callbacks: `CreateCallback`, `TriggerCallback`, `TriggerClientCallback` (see
  [Callbacks](./features/callbacks.md)).
- Items: `CreateUseableItem`, `CanUseItem`, `UseItem`, `HasItem`.
- Permissions: `HasPermission` (string or list), `GetPermission` (map of held
  levels), `AddPermission`, `RemovePermission`, `IsOptin`, `ToggleOptin` (admins
  only), `IsWhitelisted`.
- Bans and moderation: `IsPlayerBanned` (reads `bans`; `NULL` expiry is permanent;
  expired rows are deleted), `ExploitBan` (inserts a permanent ban and drops the
  player), `Kick`.
- World: `GetCoords`, `GetClosestPlayer`, `GetClosestPed`, `GetClosestVehicle`,
  `GetClosestObject`, buckets (`GetBucketObjects`, `SetPlayerBucket`,
  `SetEntityBucket`, `GetPlayersInBucket`, `GetEntitiesInBucket`).
- Vehicles: `SpawnVehicle(source, model, coords, warp)`,
  `CreateVehicle(source, model, vehtype, coords, warp)`, `CreateAutomobile`.
- Shared data: `AddItem`, `AddItems`, `UpdateItem`, `RemoveItem`, `AddJob`,
  `AddJobs`, `UpdateJob`, `RemoveJob`, `AddGang`, `AddGangs`, `UpdateGang`,
  `RemoveGang`. They write the registries and return `true, 'success'` or
  `false, reason` (`item_exists`, `job_not_exists`, ...).
- Object extension: `SetMethod`, `SetField`, `AddPlayerMethod`, `AddPlayerField`.
- Misc: `Notify`, `GetCoreVersion`, `GetDatabaseInfo`, `CreateAccountNumber`,
  `CreatePhoneNumber`, `ExecuteSql` (deprecated; forwards to `Kora.sql.query`,
  `wait` ignored, warns on each call).

`IsPlayerBanned` and `IsWhitelisted` are available to other resources, but
kora_core does not enforce bans or the whitelist on connect. While the server is
closed with `/closeserver`, connecting players without the whitelist permission
are refused.

## QBCore.Functions (client)

`GetPlayerData(cb)`, `GetName`, `GetCoords`, `HasItem` (asks kora_inventory when
started), `Notify` (via `Kora.notify`; accepts kora locale references),
`Progressbar` (via the `progressbar` export provided by kora_lib, including
`prop`/`propTwo`), `IsWearingGloves`, `LookAtEntity`, `PlayAnim`, `RequestAnimDict`,
`LoadAnimDict`, `LoadAnimSet`, `LoadModel`, `LoadParticleDictionary`,
`StartParticleAtCoord`, `StartParticleOnEntity`, `AttachProp`, `GetClosestBone`,
`GetBoneDistance`, `GetVehicles`, `GetObjects`, `GetPlayers`,
`GetPlayersFromCoords`, `GetPeds`, `GetClosestPlayer`, `GetClosestPed`,
`GetClosestVehicle`, `GetClosestObject`, `SpawnVehicle`, `DeleteVehicle`,
`GetPlate`, `GetVehicleLabel`, `GetVehicleProperties`, `SetVehicleProperties`,
`SpawnClear`, `DrawText`, `DrawText3D`, `Draw3DText`, `GetStreetNametAtCoords`,
`GetZoneAtCoords`, `GetCardinalDirection`, `GetCurrentTime`, `GetGroundZCoord`,
`GetGroundHash`, `CreateClientCallback`, `CreateCallback`, `TriggerCallback`.

Vehicle colour snapshots from `GetVehicleProperties` are saved as `r`, `g`, `b`
objects; `SetVehicleProperties` also accepts arrays and objects with numeric string
keys. Client `SpawnVehicle` asks the server for a networked vehicle; see
[Vehicle spawn](./vehicle-spawn.md).

The draw-text events and exports (`DrawText`, `ChangeText`, `HideText`,
`KeyPressed`) draw a simple native text box at the `left`, `right` or `top`
position.

## Client PlayerData

`QBCore.PlayerData` is updated in place from the replicated mirror. After every
snapshot or delta the client fires `QBCore:Player:SetPlayerData` locally (when
`Config.compat.fireLegacyPlayerDataEvent`); when a delta only changed `items`, the
event is delayed by `Config.compat.inventoryPlayerDataEventInterval` and merged.
With `jobUpdateEventSource` `client` or `both`, job and gang changes also fire
`QBCore:Client:OnJobUpdate`/`OnGangUpdate` and `QBCore:Client:OnPlayerUpdated`
locally.

If another resource fires `QBCore:Player:SetPlayerData` itself, the data is copied
into the mirror with a warning; the next server snapshot overwrites it.
`QBCore:Client:SharedUpdate` is a no-op (the registries are server-authoritative),
and `QBCore:Client:OnPlayerUpdated` ignores the pushed value and re-reads the
mirror.

## Commands

`QBCore.Commands.Add(name, help, args, argsRequired, cb, permission, ...)`
registers through `addCommand` with the lowest of the given levels, adds
`command.<name>` ACEs for `kora_core.<level>` (except `god` and `user`) and fires
`QBCore:Server:PreCommandExecution` before the callback. Extra levels make
`List[name].permission` an array. `QBCore.Commands.List` is keyed by lower-cased
name and includes `arguments`/`params`; it reflects commands present at the last
`Add` or `Refresh`. `QBCore:CallCommand` checks the `command.<name>` ACE and the
argument count like stock.

The 20 stock commands are on [Default qb-core commands](./default-commands.md).

## Legacy events

Server and client legacy events are listed on the [Events](./events.md) page.
Notable behaviour:

- `QBCore:Server:PlayerLoaded` passes the player object, the same one stored in
  `QBCore.Players[source]`.
- `QBCore:Client:OnPlayerLoaded` fires at login unless
  `Config.compat.deferClientPlayerLoaded` is on; then it waits for the client's
  `QBCore:Server:OnPlayerLoaded` (sent by kora_multichar and stock qb-spawn).
- `QBCore:Server:PlayerDropped` and `OnPlayerUnload` fire before the player is
  evicted, so `GetPlayer(source)` still works in handlers.
- `QBCore:UpdatePlayer` does not decay needs; it refreshes the HUD and saves.
- `QBCore:ToggleDuty` toggles duty with a notification.

### Stress events

`hud:server:GainStress(amount)` and `hud:server:RelieveStress(amount)` change the
sender's stress by a whole `amount` between 1 and 100 (clamped to 0..100), with
`Config.compat.stress` controlling the cooldown, job whitelist and an off switch.
They are ignored while a real `qb-hud` is started. The client receives
`hud:client:UpdateStress(value)` and a notification.

## qb-multicharacter and qb-spawn

kora_core answers the stock multicharacter protocol so a stock UI can work:

- Callbacks `qb-multicharacter:server:GetUserCharacters`, `GetNumberOfCharacters`,
  `setupCharacters`, `getSkin` (always `nil`), `deleteCharacter`, and
  `qb-spawn:server:getOwnedHouses` (always empty).
- Net events `qb-multicharacter:server:loadUserData` (select, then
  `qb-spawn:client:setupSpawns` and `qb-spawn:client:openUI`),
  `qb-multicharacter:server:createCharacter` (create, then
  `qb-multicharacter:client:closeNUIdefault`), `deleteCharacter` and `disconnect`.
  Failures send `multichar:client:selectFailed(err)`.

## Other compatibility pages

- [Default qb-core commands](./default-commands.md)
- [qbx facade for stock ox_inventory](./qbx-facade.md)
- [Stock vehicle spawn callbacks](./vehicle-spawn.md)
- [`player_vehicles` compatibility](./vehicles-compat.md)
