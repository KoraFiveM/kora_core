---
title: "Compatibility"
sidebar_position: 16
---


# Compatibility

## Server

The server half of the qb-core compatibility layer. A resource written against qb-core calls `exports['qb-core']:GetCoreObject()`, `QBCore.Functions.*`, `Player.Functions.*`, legacy net events and the qb-multicharacter / qb-spawn callbacks; kora_core answers all of it and forwards each call to its native Core modules or to kora_lib. This page lists every converted call and what it becomes, plus the gates, validation and stubs.

Namespace: `qb-core` · Source: `compat/shared/coreobject.lua, compat/server/qb-core.lua, qb-core-events.lua, qb-vehicles.lua, qb-commands.lua, qb-multicharacter.lua, qb-spawn.lua, qbx.lua, fxmanifest.lua, config.lua (Config.compat)`

### Gating keys (Config.compat)

Every key that switches or tunes a converted behavior, with the shipped default. The file is a shared script, so the client reads the same table.

| Key | Default | Effect |
| --- | --- | --- |
| Config.compat.coreObjectExport | true | Server: registers the qb-core exports GetCoreObject, GetShared, GetSharedItems/Vehicles/Jobs/Gangs/Weapons and one export per QBCore.Functions entry. false removes all of them. The client registers its exports regardless. |
| Config.compat.callbackTimeoutMs | 5000 | How long CreateCallback and CreateClientCallback wait for the legacy handler to call its responder before the reply resolves empty. Also bounds the client await form of TriggerCallback. |
| Config.compat.jobUpdateEventSource | 'client' | Who emits QBCore:Client:OnJobUpdate and OnGangUpdate (and the job/gang OnPlayerUpdated): 'client' fires them locally on the client, 'server' sends them from the server, 'both' does both. |
| Config.compat.fireLegacyPlayerDataEvent | true | Client fires QBCore:Player:SetPlayerData locally from the replication mirror. false stops the event. |
| Config.compat.inventoryPlayerDataEventInterval | 250 | Milliseconds an inventory-only QBCore:Player:SetPlayerData notification is coalesced. 0 fires on every delta. |
| Config.compat.warnOnUnknownRoot | true | Print a warning when Player.Functions.SetPlayerData targets a root key with no database column mapping (the value will not persist). |
| Config.compat.clientMetadataKeys | &#123; hunger, thirst, stress = true &#125; | Allow-list for client writes through QBCore:Server:SetMetaData. Any other key is rejected. Do not add money, jail, isdead, inlaststand, licences, criminalrecord or callsign. |
| Config.compat.toggleDutyEvent | true | Registers the client-triggerable QBCore:ToggleDuty. false means job resources must own duty changes. |
| Config.compat.defaultCommands | true | Registers the 20 stock qb-core commands. A name already registered by another resource is kept. |
| Config.compat.vehicleSpawnCallbacks | 'limited' | Server callbacks QBCore:Server:SpawnVehicle and QBCore:Server:CreateVehicle: 'off' (not registered), 'admin' (admin permission only), 'limited' (any loaded player, validated). Also backs the networked client QBCore.Functions.SpawnVehicle. |
| Config.compat.vehicleSpawn.maxDistance | 75.0 | Metres between requested coordinates and the caller's ped ('limited' mode). |
| Config.compat.vehicleSpawn.cooldownMs | 2000 | Minimum time between spawn requests per player ('limited' mode). |
| Config.compat.vehicleSpawn.maxLive | 2 | Live compat-spawned vehicles per player; the oldest is deleted to make room. |
| Config.compat.vehicleSpawn.allowModels | &#123;&#125; | Extra model names accepted besides QBCore.Shared.Vehicles and VehicleHashes. |
| Config.compat.vehicleSpawn.grantKeys | true | Call kora_vehiclekeys:giveKeys for the requester when that resource is started. |
| Config.compat.vehicleSpawn.deleteOnDrop | true | Delete a player's compat-spawned vehicles when they leave. |
| Config.compat.deferClientPlayerLoaded | false | false: QBCore:Client:OnPlayerLoaded is sent at login. true: sent when the client triggers QBCore:Server:OnPlayerLoaded after spawn (stock timing). |
| Config.compat.stress | &#123; disabled = false, whitelistedJobs = &#123; leo, ambulance &#125;, cooldownMs = 250 &#125; | Rules for hud:server:GainStress and RelieveStress. Ignored while a real qb-hud is started. |
| Config.compat.fireSharedUpdateAtLogin | false | Also send QBCore:Client:SharedUpdate(QBCore.Shared) at login. Off because the registry snapshot already covers it. |
| Config.compat.qbxFacade | false | Publishes the qbx_core and qbx_vehicles surface. `setr kora:qbxFacade true` enables it too. Refuses to start while a resource named qbx_core or qbx_vehicles exists. |
| Config.dispatch.legacyEvents | true | Outside Config.compat: Core.dispatch.alert also fires police:server:policeAlert, police:client:policeAlert and hospital:client:ambulanceAlert. |

### QBCore.Functions (`QBCore.Functions.`)

#### Players and lookup

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Functions.GetPlayer(source)` | `Returns the cached QB Player wrapper built over the live Kora handle (CoreInternal.player.handle). Not the same object as Core.player.getPlayer, exports.kora_core:getPlayer(source), which returns the native handle. Accepts a numeric source or an identifier string (resolved through GetSource). nil when the player is not loaded.` |
| `QBCore.Functions.GetPlayerByCitizenId(citizenid)` | `Wrapper for the online player with that citizenid (index lookup, same wrapper as GetPlayer). nil when offline; does not fall back to the database. Native handle: Core.player.getPlayerByCitizenId, exports.kora_core:getPlayerByCitizenId(citizenid)` |
| `QBCore.Functions.GetPlayerByPhone(number)` | `Scans loaded players for `PlayerData.charinfo.phone == number`; returns the wrapper or nil` |
| `QBCore.Functions.GetPlayerByAccount(account)` | `Scans loaded players for `charinfo.account == account`; returns the wrapper or nil` |
| `QBCore.Functions.GetPlayerByCharInfo(property, value)` | `Scans loaded players for `charinfo[property] == value`; returns the wrapper or nil` |
| `QBCore.Functions.GetPlayerByLicense(license)` | `Online wrapper whose license identifier matches (prefixed or bare form), else falls back to GetOfflinePlayerByLicense. Returns nil for a non-string` |
| `QBCore.Functions.GetPlayers()` | `Core.player.getPlayers, exports.kora_core:getPlayers() (list of source ids)` |
| `QBCore.Functions.GetQBPlayers()` | `Table of source -> QB wrapper for every loaded handle (builds each through GetPlayer)` |
| `QBCore.Functions.GetIdentifier(source, 'license')` | `Core.identity.getIdentifiers, exports.kora_core:getIdentifiers(source), indexed by the kind; the kind defaults to Config.identity.primaryIdentifier` |
| `QBCore.Functions.GetSource(identifier)` | `Scans Core.identity.getIdentifiers of every loaded player; prefixed and bare forms of the same value match. Returns 0 when nothing matches` |
| `QBCore.Functions.IsLicenseInUse(license)` | `true when a loaded player already holds that license identifier (prefixed or bare)` |

#### Offline lookups

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Functions.GetOfflinePlayerByCitizenId(citizenid)` | `Loads the row with Core.persistence._load (internal, not exported) and returns an offline wrapper through QBCore.Player.CheckPlayerData(nil, ...). Raw native read: Core.persistence.getOfflinePlayerData, exports.kora_core:getOfflinePlayerData(citizenid). nil when no such character` |
| `QBCore.Functions.GetOfflinePlayerByLicense(license)` | `SQL lookup in `players` (license in prefixed and bare form, `deleted_at IS NULL`, lowest cid first), then GetOfflinePlayerByCitizenId. Forwards to Kora.sql.single` |

#### Callbacks

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Functions.CreateCallback('name', function(source, cb, ...) end)` | `Stores the handler in the legacy callback table and registers a Kora.callback.register wrapper that hands the handler a responder `cb`. The wrapper waits for `cb` up to Config.compat.callbackTimeoutMs (5000) and resolves empty on timeout. Also reachable through the raw QBCore:Server:TriggerCallback net event. Alias: Core.compat.createCallback` |
| `QBCore.Functions.TriggerCallback('name', source, cb, ...)` | `Kora.callback.trigger(source, name, ...) inside a new thread; cb receives every value the client handler returned` |
| `QBCore.Functions.TriggerClientCallback('name', source, cb, ...)` | `Raw wire only: stores cb in QBCore.ClientCallbacks[name .. source] and fires QBCore:Client:TriggerClientCallback to that client. The reply returns on QBCore:Server:TriggerClientCallback. Returns nothing; no timeout on the reply` |
| `QBCore.Functions.TriggerClientCallback('name', source, ...)` | `Same wire, synchronous form (first extra argument not callable): parks the calling thread on a promise and returns every reply value. No timeout, so a client that never answers parks the thread for good` |

#### Items and inventory

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Functions.CreateUseableItem('item', function(source, item) end)` | `Core.inventory.createUseable, exports.kora_core:createUseable(name, handler). Also accepts a table with `cb` or `callback`. Mirrors the record into QBCore.UsableItems; the entry is dropped when the owning resource stops` |
| `QBCore.Functions.CanUseItem('item')` | `Core.inventory.getUseable, exports.kora_core:getUseable(name); also refreshes QBCore.UsableItems[name]` |
| `QBCore.Functions.UseItem(source, item)` | `Core.inventory.useItem, exports.kora_core:useItem(source, item.name or item). When no useable is registered the module fires the local QBCore:Server:UseItem event and returns false` |
| `QBCore.Functions.HasItem(source, items, amount)` | `Core.inventory.hasItem, exports.kora_core:hasItem(source, nameOrList, amount)` |

#### Permissions and access

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Functions.HasPermission(source, 'admin')` | `Core.permissions.hasPermission, exports.kora_core:hasPermission(source, permission). Accepts an array of permission names too (any match passes), which the native call does not` |
| `QBCore.Functions.GetPermission(source)` | `Returns a set such as `&#123; god = true, admin = true &#125;` built by checking every name in QBCore.Config.Server.Permissions ({ 'god', 'admin', 'mod' }) with hasPermission. The native Core.permissions.getPermission returns one level string instead` |
| `QBCore.Functions.AddPermission(source, 'admin')` | `Core.permissions.addPermission, exports.kora_core:addPermission(source, permission); on success also runs QBCore.Commands.Refresh(source)` |
| `QBCore.Functions.RemovePermission(source, 'admin')` | `Core.permissions.removePermission, exports.kora_core:removePermission(source, permission) when IsPlayerAceAllowed(source, permission); then QBCore.Commands.Refresh(source)` |
| `QBCore.Functions.RemovePermission(source)` | `No permission argument: strips every group in QBCore.Config.Server.Permissions the player currently holds, refreshing commands after each` |
| `QBCore.Functions.IsOptin(source)` | `true only when the player has a license identifier, holds admin, and `PlayerData.optin == true`. Not Core.permissions.isOptin (which treats anything but `optin == false` as opted in)` |
| `QBCore.Functions.ToggleOptin(source)` | `Admin only and needs a license: flips PlayerData.optin through Player.Functions.SetPlayerData('optin', not current)` |
| `QBCore.Functions.IsWhitelisted(source)` | `true when QBCore.Config.Server.Whitelist is false, else HasPermission(source, QBCore.Config.Server.WhitelistPermission)` |
| `QBCore.Functions.IsPlayerBanned(source)` | `Reads the `bans` table by license (prefixed and bare). Returns true plus a message for a permanent or unexpired ban; an expired row is deleted and false is returned. Forwards to Kora.sql.single / Kora.sql.query` |
| `QBCore.Functions.Kick(source, reason, setKickReason, deferrals)` | `Builds the stock kick text (reason plus Discord line from QBCore.Config.Server.Discord), calls setKickReason when given, updates deferrals and waits 2500 ms when deferrals are passed, then DropPlayer(source, reason)` |
| `QBCore.Functions.ExploitBan(playerId, origin)` | `Inserts a permanent ban row (expire 2147483647, bannedby 'Anti Cheat') through Kora.sql.insert, drops the player, then fires the local qb-log:server:CreateLog event (category anticheat)` |

#### Utilities

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Functions.Notify(source, text, 'success', 5000)` | `TriggerClientEvent('QBCore:Notify', source, text, type, length); the client handler forwards to Kora.notify.send` |
| `QBCore.Functions.ExecuteSql(wait, query, cb)` | `Deprecated shim: prints a warning, ignores `wait`, runs Kora.sql.query(query, {}) in a thread and calls cb(rows). Use Kora.sql.query or exports.kora_sql:query` |
| `QBCore.Functions.PaycheckInterval()` | `Config.jobs.paycheckInterval, default 300000 ms when unset` |
| `QBCore.Functions.GetCoords(entity)` | `vector4(GetEntityCoords(entity), GetEntityHeading(entity))` |
| `QBCore.Functions.GetCoreVersion(invokingResource)` | `The kora_core fxmanifest `version` (prints the caller name when one is given)` |
| `QBCore.Functions.GetDatabaseInfo()` | `Parses the `mysql_connection_string` convar (URI or key=value form) into `&#123; exists, database &#125;`` |
| `QBCore.Functions.CreateAccountNumber()` | `Random 'US0x' + 'QBCore' + digits account string; retries up to 100 times against `players.charinfo.account` via Kora.sql.scalar, logs an error and returns nil if all collide` |
| `QBCore.Functions.CreatePhoneNumber()` | `Random 10-digit number checked unique against `players.charinfo.phone` (same retry rule)` |

#### Job and duty

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Functions.GetPlayersByJob('police', checkOnDuty)` | `Scans QBCore.Players for `job.name == arg or job.type == arg` (a name or a job type, indistinguishable); returns (sources, count). Native indexed lookups: Core.jobs.getPlayersByJob, exports.kora_core:getPlayersByJob(name, onDutyOnly) and Core.jobs.getPlayersByJobType` |
| `QBCore.Functions.GetPlayersOnDuty('police')` | `GetPlayersByJob(job, true): (sources, count) of on-duty matches` |
| `QBCore.Functions.GetDutyCount('police')` | `Count from GetPlayersByJob(job, true). Native: Core.jobs.getDutyCount, exports.kora_core:getDutyCount(name)` |

#### Entities, closest and routing buckets

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Functions.GetClosestPlayer(source, coords)` | `Kora.closest.player(source, coords); returns (playerId, distance), (-1, -1) when none` |
| `QBCore.Functions.GetClosestObject(source, coords)` | `Kora.world.getClosestEntity('object', coords); returns (entity, distance) or (-1, -1). Coords default to the caller ped` |
| `QBCore.Functions.GetClosestVehicle(source, coords)` | `Kora.world.getClosestEntity('vehicle', coords); returns (entity, distance) or (-1, -1)` |
| `QBCore.Functions.GetClosestPed(source, coords)` | `Kora.world.getClosestEntity('ped', coords) excluding the caller ped; returns (entity, distance) or (-1, -1)` |
| `QBCore.Functions.GetBucketObjects()` | `Returns QBCore.Player_Buckets, QBCore.Entity_Buckets (the maps the compat keeps)` |
| `QBCore.Functions.SetPlayerBucket(source, bucket)` | `Core.player.setPlayerBucket, exports.kora_core:setPlayerBucket(source, bucket). Also sets the `instance` state bag, records QBCore.Player_Buckets[license] and fires the local kora_voice:server:bucketChanged event` |
| `QBCore.Functions.SetEntityBucket(entity, bucket)` | `SetEntityRoutingBucket plus QBCore.Entity_Buckets[entity]; false when either argument is missing` |
| `QBCore.Functions.GetPlayersInBucket(bucket)` | `Sources recorded in QBCore.Player_Buckets with that bucket. Only players moved through SetPlayerBucket are tracked` |
| `QBCore.Functions.GetEntitiesInBucket(bucket)` | `Entities recorded in QBCore.Entity_Buckets with that bucket (only those set through SetEntityBucket)` |

#### Vehicles

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Functions.SpawnVehicle(source, model, coords, warp)` | `Server-created networked vehicle (CreateVehicle) waited on through Kora.loops.controlled (5000 ms); requires the caller to become network owner, then optionally warps the ped in (2000 ms). Returns the entity or false and deletes the vehicle on failure` |
| `QBCore.Functions.CreateAutomobile(source, model, coords, warp)` | `CreateVehicle(source, model, 'automobile', coords, warp); uses the reliable server-setter path instead of the CREATE_AUTOMOBILE native` |
| `QBCore.Functions.CreateVehicle(source, model, vehtype, coords, warp)` | `CreateVehicleServerSetter(model, vehtype, coords, heading), awaited (5000 ms), optional ped warp; returns the entity or false` |

#### Shared registry mutators

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Functions.AddItem('name', item)` | `Core.registry.registerShared('items', name, copy), exports.kora_core:registerShared. Returns (true, 'success') or (false, 'item_exists' / 'invalid_item_name' / registry error). Fires QBCore:Client:OnSharedUpdate to everyone and the local QBCore:Server:UpdateObject` |
| `QBCore.Functions.UpdateItem('name', item)` | `Re-registers the existing record (items first, then weapons) with registerShared. Returns (false, 'item_not_exists') when unknown` |
| `QBCore.Functions.AddItems({ name = item })` | `Registers each record with registerShared (not registerManyShared) after checking none exist; on failure returns (false, reason, key). Fires QBCore:Client:OnSharedUpdateMultiple` |
| `QBCore.Functions.RemoveItem('name')` | `Core.registry.unregisterShared, exports.kora_core:unregisterShared for items and any shadowed weapons entry. Returns (false, 'item_not_exists') or (false, 'item_remove_failed')` |
| `QBCore.Functions.AddJob('name', job)` | `registerShared('jobs', ...); (false, 'job_exists') when present. Same events as AddItem. Job grades here are the native one-based array, not the zero-based legacy view` |
| `QBCore.Functions.AddJobs({ name = job })` | `Batch form of AddJob; fires QBCore:Client:OnSharedUpdateMultiple` |
| `QBCore.Functions.UpdateJob('name', job)` | `registerShared over an existing job; (false, 'job_not_exists') when unknown` |
| `QBCore.Functions.RemoveJob('name')` | `unregisterShared('jobs', name); (false, 'job_not_exists') when unknown` |
| `QBCore.Functions.AddGang('name', gang)` | `registerShared('gangs', ...); (false, 'gang_exists') when present` |
| `QBCore.Functions.AddGangs({ name = gang })` | `Batch form of AddGang` |
| `QBCore.Functions.UpdateGang('name', gang)` | `registerShared over an existing gang; (false, 'gang_not_exists') when unknown` |
| `QBCore.Functions.RemoveGang('name')` | `unregisterShared('gangs', name); (false, 'gang_not_exists') when unknown` |

#### Player and object extension

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Functions.AddPlayerMethod(ids, 'name', handler)` | `Sets the handler on `player[name]` and `player.Functions[name]` for the source, a list of sources, or -1 for every loaded wrapper. Needs a string name and a callable; applies only to wrappers that exist now` |
| `QBCore.Functions.AddPlayerField(ids, 'name', data)` | `Sets a plain (non-callable) field on the same set of wrappers` |
| `QBCore.Functions.SetMethod('name', handler)` | `Adds QBCore.Functions[name], publishes it as exports['qb-core'] via Kora.compat.provideExport and fires the local QBCore:Server:UpdateObject. Returns (false, 'method_exists') if the name is taken, (false, 'invalid_method_name') for a non-string` |
| `QBCore.Functions.SetField('name', data)` | `Adds QBCore[name]; (false, 'field_exists') when taken; fires QBCore:Server:UpdateObject` |

### QBCore.Player (`QBCore.Player.`)

#### Login and lifecycle

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Player.Login(source, citizenid, newData)` | `With a citizenid: loads it with Core.persistence._load, checks the row license equals the source license, then CheckPlayerData. Mismatch drops the player ('Dropped for character joining exploit') and logs anticheat. Without a citizenid: CheckPlayerData(source, newData). Returns boolean` |
| `QBCore.Player.Logout(source)` | `Core.player.logout, exports.kora_core:logout(source, options)` |
| `QBCore.Player.Save(source)` | `Player.Functions.Save() of the loaded player (reconcile, then Core.persistence.saveNow)` |
| `QBCore.Player.SaveOffline(playerData)` | `Converts with fromLegacyPlayerData and calls Core.persistence.saveOfflinePlayer (fields name, money, charinfo, job, gang, position, metadata, items, phone). A character with no row is inserted when it is not online and the persistent columns are available. Returns (ok, err)` |
| `QBCore.Player.CreatePlayer(playerData, offline)` | `Table argument: with `offline == true` or no `.source` returns an offline wrapper; otherwise saves the row, then Core.player.login(source, citizenid, data) and returns the wrapper (nil if that source is already loaded)` |
| `QBCore.Player.CreatePlayer(source, charinfo, cid)` | `Numeric source: Core.player.createCharacter, exports.kora_core:createCharacter(source, charinfo, cid)` |
| `QBCore.Player.DeleteCharacter(source, citizenid)` | `Core.multichar.deleteCharacter, exports.kora_core:deleteCharacter(source, citizenid)` |
| `QBCore.Player.ForceDeleteCharacter(citizenid)` | `Soft delete: `UPDATE players SET deleted_at = NOW()` through Kora.sql.query. No ownership check` |
| `QBCore.Player.CheckPlayerData(source, playerData)` | `Fills source, license and name, validates job and gang against the registry (unknown name or grade drops the role), applies QBCore.Config.Player.PlayerDefaults, then CreatePlayer. Grade levels here are zero-based` |
| `QBCore.Player.ForceUpdatePlayerData(source)` | `Player.Functions.UpdatePlayerData() for that player, or for every loaded player when source is nil` |

#### Offline and ID helpers

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Player.GetOfflinePlayer(citizenid)` | `QBCore.Functions.GetOfflinePlayerByCitizenId(citizenid)` |
| `QBCore.Player.GetPlayerByLicense(license)` | `QBCore.Functions.GetPlayerByLicense(license)` |
| `QBCore.Player.GetOfflinePlayerByLicense(license)` | `QBCore.Functions.GetOfflinePlayerByLicense(license)` |
| `QBCore.Player.CreateCitizenId()` | `Core.identity.generateCitizenId, exports.kora_core:generateCitizenId()` |
| `QBCore.Player.CreateFingerId()` | `Random fingerprint string (2 letters, 3 digits, 1 letter, 2 digits, 3 letters, 4 digits) from Core.util.randomStr / randomInt` |
| `QBCore.Player.CreateWalletId()` | `'QB-' plus an 8-digit random number` |
| `QBCore.Player.CreateSerialNumber()` | `9 random digits` |

### Player object (`Player.Functions.`)

#### Wrapper shape

| Legacy call | Becomes |
| --- | --- |
| `Player.PlayerData` | `Legacy-shaped detached view of the live PlayerData: job/gang `grade.level` converted native one-based -> legacy zero-based, `grade.payment` and `grade.isboss` mirrored from the registry, metadata and charinfo defaults filled in (not persisted), position carries both `h` and `w`, `optin` defaults to true, and money.cash shows the real item balance. Kept current by Core.compat.onPlayerDataChanged on every setPath write; direct edits are only applied when reconciled` |
| `Player.Offline` | `false for a loaded player (true for offline wrappers)` |
| `Player.AddMoney('cash', 100)` | `Every Functions entry is also callable on the object itself (`Player.AddMoney` and `Player:AddMoney`): the receiver is detected and dropped, so dot and colon calls both work, including on a msgpack copy` |
| `Player.Functions.AddMoney('cash', 100)` | `After logout or a character swap the stale wrapper's Functions return (false, 'player is no longer loaded') instead of acting on a different handle` |

#### Identity and data

| Legacy call | Becomes |
| --- | --- |
| `Player.Functions.GetName()` | ``charinfo.firstname .. ' ' .. charinfo.lastname`, falling back to PlayerData.name` |
| `Player.Functions.GetPlayerData()` | `Fresh legacy view copy (legacyView) of the live PlayerData` |
| `Player.Functions.SetPlayerData('key', value)` | `Converts with fromLegacyPlayerData, writes root `key` with Core.player.setPath(source, { key }, value), then UpdateClient(key). Refuses source, citizenid, license and cid ('player identity is immutable'). Warns when the key has no DB column mapping and Config.compat.warnOnUnknownRoot is on` |
| `Player.Functions.SetPlayerData('money', { cash = 500, bank = 100 })` | `Non-cash accounts replace the ledger; the physical-cash account is applied as a delta against the mirrored balance through Core.money.addMoney / removeMoney (reason 'qb-compat-setplayerdata'). A removal larger than the real balance refuses the whole write and logs` |
| `Player.Functions.UpdateClient()` | `Reconciles direct edits to Player.PlayerData into the funnel, fires the local QBCore:Player:SetPlayerData and QBCore:Server:OnPlayerUpdated(source, 'all', data), then sends QBCore:Client:OnPlayerUpdated to the client on the next tick` |
| `Player.Functions.UpdatePlayerData('key')` | `Alias of UpdateClient. With a key, only that root is reconciled and announced; for job/gang the client event is skipped when a pending delta already produces it` |

#### Job and gang

| Legacy call | Becomes |
| --- | --- |
| `Player.Functions.SetJob('police', 0)` | `Core.jobs.setJob, exports.kora_core:setJob(source, name:lower(), grade + 1). Grade is legacy zero-based, converted to native one-based` |
| `Player.Functions.SetGang('ballas', 0)` | `Core.jobs.setGang, exports.kora_core:setGang(source, name:lower(), grade + 1). Grade zero-based -> one-based` |
| `Player.Functions.SetJobDuty(true)` | `Core.jobs.setJobDuty, exports.kora_core:setJobDuty(source, onDuty); keeps the duty index and fires QBCore:Server:SetDuty / QBCore:Client:SetDuty` |
| `Player.Functions.SetJobData('key', value)` | `Rewrites the job root with that key changed (legacy shape, grade zero-based) through writeLegacyRoot, then UpdateClient('job'). Key 'onduty' is routed to Core.jobs.setJobDuty instead of a raw path write` |
| `Player.Functions.SetGangData('key', value)` | `Same as SetJobData for the gang root` |

#### Money

| Legacy call | Becomes |
| --- | --- |
| `Player.Functions.AddMoney('cash', 100, 'reason', ignoreTax)` | `Core.money.addMoney, exports.kora_core:addMoney(source, account, amount, reason, ignoreTax). Account is lower-cased; negative or non-numeric amount returns false; amount 0 returns true for a configured account. `ignoreTax` is a kora_core addition` |
| `Player.Functions.RemoveMoney('bank', 100, 'reason', ignoreTax)` | `Core.money.removeMoney, exports.kora_core:removeMoney(source, account, amount, reason, ignoreTax); same argument rules as AddMoney` |
| `Player.Functions.SetMoney('bank', 1000, 'reason')` | `Core.money.setMoney, exports.kora_core:setMoney(source, account, amount, reason); reason defaults to 'qb-compat-setmoney'. Never taxed` |
| `Player.Functions.GetMoney('cash')` | `Core.money.getMoney, exports.kora_core:getMoney(source, account)` |

#### Inventory

| Legacy call | Becomes |
| --- | --- |
| `Player.Functions.AddItem('item', 1, slot, info)` | `Core.inventory.addItem, exports.kora_core:addItem(source, name, amount, slot, info)` |
| `Player.Functions.RemoveItem('item', 1, slot)` | `Core.inventory.removeItem, exports.kora_core:removeItem(source, name, amount, slot)` |
| `Player.Functions.GetItemByName('item')` | `Core.inventory.getItemByName, exports.kora_core:getItemByName(source, name)` |
| `Player.Functions.GetItemsByName('item')` | `Core.inventory.getItemsByName, exports.kora_core:getItemsByName(source, name)` |
| `Player.Functions.GetItemBySlot(slot)` | `Core.inventory.getItemBySlot, exports.kora_core:getItemBySlot(source, slot)` |
| `Player.Functions.GetItemInSlot(slot)` | `Alias of GetItemBySlot` |
| `Player.Functions.ClearInventory({ 'item' })` | `Core.inventory.clearInventory, exports.kora_core:clearInventory(source, keep)` |
| `Player.Functions.SetInventory(items)` | `Core.inventory.setItems, exports.kora_core:setItems(source, items)` |
| `Player.Functions.HasItem(items, amount)` | `Core.inventory.hasItem, exports.kora_core:hasItem(source, nameOrList, amount)` |

#### Metadata, charinfo and reputation

| Legacy call | Becomes |
| --- | --- |
| `Player.Functions.SetMetaData('key', value)` | `Core.metadata.setMetaData, exports.kora_core:setMetaData(source, key, value) with a deep-cloned value; hunger and thirst are clamped to 0..100 first. Then UpdateClient('metadata'); the module fires QBCore:Server:OnMetaDataChange` |
| `Player.Functions.GetMetaData('key')` | `Core.metadata.getMetaData, exports.kora_core:getMetaData(source, key)` |
| `Player.Functions.SetCharInfo('key', value)` | `Core.player.setPath(source, { 'charinfo', key }, value), then UpdateClient('charinfo')` |
| `Player.Functions.SetCreditCard(number)` | `SetCharInfo('card', number)` |
| `Player.Functions.GetRep('name')` | ``metadata.rep[name]`, 0 when unset` |
| `Player.Functions.AddRep('name', 5)` | `Adds to `metadata.rep[name]`, floored at 0, written with Core.metadata.setMetaData` |
| `Player.Functions.RemoveRep('name', 5)` | `Subtracts from `metadata.rep[name]`, floored at 0` |
| `Player.Functions.AddJobReputation(5)` | `Adds a signed amount to `metadata.jobrep[currentJobName]` (separate from `rep`) with Core.player.setPath, then UpdatePlayerData` |
| `Player.Functions.AddJobRep(5)` | `Alias of AddJobReputation` |

#### Persistence and misc

| Legacy call | Becomes |
| --- | --- |
| `Player.Functions.Save()` | `Reconciles pending direct edits, then Core.persistence.saveNow(handle). Returns false plus the reason if a reconcile write is refused` |
| `Player.Functions.Logout()` | `Core.player.logout, exports.kora_core:logout(source)` |
| `Player.Functions.Notify('text', 'success', 5000)` | `TriggerClientEvent('QBCore:Notify', source, text, type, length)` |
| `Player.Functions.AddMethod('name', fn)` | `Adds `fn` to this wrapper's object and Functions table; false for a non-string name or non-callable` |
| `Player.Functions.AddField('name', value)` | `Adds a non-callable field on this wrapper's object; false for a callable value` |

#### Offline wrapper differences

| Legacy call | Becomes |
| --- | --- |
| `OfflinePlayer.Offline` | `true. Wrapper from GetOfflinePlayerByCitizenId / GetOfflinePlayerByLicense / CreatePlayer(data, true); every Functions call edits a local snapshot and never touches the live funnel` |
| `OfflinePlayer.Functions.UpdateClient()` | `No-op (also UpdatePlayerData)` |
| `OfflinePlayer.Functions.Save()` | `QBCore.Player.SaveOffline(PlayerData), which persists through Core.persistence.saveOfflinePlayer` |
| `OfflinePlayer.Functions.SetJob('police', 0)` | `Looks the job up with Core.registry.getShared; false when unknown. Level stays zero-based; stores the label, isboss and grade from `definition.grades[level + 1]` ('No Grades' when absent). No events, no duty index` |
| `OfflinePlayer.Functions.SetGang('ballas', 0)` | `Same as SetJob for gangs` |
| `OfflinePlayer.Functions.SetJobDuty(true)` | `Sets job.onduty on the snapshot only` |
| `OfflinePlayer.Functions.SetJobData('key', value)` | `Writes the field on the snapshot job table` |
| `OfflinePlayer.Functions.SetGangData('key', value)` | `Writes the field on the snapshot gang table` |
| `OfflinePlayer.Functions.SetPlayerData('key', value)` | `Plain snapshot write; no immutable-root check and no money handling` |
| `OfflinePlayer.Functions.SetMetaData('key', value)` | `Snapshot write; hunger and thirst clamped 0..100` |
| `OfflinePlayer.Functions.GetMetaData('key')` | `Reads the snapshot metadata` |
| `OfflinePlayer.Functions.SetCharInfo('key', value)` | `Snapshot write` |
| `OfflinePlayer.Functions.SetCreditCard(number)` | `SetCharInfo('card', number) on the snapshot` |
| `OfflinePlayer.Functions.GetMoney('cash')` | `Reads `PlayerData.money[type]` from the snapshot (the stored ledger value)` |
| `OfflinePlayer.Functions.SetMoney('cash', 100)` | `Snapshot write; false when the account does not exist in the snapshot or the amount is not numeric` |
| `OfflinePlayer.Functions.AddMoney('cash', 100)` | `Snapshot arithmetic; no tax, no transaction hooks, no money events; false for negative amounts` |
| `OfflinePlayer.Functions.RemoveMoney('cash', 100)` | `Snapshot arithmetic honouring Config.money.allowNegative and Config.money.minusLimit` |
| `OfflinePlayer.Functions.AddItem('item', 1, slot, info)` | `Writes a record into `items[slot]` (first free index when no slot); replaces whatever sits in that slot and does no stacking, weight or definition checks` |
| `OfflinePlayer.Functions.RemoveItem('item', 1, slot)` | `Decrements the snapshot stack, clearing the slot at zero; false when missing or short` |
| `OfflinePlayer.Functions.GetItemByName('item')` | `First snapshot item with that name` |
| `OfflinePlayer.Functions.GetItemsByName('item')` | `All snapshot items with that name` |
| `OfflinePlayer.Functions.GetItemBySlot(slot)` | ``items[slot]` from the snapshot (also GetItemInSlot)` |
| `OfflinePlayer.Functions.HasItem(items, amount)` | `Counts snapshot stacks by name for one name or an array` |
| `OfflinePlayer.Functions.SetInventory(items)` | `Replaces the snapshot items table` |
| `OfflinePlayer.Functions.ClearInventory({ 'item' })` | `Keeps only the named items in the snapshot` |
| `OfflinePlayer.Functions.GetRep('name')` | `Snapshot `metadata.rep[name]` or 0` |
| `OfflinePlayer.Functions.AddRep('name', 5)` | `Snapshot update, floored at 0 (RemoveRep subtracts through it)` |
| `OfflinePlayer.Functions.RemoveRep('name', 5)` | `AddRep with a negated amount` |
| `OfflinePlayer.Functions.AddJobReputation(5)` | `Snapshot update of `metadata.jobrep[job.name]` (AddJobRep alias)` |
| `OfflinePlayer.Functions.Notify('text')` | `No-op` |
| `OfflinePlayer.Functions.Logout()` | `Returns false` |
| `OfflinePlayer.Functions.AddMethod('name', fn)` | `Same as the online wrapper` |
| `OfflinePlayer.Functions.AddField('name', value)` | `Same as the online wrapper` |

### QBCore object fields (`QBCore.`)

#### Tables kept by the compat

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Players` | `source -> Player wrapper. Filled on kora_core:server:playerLoaded, cleared on kora_core:server:playerDropped and QBCore:Server:OnPlayerUnload; GetPlayer also rebuilds lazily` |
| `QBCore.PlayersByCitizenId` | `citizenid -> Player wrapper, kept in step with QBCore.Players` |
| `QBCore.UsableItems` | `name -> useable record mirrored from Core.inventory (CreateUseableItem / CanUseItem)` |
| `QBCore.ClientCallbacks` | `Pending server-to-client callback entries keyed by `name .. source` (TriggerClientCallback)` |
| `QBCore.ServerCallbacks` | `Present as an empty table on the server (the client fills its own copy)` |
| `QBCore.Player_Buckets` | `license -> { id = source, bucket } maintained by Core.player.setPlayerBucket` |
| `QBCore.Entity_Buckets` | `entity -> { id = entity, bucket } maintained by SetEntityBucket` |

#### Config

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Config.MaxPlayers` | `GetConvarInt('sv_maxclients', 48)` |
| `QBCore.Config.DefaultSpawn` | `vector4(-1035.71, -2731.87, 12.86, 0.0)` |
| `QBCore.Config.UpdateInterval` | `5` |
| `QBCore.Config.StatusInterval` | `5000` |
| `QBCore.Config.Money` | `{ MoneyTypes = Config.money.default, DontAllowMinus = accounts not in Config.money.allowNegative, MinusLimit = Config.money.minusLimit, PayCheckTimeOut = 10, PayCheckSociety = false }` |
| `QBCore.Config.Player` | `{ HungerRate = 4.2, ThirstRate = 3.8, Bloodtypes, MaxWeight = Config.inventory.maxWeight, MaxInvSlots = Config.inventory.slots, PlayerDefaults = stock defaults (charinfo, job unemployed/Civilian, gang none, metadata, position, items) }` |
| `QBCore.Config.Server` | `{ Closed = false, ClosedReason = 'Server Closed', Uptime = 0, Whitelist = false, WhitelistPermission = 'admin', PVP = true, Discord = convar kora_discord, CheckDuplicateLicense = true, Permissions = { 'god', 'admin', 'mod' } }` |
| `QBCore.Config.Commands` | `{ OOCColor = { 255, 151, 133 } }` |
| `QBCore.Config.Notify` | `Stock NotificationStyling and VariantDefinitions (success, primary, warning, error, police, ambulance)` |

#### Helpers

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Debug(table, indent)` | `Recursive table printer (also the target of the QBCore:DebugSomething net event)` |
| `QBCore.ShowError('resource', 'message')` | `print in red: '[resource] message'` |
| `QBCore.ShowSuccess('resource', 'message')` | `print in green: '[resource] message'` |

### QBCore.Shared (`QBCore.Shared.`)

#### Helper functions

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Shared.Round(value, decimals)` | `Core.util.round, exports.kora_core:round(value, precision)` |
| `QBCore.Shared.Trim(value)` | `Core.util.trim, exports.kora_core:trim(value)` |
| `QBCore.Shared.SplitStr(str, delimiter)` | `Core.util.splitStr, exports.kora_core:splitStr(str, delimiter)` |
| `QBCore.Shared.RandomStr(length)` | `Core.util.randomStr, exports.kora_core:randomStr(length)` |
| `QBCore.Shared.RandomInt(length)` | `Core.util.randomInt, exports.kora_core:randomInt(length)` |
| `QBCore.Shared.FirstToUpper(value)` | `Uppercases the first lowercase letter; nil for a nil value` |
| `QBCore.Shared.IsFunction(value)` | `true for a function, a function reference, or a table with a callable __call (broader than stock)` |

#### Constants

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Shared.StarterItems` | `{ phone, id_card, driver_license }, each `&#123; amount = 1, item = name &#125;`` |
| `QBCore.Shared.MaleNoGloves` | `Set of component-3 drawable indices meaning no gloves for the male freemode ped` |
| `QBCore.Shared.FemaleNoGloves` | `Same set for the female freemode ped` |
| `QBCore.Shared.ForceJobDefaultDutyAtLogin` | `true. Read only by CheckPlayerData when validating a legacy job; Kora login duty still follows Config.jobs.defaultDuty` |

#### Registry views

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Shared.Items` | `Live name-keyed view over the 'weapons' and 'items' registries (items win on a name clash). Refreshes on registry change; a read-only compatibility view, writes do not reach the registry` |
| `QBCore.Shared.Weapons` | `Hash-keyed (joaat) view: stock damage metadata merged with the 'weapons' registry; entries without catalog data get damagereason 'Died'` |
| `QBCore.Shared.Vehicles` | `Model-keyed live view over the 'vehicles' registry` |
| `QBCore.Shared.VehicleHashes` | `Same vehicles keyed by joaat(model)` |
| `QBCore.Shared.Jobs` | `Live view over the 'jobs' registry with `grades` re-keyed to the zero-based strings '0', '1', ... (legacy). Native registry grades are a one-based array` |
| `QBCore.Shared.Gangs` | `Live view over the 'gangs' registry with zero-based string grade keys` |
| `QBCore.Shared.Locations` | `Live name-keyed view over the 'locations' registry` |

### QBCore.Commands (`QBCore.Commands.`)

#### Registration

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Commands.Add('name', 'help', args, argsRequired, function(source, args, rawCommand) end, 'admin')` | `Core.commands.addCommand, exports.kora_core:addCommand(name, help, args, argsRequired, handler, permission). Stock { { 'id', 'desc' } } suggestion tables are adapted to { name, help }. The handler is wrapped to fire the cancellable QBCore:Server:PreCommandExecution first` |
| `QBCore.Commands.Add('name', 'help', args, argsRequired, cb, 'admin', 'mod')` | `Extra permission levels after the first are accepted: each level gets `add_ace kora_core.&lt;level> command.&lt;name> allow`, List[name].permission becomes the array, and the native check uses the least privileged level` |
| `QBCore.Commands.Refresh(source)` | `Core.commands.refreshCommands, exports.kora_core:refreshCommands(source), then rebuilds QBCore.Commands.List` |

#### State

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Commands.List` | `Table keyed by lower-cased name with { name, help, permission, params, arguments, argsrequired, callback }. Rebuilt on Add and Refresh only, so commands registered straight through Kora.commands appear after the next rebuild` |
| `QBCore.Commands.IgnoreList` | `{ god = true, user = true }: levels that get no per-command ACE` |

#### Command-related events

| Legacy call | Becomes |
| --- | --- |
| `TriggerServerEvent('QBCore:CallCommand', 'name', args)` | `Looks the name up in QBCore.Commands.List and calls its stored raw callback in-process after checking `command.&lt;name>` ACE and argsrequired. See the Legacy events group` |

### Legacy events |

#### Inbound from clients (net events)

| Legacy call | Becomes |
| --- | --- |
| `TriggerServerEvent('QBCore:Server:SetMetaData', 'hunger', 50)` | `Core.metadata.setMetaData, exports.kora_core:setMetaData(source, key, value) only for keys set true in Config.compat.clientMetadataKeys (default hunger, thirst, stress). hunger, thirst and stress must be finite numbers and are clamped 0..100; 'starterItems' and every other key are rejected with a console warning` |
| `TriggerServerEvent('QBCore:ToggleDuty')` | `Flips the caller's own duty flag through Core.jobs.setJobDuty and sends a 'You are now on duty!' / 'off duty!' notify. Needs Config.compat.toggleDutyEvent, a loaded player with a job other than Config.jobs.defaultJob, and a 2000 ms per-player cooldown` |
| `TriggerServerEvent('QBCore:Server:Logout')` | `Core.player.logout(source), exports.kora_core:logout(source)` |
| `TriggerServerEvent('QBCore:Server:OnPlayerLoaded')` | `No-op unless Config.compat.deferClientPlayerLoaded is true; then sends QBCore:Client:OnPlayerLoaded once per login (guarded by the handle's _clientLoadedSent flag)` |
| `TriggerServerEvent('QBCore:Server:UpdateObject')` | `Registered as a net event with an empty body: nothing is refreshed or sent back` |
| `TriggerServerEvent('QBCore:UpdatePlayer')` | `Sends hud:client:UpdateNeeds with the stored hunger and thirst and calls Core.persistence.saveNow. Does not tick hunger or thirst (the needs module owns decay). 10 s per-player cooldown` |
| `TriggerServerEvent('QBCore:DebugSomething', ...)` | `QBCore.Debug(...) on the server console; 1 s per-player cooldown, excess calls dropped silently` |
| `TriggerServerEvent('QBCore:Server:CloseServer', 'reason')` | `Needs admin (otherwise the caller is kicked). Sets QBCore.Config.Server.Closed and ClosedReason, then kicks every loaded player without the whitelist permission` |
| `TriggerServerEvent('QBCore:Server:OpenServer')` | `Needs admin (otherwise the caller is kicked). Sets QBCore.Config.Server.Closed = false` |
| `TriggerServerEvent('QBCore:Command:TeleportToCoords', x, y, z)` | `Relays the same event back to the caller only; no server-side checks` |
| `TriggerServerEvent('QBCore:CallCommand', 'name', args)` | `Unknown name: silent return. Needs `command.&lt;name>` ACE (else notifies 'No access to this command'). `args` must be a table of at most 16 entries (else treated as empty). With argsrequired and fewer args than declared params, notifies 'All arguments must be filled out!'. Otherwise calls List[name].callback(source, args)` |
| `TriggerServerEvent('hud:server:GainStress', amount)` | `Core.metadata.incrementMetaData(source, 'stress', +amount, 0, 100), then hud:client:UpdateStress and a 'Feeling More Stressed!' notify. Ignored while qb-hud is started, when Config.compat.stress.disabled, for whitelisted jobs or types (leo, ambulance), for non-numeric amounts (the amount is floored and must then be 1..100), and inside Config.compat.stress.cooldownMs` |
| `TriggerServerEvent('hud:server:RelieveStress', amount)` | `Same rules with a negative delta and a 'Feeling More Relaxed!' notify` |
| `TriggerServerEvent('QBCore:Server:TriggerCallback', 'name', ...)` | `Raw callback wire, request leg: runs the handler registered through CreateCallback in a pcall with a responder; the reply goes back as QBCore:Client:TriggerCallback. Unknown names are ignored; errors are printed` |
| `TriggerServerEvent('QBCore:Server:TriggerClientCallback', 'name', ...)` | `Raw callback wire, reply leg for TriggerClientCallback: resolves the entry stored at QBCore.ClientCallbacks[name .. source] once (function called, promise resolved)` |

#### Local-only handlers (server)

| Legacy call | Becomes |
| --- | --- |
| `TriggerEvent('QBCore:Server:OnPlayerUpdated', source, 'all')` | `Handler registered with AddEventHandler (not a net event). For key nil or 'all' re-fires QBCore:Server:OnJobUpdate and OnGangUpdate with the current legacy-shaped job and gang. Any other key is ignored here` |
| `TriggerEvent('qb-log:server:CreateLog', name, title, color, message, tagEveryone, imageUrl)` | `Core.logging.logEvent (category = name, source 'qb-log') with field lengths capped. Local only; webhook URLs are never read` |
| `AddEventHandler('chatMessage', ...)` | `Cancels the event for any message starting with '/', so the chat resource does not echo commands` |

#### Outbound to server listeners (fired by kora_core)

| Legacy call | Becomes |
| --- | --- |
| `AddEventHandler('QBCore:Server:PlayerLoaded', function(Player) end)` | `Fired at login with the QB Player wrapper (not the native handle)` |
| `AddEventHandler('QBCore:Server:OnPlayerUnload', function(source) end)` | `Fired on logout and on drop, once per session` |
| `AddEventHandler('QBCore:Server:PlayerDropped', function(source, reason) end)` | `Fired when a loaded player disconnects` |
| `AddEventHandler('QBCore:Server:OnJobUpdate', function(source, job) end)` | `Fired after setJob, setJobDuty and OnPlayerUpdated('all'); `job` is legacy-shaped (zero-based grade.level)` |
| `AddEventHandler('QBCore:Server:OnGangUpdate', function(source, gang) end)` | `Fired after setGang and OnPlayerUpdated('all'); legacy-shaped gang` |
| `AddEventHandler('QBCore:Server:OnPlayerUpdated', function(source, key, value) end)` | `Fired by setJob, setGang, setJobDuty and by Player.Functions.UpdateClient with the legacy value` |
| `AddEventHandler('QBCore:Server:SetDuty', function(source, onDuty) end)` | `Fired by Core.jobs.setJobDuty` |
| `AddEventHandler('QBCore:Server:OnMoneyChange', function(source, account, amount, action, reason) end)` | `Fired for every ledger change from Core.money` |
| `AddEventHandler('QBCore:Server:OnMetaDataChange', function(source, key, value) end)` | `Fired by Core.metadata.setMetaData and incrementMetaData` |
| `AddEventHandler('QBCore:Server:UseItem', function(source, item) end)` | `Fired by Core.inventory.useItem when the item has no registered useable handler` |
| `AddEventHandler('QBCore:Player:SetPlayerData', function(data) end)` | `Fired locally by Player.Functions.UpdateClient with no key (full legacy PlayerData)` |
| `AddEventHandler('QBCore:Server:UpdateObject', function() end)` | `Fired locally by SetMethod, SetField and every shared registry mutator` |
| `AddEventHandler('QBCore:Server:PreCommandExecution', function(source, name, args, rawCommand) end)` | `Fired before each command added through QBCore.Commands.Add runs from chat or console; CancelEvent() stops the callback` |
| `AddEventHandler('police:server:policeAlert', function(message) end)` | `Fired by Core.dispatch.alert for job 'police' when Config.dispatch.legacyEvents is true` |

#### Outbound to clients

| Legacy call | Becomes |
| --- | --- |
| `TriggerClientEvent('QBCore:Client:OnPlayerLoaded', source)` | `Sent at login after the snapshot, or on the client's QBCore:Server:OnPlayerLoaded when Config.compat.deferClientPlayerLoaded is true` |
| `TriggerClientEvent('QBCore:Client:OnPlayerUnload', source)` | `Sent on logout` |
| `TriggerClientEvent('QBCore:Client:OnJobUpdate', source, job)` | `Sent by the server when Config.compat.jobUpdateEventSource is 'server' or 'both'; with 'client' the client fires it locally` |
| `TriggerClientEvent('QBCore:Client:OnGangUpdate', source, gang)` | `Same gating as OnJobUpdate` |
| `TriggerClientEvent('QBCore:Client:OnPlayerUpdated', source, key, value)` | `Sent by Player.Functions.UpdateClient and, for job and gang, by the server job functions under the same jobUpdateEventSource gate` |
| `TriggerClientEvent('QBCore:Client:SetDuty', source, onDuty)` | `Sent by Core.jobs.setJobDuty` |
| `TriggerClientEvent('QBCore:Client:OnMoneyChange', source, account, amount, action, reason)` | `Sent for every ledger change` |
| `TriggerClientEvent('hud:client:OnMoneyChange', source, account, amount, isRemove)` | `Legacy qb-hud money popup hook, sent alongside OnMoneyChange` |
| `TriggerClientEvent('qb-phone:client:RemoveBankMoney', source, amount)` | `Sent only when the bank account is reduced` |
| `TriggerClientEvent('hud:client:UpdateNeeds', source, hunger, thirst)` | `Sent by the QBCore:UpdatePlayer handler` |
| `TriggerClientEvent('hud:client:UpdateStress', source, value)` | `Sent after an accepted GainStress / RelieveStress` |
| `TriggerClientEvent('QBCore:Notify', source, text, type, length)` | `Sent by Functions.Notify, Player.Functions.Notify, command replies and ToggleDuty; the client forwards to Kora.notify.send` |
| `TriggerClientEvent('QBCore:Client:OnSharedUpdate', -1, 'Items', key, value)` | `Sent by AddItem, UpdateItem, RemoveItem, AddJob, ... (value nil on removal)` |
| `TriggerClientEvent('QBCore:Client:OnSharedUpdateMultiple', -1, 'Items', records)` | `Sent by AddItems, AddJobs and AddGangs` |
| `TriggerClientEvent('QBCore:Client:SharedUpdate', source, QBCore.Shared)` | `Opt-in: only when Config.compat.fireSharedUpdateAtLogin is true, at kora_core:server:playerLoaded. Default off` |
| `TriggerClientEvent('QBCore:Client:PvpHasToggled', -1, enabled)` | `Sent by /togglepvp, and to a player who joins while PVP is off` |
| `TriggerClientEvent('QBCore:Client:TriggerCallback', source, 'name', ...)` | `Raw callback reply to a QBCore:Server:TriggerCallback request` |
| `TriggerClientEvent('QBCore:Client:TriggerClientCallback', source, 'name', ...)` | `Request leg of TriggerClientCallback` |
| `TriggerClientEvent('hospital:client:ambulanceAlert', source, coords, message)` | `Sent to on-duty ambulance and ems players by Core.dispatch.alert when Config.dispatch.legacyEvents is true` |
| `TriggerClientEvent('police:client:policeAlert', source, coords, message)` | `Sent to on-duty police by Core.dispatch.alert under the same flag` |

### Legacy callbacks (`QBCore.Functions.CreateCallback`)

#### Registered by the compat

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Functions.TriggerCallback('QBCore:Server:SpawnVehicle', cb, model, coords, warp)` | `Registered through CreateCallback only when Config.compat.vehicleSpawnCallbacks is 'admin' or 'limited'. Returns the network id of a server-created vehicle (F.SpawnVehicle) or nil on refusal. 'admin' needs the admin permission. 'limited' needs a loaded player and enforces a per-player cooldown, the model allow-list (QBCore.Shared.Vehicles, VehicleHashes, Config.compat.vehicleSpawn.allowModels), a distance cap from the ped, and max live vehicles; it grants keys through kora_vehiclekeys:giveKeys when started. Every attempt is audited under 'vehicle'` |
| `QBCore.Functions.TriggerCallback('QBCore:Server:CreateVehicle', cb, model, coords, warp)` | `Same handler and checks, creating through F.CreateAutomobile` |

#### Wire

| Legacy call | Becomes |
| --- | --- |
| `TriggerServerEvent('QBCore:Server:TriggerCallback', 'name', ...)` | `Raw request; see Legacy events` |
| `TriggerClientEvent('QBCore:Client:TriggerCallback', source, 'name', ...)` | `Raw reply; the client answers pending requests in first-in-first-out order per name` |

### Default commands (`/`)

#### Admin

| Legacy call | Becomes |
| --- | --- |
| `/tp <id \| x y z [heading] \| location>` | `permission admin. One numeric id teleports the caller to that player (QBCore:Command:TeleportToPlayer); a non-numeric word looks up QBCore.Shared.Locations; 3 or 4 numbers (commas stripped) teleport to coordinates (QBCore:Command:TeleportToCoords). Players only` |
| `/tpm` | `permission admin. Fires QBCore:Command:GoToMarker on the caller (teleport to waypoint). Players only` |
| `/togglepvp` | `permission admin. Flips QBCore.Config.Server.PVP and broadcasts QBCore:Client:PvpHasToggled` |
| `/openserver` | `permission admin. Sets QBCore.Config.Server.Closed = false; replies 'The server is already open' if open` |
| `/closeserver [reason]` | `permission admin. Sets Closed and ClosedReason (reason up to 200 chars) and kicks loaded players without the whitelist permission. A playerConnecting handler refuses joins while closed unless the player has the whitelist permission` |
| `/car <model>` | `permission admin, argument required. Model must match [%w_]+ and be 32 chars or fewer. Spawns with F.SpawnVehicle (warp in), deletes the vehicle the admin was in, grants keys via kora_vehiclekeys:giveKeys when started. Players only` |
| `/dv` | `permission admin. Deletes the occupied vehicle, or every vehicle within 5.0 m on foot. Players only` |
| `/dvall` | `permission admin. Deletes every vehicle (GetAllVehicles) and replies with the count` |
| `/dvp` | `permission admin. Deletes every ped except player peds` |
| `/dvo` | `permission admin. Deletes every object` |
| `/givemoney <id> <moneytype> <amount>` | `permission admin, all arguments required. Core.money.addMoney(id, account, amount, 'Admin give money', true) (tax ignored). Account must be in Config.money.types` |
| `/setmoney <id> <moneytype> <amount>` | `permission admin, all arguments required. Core.money.setMoney(id, account, amount, 'Admin set money')` |
| `/setjob <id> <job> <grade>` | `permission admin, all arguments required. Core.jobs.setJob(id, job:lower(), grade + 1); grade is a whole number >= 0 (legacy zero-based, converted to one-based)` |
| `/setgang <id> <gang> <grade>` | `permission admin, all arguments required. Core.jobs.setGang with the same grade conversion` |

#### God

| Legacy call | Becomes |
| --- | --- |
| `/addpermission <id> <permission>` | `permission god, all arguments required. Permission must be one of QBCore.Config.Server.Permissions; calls Functions.AddPermission then QBCore.Commands.Refresh(id)` |
| `/removepermission <id> <permission>` | `permission god, all arguments required. Functions.RemovePermission then refresh` |

#### User

| Legacy call | Becomes |
| --- | --- |
| `/job` | `permission user. Notifies the caller's job label, grade name and duty state` |
| `/gang` | `permission user. Notifies the caller's gang label and grade name` |
| `/ooc <message>` | `permission user. Sends chat:addMessage 'OOC \| name' to the sender and players within 20.0 m; opted-in admins elsewhere get 'Proximity OOC \| name' and a qb-log entry. Message up to 255 chars. Players only` |
| `/me <message>` | `permission user. Fires QBCore:Command:ShowMe3D to the sender and players within 20.0 m; formatting tags stripped, 255 chars max. Players only` |

### qb-multicharacter (`qb-multicharacter:server:`)

#### Callbacks (Kora.callback only)

| Legacy call | Becomes |
| --- | --- |
| `Kora.callback.trigger('qb-multicharacter:server:GetUserCharacters')` | `Raw `players` rows for the caller's primary identifier (`deleted_at IS NULL`) via Kora.sql.query; {} without an identifier` |
| `Kora.callback.trigger('qb-multicharacter:server:GetNumberOfCharacters')` | `Returns (Core.users.getMaxCharacters(license), {}); with no identifier returns Config.identity.maxCharacters and {}. The countries list is always empty` |
| `Kora.callback.trigger('qb-multicharacter:server:setupCharacters')` | `Core.multichar.getCharacters, exports.kora_core:getCharacters(source)` |
| `Kora.callback.trigger('qb-multicharacter:server:getSkin', citizenid)` | `Always returns nil: no appearance module exists to answer it` |
| `Kora.callback.trigger('qb-multicharacter:server:deleteCharacter', citizenid)` | `Core.multichar.deleteCharacter, exports.kora_core:deleteCharacter(source, citizenid)` |

#### Events

| Legacy call | Becomes |
| --- | --- |
| `TriggerServerEvent('qb-multicharacter:server:loadUserData', { citizenid = cid })` | `Core.multichar.selectCharacter(source, citizenid); on failure sends multichar:client:selectFailed. On success reads the position with Core.player.getPlayerData(source, { 'position' }), then sends qb-spawn:client:setupSpawns and qb-spawn:client:openUI. Needs a table with a citizenid` |
| `TriggerServerEvent('qb-multicharacter:server:createCharacter', data)` | `Core.player.createCharacter(source, data); the client-supplied cid is ignored (next free slot and the limit are computed server-side). Failure sends multichar:client:selectFailed; success sends qb-multicharacter:client:closeNUIdefault` |
| `TriggerServerEvent('qb-multicharacter:server:deleteCharacter', citizenid)` | `Core.multichar.deleteCharacter(source, citizenid)` |
| `TriggerServerEvent('qb-multicharacter:server:disconnect', reason)` | `DropPlayer(source, reason or 'Disconnected.')` |

### qb-spawn (`qb-spawn:server:`)

#### Callbacks

| Legacy call | Becomes |
| --- | --- |
| `Kora.callback.trigger('qb-spawn:server:getOwnedHouses', citizenid)` | `Always returns {}: no housing data exists to query` |

### qb-core exports (`exports['qb-core']:`)

#### Core object and shared data

| Legacy call | Becomes |
| --- | --- |
| `exports['qb-core']:GetCoreObject(filters)` | `Returns QBCore, or a table holding only the keys named in the `filters` array. Gated by Config.compat.coreObjectExport (default true)` |
| `exports['qb-core']:GetShared('Items', 'item')` | `QBCore.Shared[namespace] (canonical-case fallback: 'items' works as 'Items'); with an item key returns that entry, otherwise the whole map. nil for an unknown namespace` |
| `exports['qb-core']:GetSharedItems()` | `GetShared('Items')` |
| `exports['qb-core']:GetSharedVehicles()` | `GetShared('Vehicles')` |
| `exports['qb-core']:GetSharedJobs()` | `GetShared('Jobs') (zero-based grade view)` |
| `exports['qb-core']:GetSharedGangs()` | `GetShared('Gangs') (zero-based grade view)` |
| `exports['qb-core']:GetSharedWeapons()` | `GetShared('Weapons')` |

#### Direct function exports

| Legacy call | Becomes |
| --- | --- |
| `exports['qb-core']:GetPlayer(source)` | `QBCore.Functions.GetPlayer` |
| `exports['qb-core']:GetPlayerByCitizenId(citizenid)` | `QBCore.Functions.GetPlayerByCitizenId` |
| `exports['qb-core']:GetPlayerByPhone(number)` | `QBCore.Functions.GetPlayerByPhone` |
| `exports['qb-core']:GetPlayers()` | `QBCore.Functions.GetPlayers` |
| `exports['qb-core']:GetQBPlayers()` | `QBCore.Functions.GetQBPlayers` |
| `exports['qb-core']:GetOfflinePlayerByCitizenId(citizenid)` | `QBCore.Functions.GetOfflinePlayerByCitizenId` |
| `exports['qb-core']:GetIdentifier(source, kind)` | `QBCore.Functions.GetIdentifier` |
| `exports['qb-core']:GetSource(identifier)` | `QBCore.Functions.GetSource` |
| `exports['qb-core']:CreateCallback(name, handler)` | `QBCore.Functions.CreateCallback` |
| `exports['qb-core']:TriggerCallback(name, source, cb, ...)` | `QBCore.Functions.TriggerCallback` |
| `exports['qb-core']:CreateUseableItem(name, cb)` | `QBCore.Functions.CreateUseableItem` |
| `exports['qb-core']:CanUseItem(name)` | `QBCore.Functions.CanUseItem` |
| `exports['qb-core']:UseItem(source, item)` | `QBCore.Functions.UseItem` |
| `exports['qb-core']:HasPermission(source, permission)` | `QBCore.Functions.HasPermission` |
| `exports['qb-core']:GetPermission(source)` | `QBCore.Functions.GetPermission` |
| `exports['qb-core']:AddPermission(source, permission)` | `QBCore.Functions.AddPermission` |
| `exports['qb-core']:RemovePermission(source, permission)` | `QBCore.Functions.RemovePermission` |
| `exports['qb-core']:IsOptin(source)` | `QBCore.Functions.IsOptin` |
| `exports['qb-core']:ToggleOptin(source)` | `QBCore.Functions.ToggleOptin` |
| `exports['qb-core']:Kick(source, reason, setKickReason, deferrals)` | `QBCore.Functions.Kick` |
| `exports['qb-core']:Notify(source, text, type, length)` | `QBCore.Functions.Notify` |
| `exports['qb-core']:HasItem(source, items, amount)` | `QBCore.Functions.HasItem` |
| `exports['qb-core']:ExecuteSql(wait, query, cb)` | `QBCore.Functions.ExecuteSql` |
| `exports['qb-core']:PaycheckInterval()` | `QBCore.Functions.PaycheckInterval` |
| `exports['qb-core']:GetCoords(entity)` | `QBCore.Functions.GetCoords` |
| `exports['qb-core']:GetOfflinePlayerByLicense(license)` | `QBCore.Functions.GetOfflinePlayerByLicense` |
| `exports['qb-core']:GetPlayerByLicense(license)` | `QBCore.Functions.GetPlayerByLicense` |
| `exports['qb-core']:GetPlayerByAccount(account)` | `QBCore.Functions.GetPlayerByAccount` |
| `exports['qb-core']:GetPlayerByCharInfo(property, value)` | `QBCore.Functions.GetPlayerByCharInfo` |
| `exports['qb-core']:GetPlayersByJob(job, checkOnDuty)` | `QBCore.Functions.GetPlayersByJob` |
| `exports['qb-core']:GetPlayersOnDuty(job)` | `QBCore.Functions.GetPlayersOnDuty` |
| `exports['qb-core']:GetDutyCount(job)` | `QBCore.Functions.GetDutyCount` |
| `exports['qb-core']:GetClosestPlayer(source, coords)` | `QBCore.Functions.GetClosestPlayer` |
| `exports['qb-core']:GetClosestObject(source, coords)` | `QBCore.Functions.GetClosestObject` |
| `exports['qb-core']:GetClosestVehicle(source, coords)` | `QBCore.Functions.GetClosestVehicle` |
| `exports['qb-core']:GetClosestPed(source, coords)` | `QBCore.Functions.GetClosestPed` |
| `exports['qb-core']:GetBucketObjects()` | `QBCore.Functions.GetBucketObjects` |
| `exports['qb-core']:SetPlayerBucket(source, bucket)` | `QBCore.Functions.SetPlayerBucket` |
| `exports['qb-core']:SetEntityBucket(entity, bucket)` | `QBCore.Functions.SetEntityBucket` |
| `exports['qb-core']:GetPlayersInBucket(bucket)` | `QBCore.Functions.GetPlayersInBucket` |
| `exports['qb-core']:GetEntitiesInBucket(bucket)` | `QBCore.Functions.GetEntitiesInBucket` |
| `exports['qb-core']:SpawnVehicle(source, model, coords, warp)` | `QBCore.Functions.SpawnVehicle` |
| `exports['qb-core']:CreateAutomobile(source, model, coords, warp)` | `QBCore.Functions.CreateAutomobile` |
| `exports['qb-core']:CreateVehicle(source, model, vehtype, coords, warp)` | `QBCore.Functions.CreateVehicle` |
| `exports['qb-core']:TriggerClientCallback(name, source, ...)` | `QBCore.Functions.TriggerClientCallback` |
| `exports['qb-core']:IsWhitelisted(source)` | `QBCore.Functions.IsWhitelisted` |
| `exports['qb-core']:IsPlayerBanned(source)` | `QBCore.Functions.IsPlayerBanned` |
| `exports['qb-core']:IsLicenseInUse(license)` | `QBCore.Functions.IsLicenseInUse` |
| `exports['qb-core']:GetDatabaseInfo()` | `QBCore.Functions.GetDatabaseInfo` |
| `exports['qb-core']:GetCoreVersion(invokingResource)` | `QBCore.Functions.GetCoreVersion` |
| `exports['qb-core']:ExploitBan(playerId, origin)` | `QBCore.Functions.ExploitBan` |
| `exports['qb-core']:CreateAccountNumber()` | `QBCore.Functions.CreateAccountNumber` |
| `exports['qb-core']:CreatePhoneNumber()` | `QBCore.Functions.CreatePhoneNumber` |
| `exports['qb-core']:AddPlayerMethod(ids, methodName, handler)` | `QBCore.Functions.AddPlayerMethod` |
| `exports['qb-core']:AddPlayerField(ids, fieldName, data)` | `QBCore.Functions.AddPlayerField` |
| `exports['qb-core']:SetMethod(methodName, handler)` | `QBCore.Functions.SetMethod` |
| `exports['qb-core']:SetField(fieldName, data)` | `QBCore.Functions.SetField` |
| `exports['qb-core']:AddItem(name, item)` | `QBCore.Functions.AddItem (shared registry mutator, not the Player.Functions inventory call)` |
| `exports['qb-core']:UpdateItem(name, item)` | `QBCore.Functions.UpdateItem` |
| `exports['qb-core']:AddItems(items)` | `QBCore.Functions.AddItems` |
| `exports['qb-core']:RemoveItem(name)` | `QBCore.Functions.RemoveItem` |
| `exports['qb-core']:AddJob(name, job)` | `QBCore.Functions.AddJob` |
| `exports['qb-core']:AddJobs(jobs)` | `QBCore.Functions.AddJobs` |
| `exports['qb-core']:UpdateJob(name, job)` | `QBCore.Functions.UpdateJob` |
| `exports['qb-core']:RemoveJob(name)` | `QBCore.Functions.RemoveJob` |
| `exports['qb-core']:AddGang(name, gang)` | `QBCore.Functions.AddGang` |
| `exports['qb-core']:AddGangs(gangs)` | `QBCore.Functions.AddGangs` |
| `exports['qb-core']:UpdateGang(name, gang)` | `QBCore.Functions.UpdateGang` |
| `exports['qb-core']:RemoveGang(name)` | `QBCore.Functions.RemoveGang` |

### qbx facade (`exports.qbx_core:`)

#### Enabling

| Legacy call | Becomes |
| --- | --- |
| `Config.compat.qbxFacade = true` | `Opt-in switch; `setr kora:qbxFacade true` enables it too. Stays off (nothing registered) when disabled or when a resource named qbx_core or qbx_vehicles exists. There is no `provide 'qbx_core'`: exports are published with the __cfx_export_ hijack` |

#### qbx_core exports

| Legacy call | Becomes |
| --- | --- |
| `exports.qbx_core:GetPlayer(source)` | `Copy of QBCore.Functions.GetPlayer(source) with receiver-agnostic methods. Differences: SetPlayerData('items', t) only updates the in-memory mirror (ox_inventory owns persistence), and SetMoney is a no-op when the balance already equals the amount. nil for a non-numeric source or unloaded player` |
| `exports.qbx_core:GetPlayersData()` | `Array of deep-cloned PlayerData for every loaded player, ordered by source` |
| `exports.qbx_core:CanUseItem('item')` | `Returns a function(source, data) calling the registered useable (Core.inventory.getUseable), or nil when none` |
| `exports.qbx_core:GetGroups(source)` | `{ [jobName] = zeroBasedGrade, [gangName] = zeroBasedGrade } for the active job and the gang (gang 'none' omitted). Uses toLegacyGradeLevel: native one-based -> zero-based` |
| `exports.qbx_core:IsGradeBoss('group', grade)` | `true when `grades[grade + 1].isboss` in the jobs or gangs registry; grade is zero-based` |
| `exports.qbx_vehicles:GetVehicleIdByPlate('PLATE')` | `Integer `player_vehicles.id` for the plate (as given, or trimmed and upper-cased), excluding soft-deleted rows; nil otherwise. Forwards to Kora.sql.single` |

#### Events and state bags

| Legacy call | Becomes |
| --- | --- |
| `TriggerEvent('qbx_core:server:onGroupUpdate', source, name, grade)` | `Fired locally when the active job or gang name or grade changes (nil grade when a group is lost), diffed once per change` |
| `TriggerClientEvent('qbx_core:client:onGroupUpdate', source, name, grade)` | `Client counterpart of the group update` |
| `TriggerClientEvent('qbx_core:client:setGroups', source, groups)` | `Sent once when the session is ready, with the GetGroups map` |
| `TriggerEvent('qbx_core:server:playerLoggedOut', source)` | `Fired once per session when QBCore:Server:OnPlayerUnload runs` |
| `Player(source).state.loadInventory` | `Set true after isLoggedIn becomes true (polled up to 40 times at 50 ms), set false on unload. Also writes an empty `metadata.licences` table once when absent` |

### How it works

kora_core builds one QBCore table (compat/shared/coreobject.lua) and fills the server realm in compat/server/qb-core.lua. Functions call the internal Core.* implementation directly, never `exports.kora_core:fn()`, so GetInvokingResource() inside them is still the original caller (needed for owner-tracked commands, useables and registry entries). The Player wrapper returned by GetPlayer holds a legacy-shaped copy of PlayerData that is patched on every Core.player.setPath write. Exports are published under the qb-core identity with Kora.compat.provideExport. Outbound legacy events are fired by the native modules at their source; compat/server/qb-core-events.lua only handles the inbound side.

### Terms used on this page

| Term | Meaning |
| --- | --- |
| Legacy view | The detached PlayerData copy a QB wrapper exposes. Job and gang grade levels are converted from the native one-based level to the legacy zero-based level; payment and isboss are mirrored onto the grade; metadata and charinfo defaults are filled in but never persisted; position carries both `h` and `w`; `optin` defaults to true. |
| Player wrapper | The `{ PlayerData, Functions, Offline }` object legacy code gets from GetPlayer. Every Functions entry is also callable directly on the object, with dot or colon syntax. |
| Identity hijack | Answering `exports['qb-core']` calls by registering `__cfx_export_qb-core_<name>` event handlers (Kora.compat.provideExport) instead of owning a resource called qb-core. |
| Callback wire | The raw net events QBCore:Server:TriggerCallback and QBCore:Client:TriggerCallback that stock qb-core uses, bridged to kora_lib Kora.callback. |
| Offline wrapper | A Player-shaped object over a database snapshot. Edits change the snapshot and persist only when Save is called. |
| Facade | The opt-in qbx_core / qbx_vehicles export surface for stock ox_inventory (Config.compat.qbxFacade). |
| Grade conversion | Legacy grades are zero-based, native grades are one-based. Calls that take or return a grade add or subtract one at the boundary; the native Core API never sees the legacy number. |

### How exports['qb-core'] is served

kora_core is not a resource named qb-core. An export call resolves by firing `__cfx_export_<resource>_<name>` and using the callback a handler hands back. `Kora.compat.provideExport(resource, name, func)` in kora_lib/compat/provider.lua asserts a non-empty resource and export name and a callable, then registers `AddEventHandler('__cfx_export_<resource>_<name>', function(setCallback) setCallback(func) end)`. kora_core calls it with `qb-core` for GetCoreObject, GetShared, the five GetShared* wrappers and every function in QBCore.Functions that exists when compat/server/qb-core.lua finishes loading; SetMethod adds more at runtime. The values cross the export boundary as msgpack copies: metatables are lost, which is why the lazy QBCore.Shared views are forced into real keys at load, and callbacks arrive as function references. Calls that reach the same names through `exports.kora_core` are the native API and are unaffected.

### Manifest identities

fxmanifest.lua declares `provide 'qb-core'`. The manifest comment states what provide covers: another resource's `dependency 'qb-core'` check, and, together with the export hijack above, `exports['qb-core']:Fn()` calls. The hijack is registered only under the identity `qb-core` (and `qbx_core` / `qbx_vehicles` for the facade). Not provided on purpose: `qb-multicharacter`, because that compat is event and callback level only and taking the name would silently disable a real character-select UI; and `qbx_core`, because a fake resource of that name would flip third-party framework autodetection such as `GetResourceState('qbx_core')` onto qbx code paths.

### The missing @qb-core include

Provide does not make a file include like `'@qb-core/shared/locale.lua'` resolve: FiveM resolves an `@name/path` include against a real resource whose folder is named `name`. kora_core lists `shared/locale.lua` in `files` and the manifest comment points at a `[compat]/qb-core` stub resource for exactly this, but no `[compat]` folder or qb-core resource exists in this server's resources tree. A legacy script that includes `'@qb-core/shared/locale.lua'` will fail to load until such a folder is created.

### Callback wire

CreateCallback stores the handler in one table keyed by name and registers a Kora.callback.register wrapper. Both transports, kora_lib and the raw `QBCore:Server:TriggerCallback` net event, look the current handler up in that table at dispatch time, so re-registering a name after a resource restart updates both without running a request twice. The wrapper gives the handler a responder `cb(...)` and awaits it; a handler that returns without calling `cb` is released after Config.compat.callbackTimeoutMs (5000) and the reply is empty. On the raw wire the handler runs in a pcall with a responder that sends `QBCore:Client:TriggerCallback`; unknown names and non-string names are ignored. In the other direction TriggerCallback forwards to Kora.callback.trigger and passes every returned value to the callback, while TriggerClientCallback uses the raw `QBCore:Client:TriggerClientCallback` / `QBCore:Server:TriggerClientCallback` pair only, because also going through kora_lib would run the client handler twice.

### Validation of client-triggerable legacy events

Every legacy event a client can fire is checked before it reaches Core. QBCore:Server:SetMetaData accepts only keys set true in Config.compat.clientMetadataKeys, rejects starterItems, and clamps hunger, thirst and stress to finite numbers 0..100. QBCore:ToggleDuty needs the toggleDutyEvent flag, a loaded player on a non-default job and a 2000 ms cooldown. QBCore:UpdatePlayer has a 10 s per-player cooldown and never ticks hunger or thirst. QBCore:DebugSomething has a 1 s cooldown. QBCore:Server:CloseServer and OpenServer require admin and kick the caller otherwise. QBCore:CallCommand needs the `command.<name>` ACE, caps args at 16 entries and honours argsrequired. hud:server:GainStress and RelieveStress are type-checked, floored to 1..100, rate-limited, skipped for whitelisted jobs and skipped while qb-hud runs. The default commands re-validate every argument and re-check the permission level because QBCore:CallCommand reaches the raw callback with only the ACE checked; every use of a non-user command is written to Core.logging under category admin. Cooldown tables are cleared when the player drops.

### Legacy data shape

Native job and gang grades are one-based; legacy code reads zero-based levels and indexes `grades` by the strings '0', '1'. The compat converts at the boundary: Player.PlayerData and Shared.Jobs / Shared.Gangs are views, SetJob and SetGang add one to the grade, the default commands add one, GetGroups in the facade subtracts one. PlayerData is a detached copy, so direct edits like `Player.PlayerData.metadata.x = 1` only reach the authoritative state when Player.Functions.UpdateClient (or Save) reconciles them. The physical-cash account is an item stack: its ledger value is a constant 0 and the view shows the real item balance, so a `money` write applies the difference as an addMoney or removeMoney call and refuses the whole write if it would overdraw.

### Command registration

QBCore.Commands.Add forwards to Core.commands.addCommand through a wrapper that fires the cancellable QBCore:Server:PreCommandExecution first, grants each permission level the `command.<name>` ACE (levels god and user excepted), and records params, argsrequired and the raw callback so QBCore:CallCommand can run it in-process. Several permission levels are accepted; the native check uses the least privileged one. QBCore.Commands.List is rebuilt only on Add and Refresh.

### qbx facade

Off by default and, when off, registers nothing. When enabled it publishes qbx_core GetPlayer, GetPlayersData, CanUseItem, GetGroups, IsGradeBoss and qbx_vehicles GetVehicleIdByPlate through the same export hijack, fires the qbx group events when the active job or gang changes, and sets the `loadInventory` state bag once the player is fully logged in. It exists so an unmodified ox_inventory with `inventory:framework qbx` runs on kora_core. It refuses to start if a real qbx_core or qbx_vehicles resource exists.

### Stubs and no-ops

QBCore:Server:UpdateObject is registered as a net event with an empty body. QBCore:Client:SharedUpdate is an empty client handler (the server only sends it when Config.compat.fireSharedUpdateAtLogin is true). qb-multicharacter:server:getSkin always returns nil, GetNumberOfCharacters always returns an empty countries list, and qb-multicharacter:server:GetServerLogs is deliberately not implemented. qb-spawn:server:getOwnedHouses always returns an empty table. Those callbacks are registered with Kora.callback only, so they answer Kora.callback.trigger (what kora_multichar uses) but not a raw-wire QBCore.Functions.TriggerCallback call. QBCore.Functions.ExecuteSql prints a deprecation warning and ignores its wait argument. Offline wrappers never fire events or touch the live funnel.

### Other caveats

QBCore.Shared.Items, Weapons, Vehicles, Jobs, Gangs and Locations are read-only compatibility views; writes to them do not reach the registry (use the Functions.AddItem family). GetPlayersInBucket and GetEntitiesInBucket only know players and entities moved through SetPlayerBucket and SetEntityBucket. TriggerClientCallback in its synchronous form has no timeout. Functions defined by another resource on a name the compat already owns are not replaced: SetMethod refuses an existing name.

## Client

The client half of the qb-core compatibility layer: QBCore.Functions, QBCore.Shared and QBCore.PlayerData for legacy client scripts, the legacy events the client accepts or fires locally, and the exports['qb-core'] surface including the DrawText prompt family.

Namespace: `qb-core` · Source: `compat/shared/coreobject.lua, compat/client/qb-core.lua, qb-core-events.lua, config.lua (Config.compat)`

### Gating keys read on the client (Config.compat)

Config is a shared script; these are the keys the client realm reads, with the shipped defaults. The server-only keys are listed on the server page.

| Key | Default | Effect |
| --- | --- | --- |
| Config.compat.callbackTimeoutMs | 5000 | Await-form TriggerCallback resolves nil after this long; CreateClientCallback handlers that never call their responder resolve empty after it. |
| Config.compat.fireLegacyPlayerDataEvent | true | Fire QBCore:Player:SetPlayerData locally from the mirror. false stops the event. |
| Config.compat.inventoryPlayerDataEventInterval | 250 | Coalescing window in ms for inventory-only SetPlayerData notifications; 0 fires every delta. |
| Config.compat.jobUpdateEventSource | 'client' | The client fires QBCore:Client:OnJobUpdate, OnGangUpdate and the job/gang OnPlayerUpdated unless this is 'server'. |
| Config.compat.vehicleSpawnCallbacks | 'limited' | QBCore.Functions.SpawnVehicle asks the server for a networked vehicle unless this is 'off'; a refusal falls back to a local vehicle. |

### QBCore.Functions (`QBCore.Functions.`)

#### Callbacks

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Functions.TriggerCallback('name', function(...) end, ...)` | `Raw wire: fires QBCore:Server:TriggerCallback with the arguments (the callback is not forwarded) and queues the entry per name; the reply on QBCore:Client:TriggerCallback calls cb(...). Also stores the entry in QBCore.ServerCallbacks[name]. Replies resolve first-in-first-out per name` |
| `QBCore.Functions.TriggerCallback('name', nil, ...)` | `Await form (first extra argument not callable, nil is forwarded): must run inside a thread (errors otherwise), parks until the reply and returns its first value. Resolves nil after Config.compat.callbackTimeoutMs (5000) and prints a warning` |
| `QBCore.Functions.CreateClientCallback('name', function(cb, ...) end)` | `Stores the handler and registers a Kora.callback.register wrapper that gives it a responder `cb` (promise bridge, resolves empty after callbackTimeoutMs). Also served on the raw QBCore:Client:TriggerClientCallback event, which replies with QBCore:Server:TriggerClientCallback` |
| `QBCore.Functions.CreateCallback('name', function(cb, ...) end)` | `Alias of CreateClientCallback kept for kora resources (not part of stock client qb-core)` |

#### Player data and items

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Functions.GetPlayerData(cb)` | `Returns QBCore.PlayerData, the legacy-shaped mirror (zero-based grade level) kept current by modules/replication/client.lua; also calls cb(data) when given. Native: Core.replication.getData, Core.player.getPlayerData(path)` |
| `QBCore.Functions.GetName()` | ``charinfo.firstname .. ' ' .. charinfo.lastname` read with Core.replication.getData(&#123; 'charinfo' &#125;)` |
| `QBCore.Functions.HasItem(items, amount)` | `exports.kora_inventory:HasItem(items, amount) when kora_inventory is started; otherwise counts the replicated `items` mirror (name, array or { name = amount } forms)` |
| `QBCore.Functions.IsWearingGloves()` | `Core.player.isWearingGloves()` |
| `QBCore.Functions.GetCoords(entity)` | `vector4(GetEntityCoords(entity), GetEntityHeading(entity))` |

#### Notifications and UI

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Functions.Notify('text', 'success', 5000, icon)` | `Kora.notify.send({ type, message, duration = length or 5000, icon }). Types map: primary, inform, info, police, ambulance -> info; success, warning, error unchanged; anything else -> info. A table `&#123; text, caption &#125;` maps caption to the title; locale-reference tables are resolved through exports.kora_lib:locale_translate` |
| `QBCore.Functions.Progressbar('name', 'label', duration, useWhileDead, canCancel, disableControls, animation, prop, propTwo, onFinish, onCancel)` | `exports['progressbar']:Progress({ name, label, duration, useWhileDead, canCancel, controlDisables, animation, prop, propTwo }, cb, owner); onFinish or onCancel is called from the result. Requires a resource providing the progressbar export` |
| `QBCore.Functions.DrawText(x, y, width, height, scale, r, g, b, a, text)` | `Ported stock screen-text draw (font 4). Not the same as exports['qb-core']:DrawText, which is the prompt family` |
| `QBCore.Functions.DrawText3D(x, y, z, text)` | `Ported stock world-space text with a black backing rectangle` |
| `QBCore.Functions.Draw3DText(coords, text, opts)` | `Kora.drawing.text3d(coords, text, opts); kora alias, not stock` |

#### Players and entity lookup

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Functions.GetPlayers()` | `GetActivePlayers()` |
| `QBCore.Functions.GetPeds(ignoreList)` | `GetGamePool('CPed') without the ignored handles` |
| `QBCore.Functions.GetVehicles()` | `GetGamePool('CVehicle')` |
| `QBCore.Functions.GetObjects()` | `GetGamePool('CObject')` |
| `QBCore.Functions.GetPlayersFromCoords(coords, distance)` | `Kora.world.getNearbyEntities('player', coords, distance or 5) mapped from ped handles back to player ids; coords default to the local ped` |
| `QBCore.Functions.GetClosestPlayer(coords)` | `Kora.world.getClosestEntity('player', coords, { excludeEntities = { ped } }) mapped back to a player id; returns (playerId, distance) or (-1, -1)` |
| `QBCore.Functions.GetClosestPed(coords, ignoreList)` | `Kora.world.getClosestEntity('ped', coords, { excludeEntities = ignoreList }); returns (entity, distance) or (-1, -1)` |
| `QBCore.Functions.GetClosestVehicle(coords)` | `Kora.world.getClosestEntity('vehicle', coords); returns (entity, distance) or (-1, -1)` |
| `QBCore.Functions.GetClosestObject(coords)` | `Kora.world.getClosestEntity('object', coords); returns (entity, distance) or (-1, -1)` |
| `QBCore.Functions.GetClosestBone(entity, list)` | `Ported: nearest listed bone to the local ped; falls back to 'bodyshell'. Returns (bone, coords, distance)` |
| `QBCore.Functions.GetBoneDistance(entity, boneType, boneIndex)` | `Ported: distance from the local ped to a ped bone (type 1) or entity bone name` |
| `QBCore.Functions.SpawnClear(coords, radius)` | `true when no vehicle in the pool lies within radius of coords` |

#### Vehicles

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Functions.SpawnVehicle('model', cb, coords, isnetworked, teleportInto)` | `Networked by default: relays to the server callback QBCore:Server:SpawnVehicle (skipped when Config.compat.vehicleSpawnCallbacks is 'off' or the caller cannot yield). On refusal it prints a one-time warning and creates a local, non-networked vehicle. Passing isnetworked = false goes straight to the local path. Applies owned-vehicle defaults (fuel 100, radio off), optional warp, calls cb(vehicle)` |
| `QBCore.Functions.LoadModel('model', timeout)` | `RequestModel then waits through Kora.loops.controlled (default 5000 ms); returns (loaded, model). false for an invalid model` |
| `QBCore.Functions.DeleteVehicle(vehicle)` | `SetEntityAsMissionEntity then DeleteVehicle` |
| `QBCore.Functions.GetPlate(vehicle)` | `Trimmed GetVehicleNumberPlateText; nil for handle 0` |
| `QBCore.Functions.GetVehicleLabel(vehicle)` | `Display label text of the model; nil for nil or 0` |
| `QBCore.Functions.GetVehicleProperties(vehicle)` | `Ported stock property table (model, plate, health values, colours, wheels, tyres, windows, doors, neon, extras, mods 0-49, livery, xenon, tyre smoke); nil when the entity is missing` |
| `QBCore.Functions.SetVehicleProperties(vehicle, props)` | `Ported stock property applier for the same table` |

#### Streaming and animation

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Functions.RequestAnimDict('dict', timeout)` | `Waits for the dictionary with Kora.loops.controlled (default 5000 ms); returns (loaded, dict); false when the dictionary does not exist` |
| `QBCore.Functions.LoadAnimDict('dict', cb)` | `Kora.stream.loadAnimDict(dict, cb); kora alias, not stock` |
| `QBCore.Functions.LoadAnimSet('set', timeout)` | `RequestAnimSet and wait; returns (loaded, set)` |
| `QBCore.Functions.PlayAnim('dict', 'name', upperbodyOnly, duration)` | `Loads the dict with Kora.stream.loadAnimDict, plays TaskPlayAnim (flags 16 upper body, 49 when duration is -1) and waits the clip length (or duration); returns the clip length. Bad input or a missing dictionary or clip rejects an internal promise (message prefixed with the invoking resource) and the call returns nil` |
| `QBCore.Functions.LookAtEntity(entity, timeout, speed)` | `Turns the local ped toward the entity; speed capped at 5.0, timeout at 5000 ms. Invalid input returns an error string` |
| `QBCore.Functions.AttachProp(ped, 'model', boneId, x, y, z, xR, yR, zR, vertex)` | `LoadModel, CreateObject (local) and AttachEntityToEntity; returns the prop or false` |
| `QBCore.Functions.LoadParticleDictionary('dict', timeout)` | `RequestNamedPtfxAsset and wait; returns (loaded, dict)` |
| `QBCore.Functions.StartParticleAtCoord(dict, ptName, looped, coords, rot, scale, alpha, color, duration)` | `Loads the dictionary, then starts a looped or one-shot particle at coords; returns the loop handle (or false when loading fails)` |
| `QBCore.Functions.StartParticleOnEntity(dict, ptName, looped, entity, bone, offset, rot, scale, alpha, color, evolution, duration)` | `Same on an entity or one of its bones; returns the loop handle` |

#### World information

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Functions.GetStreetNametAtCoords(coords)` | `Returns { main, cross } street names (the stock misspelt function name is kept; there is no GetStreetNameAtCoords)` |
| `QBCore.Functions.GetZoneAtCoords(coords)` | `Label text of GetNameOfZone(coords)` |
| `QBCore.Functions.GetCardinalDirection(entity)` | `'North', 'West', 'South' or 'East' from the heading (45-135 is West, 225-315 is East); defaults to the local ped` |
| `QBCore.Functions.GetCurrentTime()` | `{ min, hour, ampm } plus formattedHour only from hour 13 on and formattedMin only when minutes are 0-9 (stock behaviour)` |
| `QBCore.Functions.GetGroundZCoord(coords)` | `vector3 with the ground Z when found, otherwise the input coords; nil without coords` |
| `QBCore.Functions.GetGroundHash(entity)` | `Shape-test capsule under the entity; returns (materialHash, entityHit, surfaceNormal, endCoords, success, retval)` |

### QBCore object fields (`QBCore.`)

#### Fields

| Legacy call | Becomes |
| --- | --- |
| `QBCore.PlayerData` | `The live legacy-shaped PlayerData table, updated in place on every replication delta (keeps captured references current); empty before login` |
| `QBCore.ServerCallbacks` | `Pending reply entries for QBCore.Functions.TriggerCallback, keyed by callback name` |
| `QBCore.Config` | `Same populated configuration as the server (MaxPlayers, DefaultSpawn, Money, Player, Server, Commands, Notify), built locally by Core.compat.populateLegacyConfig` |
| `QBCore.Debug(table, indent)` | `Recursive table printer` |
| `QBCore.ShowError('resource', 'message')` | `print in red: '[resource] message'` |
| `QBCore.ShowSuccess('resource', 'message')` | `print in green: '[resource] message'` |

### QBCore.Shared (`QBCore.Shared.`)

#### Helper functions

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Shared.Round(value, decimals)` | `Core.util.round` |
| `QBCore.Shared.Trim(value)` | `Core.util.trim` |
| `QBCore.Shared.SplitStr(str, delimiter)` | `Core.util.splitStr` |
| `QBCore.Shared.RandomStr(length)` | `Core.util.randomStr` |
| `QBCore.Shared.RandomInt(length)` | `Core.util.randomInt` |
| `QBCore.Shared.FirstToUpper(value)` | `Uppercases the first lowercase letter` |
| `QBCore.Shared.IsFunction(value)` | `true for a function, a function reference, or a table with a callable __call` |
| `QBCore.Shared.ChangeVehicleExtra(vehicle, extra, enable)` | `Client only: toggles one extra and retries until the change sticks` |
| `QBCore.Shared.SetDefaultVehicleExtras(vehicle, config)` | `Client only: turns extras 1-20 off, then applies the on/off overrides in config` |

#### Constants

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Shared.StarterItems` | `{ phone, id_card, driver_license }, each `&#123; amount = 1, item = name &#125;`` |
| `QBCore.Shared.MaleNoGloves` | `Set of component-3 drawables meaning no gloves (male)` |
| `QBCore.Shared.FemaleNoGloves` | `Same set for the female ped` |
| `QBCore.Shared.ForceJobDefaultDutyAtLogin` | `true` |

#### Registry views

| Legacy call | Becomes |
| --- | --- |
| `QBCore.Shared.Items` | `Live view over the replicated 'weapons' and 'items' registries; may be empty until the registry snapshot arrives, then refreshes in place` |
| `QBCore.Shared.Weapons` | `Hash-keyed view with damage metadata` |
| `QBCore.Shared.Vehicles` | `Model-keyed view` |
| `QBCore.Shared.VehicleHashes` | `Vehicles keyed by joaat(model)` |
| `QBCore.Shared.Jobs` | `Jobs with zero-based string grade keys` |
| `QBCore.Shared.Gangs` | `Gangs with zero-based string grade keys` |
| `QBCore.Shared.Locations` | `Name-keyed locations view` |

### Legacy events handled on the client |

#### Net events the client accepts

| Legacy call | Becomes |
| --- | --- |
| `RegisterNetEvent('QBCore:Notify')` | `Calls QBCore.Functions.Notify(text, type, length, icon) so server-side notices reach Kora.notify.send` |
| `RegisterNetEvent('QBCore:Client:OnPlayerLoaded')` | `Requests a replication resync if the mirror is still empty. The event itself is fired by the server` |
| `RegisterNetEvent('QBCore:Client:OnPlayerUnload')` | `Empty handler (registered so the server trigger is network-safe); the replication module clears the mirror on the same event` |
| `RegisterNetEvent('QBCore:Client:OnPlayerUpdated')` | `Never applies the payload. Key nil or 'all' calls Core.replication.reannounceFull(); 'job' and 'gang' re-fire QBCore:Client:OnJobUpdate / OnGangUpdate from the mirror (skipped when the replication module already fired them); other keys are ignored` |
| `RegisterNetEvent('QBCore:Client:OnSharedUpdate')` | `Writes `QBCore.Shared[tableName][key] = value` on the local view, then fires QBCore:Client:UpdateObject. A later registry delta overrides it` |
| `RegisterNetEvent('QBCore:Client:OnSharedUpdateMultiple')` | `Same for a table of keys, then QBCore:Client:UpdateObject` |
| `RegisterNetEvent('QBCore:Client:SharedUpdate')` | `Empty handler: the event name fires but nothing is applied` |
| `RegisterNetEvent('QBCore:Player:SetPlayerData')` | `Replication module: a foreign trigger merges the table into the mirror with a console warning, and is overwritten by the next server snapshot. kora_core's own re-fires carry a private token and are ignored` |
| `RegisterNetEvent('QBCore:Client:TriggerCallback')` | `Raw callback reply: resolves the oldest pending TriggerCallback entry for that name` |
| `RegisterNetEvent('QBCore:Client:TriggerClientCallback')` | `Raw request from the server: runs the handler registered with CreateClientCallback in a pcall; the responder sends QBCore:Server:TriggerClientCallback` |
| `RegisterNetEvent('QBCore:Command:TeleportToCoords')` | `SetPedCoordsKeepVehicle to x, y, z and sets the heading when given` |
| `RegisterNetEvent('QBCore:Command:TeleportToPlayer')` | `SetPedCoordsKeepVehicle to the given coords` |
| `RegisterNetEvent('QBCore:Command:GoToMarker')` | `Waypoint teleport: fades out, probes ground Z from 950 down in 25 m steps, restores the old position and notifies when no ground is found. Returns 'marker' when there is no waypoint` |
| `RegisterNetEvent('QBCore:Command:SpawnVehicle')` | `Deletes the vehicle the ped is in and spawns the named model through QBCore.Functions.SpawnVehicle (networked when the server accepts, else local), cleans it and fires vehiclekeys:client:SetOwner with the plate` |
| `RegisterNetEvent('QBCore:Command:DeleteVehicle')` | `Deletes the occupied vehicle, or every vehicle within 5.0 m on foot` |
| `RegisterNetEvent('QBCore:Command:ShowMe3D')` | `Draws the message above the sender for 5 seconds` |
| `RegisterNetEvent('QBCore:Client:PvpHasToggled')` | `SetCanAttackFriendly(ped, enabled, false) and NetworkSetFriendlyFireOption(enabled)` |
| `RegisterNetEvent('qb-core:client:DrawText')` | `Starts the on-screen prompt with (text, position); same as exports['qb-core']:DrawText` |
| `RegisterNetEvent('qb-core:client:ChangeText')` | `Same prompt, new text` |
| `RegisterNetEvent('qb-core:client:HideText')` | `Hides the prompt` |
| `RegisterNetEvent('qb-core:client:KeyPressed')` | `Hides the prompt after 500 ms` |

#### Local events fired

| Legacy call | Becomes |
| --- | --- |
| `AddEventHandler('QBCore:Player:SetPlayerData', function(data) end)` | `Full legacy PlayerData, fired when replication applies a change. Inventory-only changes are coalesced for Config.compat.inventoryPlayerDataEventInterval (default 250 ms; 0 fires per delta); the whole event is gated by Config.compat.fireLegacyPlayerDataEvent` |
| `AddEventHandler('QBCore:Client:OnJobUpdate', function(job) end)` | `Fired when the job root changes, unless Config.compat.jobUpdateEventSource is 'server'. Legacy-shaped job` |
| `AddEventHandler('QBCore:Client:OnGangUpdate', function(gang) end)` | `Same for the gang root` |
| `AddEventHandler('QBCore:Client:OnPlayerUpdated', function(key, value) end)` | `Fired with 'job' or 'gang' next to the two events above` |
| `AddEventHandler('QBCore:Client:UpdateObject', function() end)` | `Fired after OnSharedUpdate and OnSharedUpdateMultiple` |
| `AddEventHandler('QBCore:Client:VehicleInfo', function(info) end)` | `Built from Kora.cache changes (seat, enteringVehicle, vehicle) with vehicle, seat, name, modelName, netId and event; the compat handler then re-fires the three events below` |
| `AddEventHandler('QBCore:Client:EnteringVehicle', function(data) end)` | `data { vehicle, seat, name, plate, driver, inseat, haskeys }; haskeys comes from exports['qb-vehiclekeys']:HasKeys(plate) when qb-vehiclekeys is started, otherwise true` |
| `AddEventHandler('QBCore:Client:EnteredVehicle', function(data) end)` | `Same payload once the player is seated` |
| `AddEventHandler('QBCore:Client:LeftVehicle', function(data) end)` | `Same payload with the last occupied seat` |
| `AddEventHandler('QBCore:Client:AbortVehicleEntering', function() end)` | `Fired when an entering animation ends without a vehicle` |

### qb-core exports (`exports['qb-core']:`)

#### Core object and shared data

| Legacy call | Becomes |
| --- | --- |
| `exports['qb-core']:GetCoreObject(filters)` | `Returns QBCore, or the keys named in `filters`. Not gated by Config.compat.coreObjectExport on the client` |
| `exports['qb-core']:GetShared('Items', 'item')` | `QBCore.Shared[namespace] with canonical-case fallback; item key optional` |
| `exports['qb-core']:GetSharedItems()` | `GetShared('Items')` |
| `exports['qb-core']:GetSharedVehicles()` | `GetShared('Vehicles')` |
| `exports['qb-core']:GetSharedJobs()` | `GetShared('Jobs')` |
| `exports['qb-core']:GetSharedGangs()` | `GetShared('Gangs')` |
| `exports['qb-core']:GetSharedWeapons()` | `GetShared('Weapons')` |

#### On-screen prompt family

| Legacy call | Becomes |
| --- | --- |
| `exports['qb-core']:DrawText('text', 'left')` | `Per-frame native text with a dark backing box. Positions 'left' (0.10, 0.50), 'right' (0.90, 0.50), 'top' (0.50, 0.05); anything else uses left. Replaces QBCore.Functions.DrawText for this export name, as stock does` |
| `exports['qb-core']:ChangeText('text', 'left')` | `Same function as DrawText: updates the text of the running prompt` |
| `exports['qb-core']:HideText()` | `Stops the prompt thread and clears the state` |
| `exports['qb-core']:KeyPressed()` | `Hides the prompt after 500 ms (no NUI press animation)` |

#### Direct function exports

| Legacy call | Becomes |
| --- | --- |
| `exports['qb-core']:TriggerCallback(name, cb, ...)` | `QBCore.Functions.TriggerCallback` |
| `exports['qb-core']:CreateClientCallback(name, handler)` | `QBCore.Functions.CreateClientCallback` |
| `exports['qb-core']:CreateCallback(name, handler)` | `QBCore.Functions.CreateCallback` |
| `exports['qb-core']:GetPlayerData(cb)` | `QBCore.Functions.GetPlayerData` |
| `exports['qb-core']:GetName()` | `QBCore.Functions.GetName` |
| `exports['qb-core']:GetCoords(entity)` | `QBCore.Functions.GetCoords` |
| `exports['qb-core']:HasItem(items, amount)` | `QBCore.Functions.HasItem` |
| `exports['qb-core']:LookAtEntity(entity, timeout, speed)` | `QBCore.Functions.LookAtEntity` |
| `exports['qb-core']:PlayAnim(animDict, animName, upperbodyOnly, duration)` | `QBCore.Functions.PlayAnim` |
| `exports['qb-core']:IsWearingGloves()` | `QBCore.Functions.IsWearingGloves` |
| `exports['qb-core']:Notify(text, type, length, icon)` | `QBCore.Functions.Notify` |
| `exports['qb-core']:Progressbar(name, label, duration, useWhileDead, canCancel, disableControls, animation, prop, propTwo, onFinish, onCancel)` | `QBCore.Functions.Progressbar` |
| `exports['qb-core']:GetVehicles()` | `QBCore.Functions.GetVehicles` |
| `exports['qb-core']:GetObjects()` | `QBCore.Functions.GetObjects` |
| `exports['qb-core']:GetPlayers()` | `QBCore.Functions.GetPlayers` |
| `exports['qb-core']:GetPlayersFromCoords(coords, distance)` | `QBCore.Functions.GetPlayersFromCoords` |
| `exports['qb-core']:GetClosestPlayer(coords)` | `QBCore.Functions.GetClosestPlayer` |
| `exports['qb-core']:GetPeds(ignoreList)` | `QBCore.Functions.GetPeds` |
| `exports['qb-core']:GetClosestPed(coords, ignoreList)` | `QBCore.Functions.GetClosestPed` |
| `exports['qb-core']:GetClosestVehicle(coords)` | `QBCore.Functions.GetClosestVehicle` |
| `exports['qb-core']:GetClosestObject(coords)` | `QBCore.Functions.GetClosestObject` |
| `exports['qb-core']:LoadModel(model, timeout)` | `QBCore.Functions.LoadModel` |
| `exports['qb-core']:SpawnVehicle(model, cb, coords, isnetworked, teleportInto)` | `QBCore.Functions.SpawnVehicle` |
| `exports['qb-core']:DeleteVehicle(vehicle)` | `QBCore.Functions.DeleteVehicle` |
| `exports['qb-core']:GetPlate(vehicle)` | `QBCore.Functions.GetPlate` |
| `exports['qb-core']:GetVehicleLabel(vehicle)` | `QBCore.Functions.GetVehicleLabel` |
| `exports['qb-core']:GetVehicleProperties(vehicle)` | `QBCore.Functions.GetVehicleProperties` |
| `exports['qb-core']:SetVehicleProperties(vehicle, props)` | `QBCore.Functions.SetVehicleProperties` |
| `exports['qb-core']:DrawText3D(x, y, z, text)` | `QBCore.Functions.DrawText3D` |
| `exports['qb-core']:Draw3DText(coords, text, opts)` | `QBCore.Functions.Draw3DText` |
| `exports['qb-core']:RequestAnimDict(animDict, timeout)` | `QBCore.Functions.RequestAnimDict` |
| `exports['qb-core']:LoadAnimDict(dict, cb)` | `QBCore.Functions.LoadAnimDict` |
| `exports['qb-core']:GetClosestBone(entity, list)` | `QBCore.Functions.GetClosestBone` |
| `exports['qb-core']:GetBoneDistance(entity, boneType, boneIndex)` | `QBCore.Functions.GetBoneDistance` |
| `exports['qb-core']:AttachProp(ped, model, boneId, x, y, z, xR, yR, zR, vertex)` | `QBCore.Functions.AttachProp` |
| `exports['qb-core']:SpawnClear(coords, radius)` | `QBCore.Functions.SpawnClear` |
| `exports['qb-core']:LoadAnimSet(animSet, timeout)` | `QBCore.Functions.LoadAnimSet` |
| `exports['qb-core']:LoadParticleDictionary(dictionary, timeout)` | `QBCore.Functions.LoadParticleDictionary` |
| `exports['qb-core']:StartParticleAtCoord(dict, ptName, looped, coords, rot, scale, alpha, color, duration)` | `QBCore.Functions.StartParticleAtCoord` |
| `exports['qb-core']:StartParticleOnEntity(dict, ptName, looped, entity, bone, offset, rot, scale, alpha, color, evolution, duration)` | `QBCore.Functions.StartParticleOnEntity` |
| `exports['qb-core']:GetStreetNametAtCoords(coords)` | `QBCore.Functions.GetStreetNametAtCoords` |
| `exports['qb-core']:GetZoneAtCoords(coords)` | `QBCore.Functions.GetZoneAtCoords` |
| `exports['qb-core']:GetCardinalDirection(entity)` | `QBCore.Functions.GetCardinalDirection` |
| `exports['qb-core']:GetCurrentTime()` | `QBCore.Functions.GetCurrentTime` |
| `exports['qb-core']:GetGroundZCoord(coords)` | `QBCore.Functions.GetGroundZCoord` |
| `exports['qb-core']:GetGroundHash(entity)` | `QBCore.Functions.GetGroundHash` |

### How it works

compat/client/qb-core.lua mixes two strategies. Self-contained native helpers (vehicle properties, particles, ground and zone lookups) are ported near-verbatim from qb-core. The few that touch player or UI state forward to kora_lib or the replicated mirror: Notify to Kora.notify.send, entity lookups to Kora.world, HasItem to kora_inventory, GetPlayerData to QBCore.PlayerData. After the Functions table is built, each function is published as `exports['qb-core']:Name` with Kora.compat.provideExport, then GetCoreObject, GetShared, the GetShared* wrappers and the on-screen prompt exports. QBCore.PlayerData is the legacy-shaped mirror, updated in place by modules/replication/client.lua; the events that announce changes (QBCore:Player:SetPlayerData, OnJobUpdate, OnGangUpdate, OnPlayerUpdated) fire locally from there.

### Terms used on this page

| Term | Meaning |
| --- | --- |
| Mirror | The replicated, server-authoritative PlayerData copy on the client. QBCore.PlayerData is its legacy-shaped view with zero-based grade levels. |
| Prompt family | exports['qb-core']:DrawText, ChangeText, HideText and KeyPressed: a persistent on-screen prompt drawn natively each frame. A different function from QBCore.Functions.DrawText. |
| Callback wire | QBCore:Server:TriggerCallback out, QBCore:Client:TriggerCallback back; and QBCore:Client:TriggerClientCallback in, QBCore:Server:TriggerClientCallback back. |
| Identity hijack | Registering `__cfx_export_qb-core_<name>` handlers so exports['qb-core'] resolves to kora_core functions. |

### How exports['qb-core'] is served on the client

The client cannot call `exports()` under another resource's name, so it uses the same `__cfx_export_qb-core_<name>` hijack as the server (Kora.compat.provideExport from kora_lib/compat/provider.lua). Every function in QBCore.Functions is published, then GetCoreObject (with the optional `filters` array), GetShared, GetSharedItems/Vehicles/Jobs/Gangs/Weapons and the prompt family. Unlike the server, the client exports are not gated by Config.compat.coreObjectExport. The provides in fxmanifest.lua (`kora_core`, `qb-core`) make the resource name resolvable; the identity hijack does the function routing. No `[compat]/qb-core` stub exists in this server tree, so `'@qb-core/shared/locale.lua'` includes do not resolve.

### Callback wire

TriggerCallback sends QBCore:Server:TriggerCallback and queues the pending entry per name. The reply carries only the name, so concurrent calls of one name are answered first-in-first-out. The await form (no callback function) must run inside a thread and resolves nil after Config.compat.callbackTimeoutMs. CreateClientCallback stores the handler once and serves it both through Kora.callback and through the raw QBCore:Client:TriggerClientCallback event, looking the handler up at dispatch time so a re-registration takes effect on both.

### Prompt exports shadow DrawText

Stock qb-core exports two different functions under the name DrawText: the world-text function in functions.lua and the prompt in drawtext.lua, the later one winning. The compat mirrors this by registering the prompt family after the Functions loop, so `exports['qb-core']:DrawText(text, position)` is the prompt while `QBCore.Functions.DrawText(x, y, ...)` stays the world-text function. The prompt is drawn natively each frame at one of three anchors; KeyPressed only hides it after 500 ms.

### Inbound events and trust

Events such as QBCore:Command:TeleportToCoords, SpawnVehicle and DeleteVehicle act only on the local player and are normally sent by the server. QBCore:Client:OnPlayerUpdated never applies its payload to the mirror: it only re-announces what the mirror already holds, so a foreign resource cannot desynchronise it. QBCore:Player:SetPlayerData from a foreign resource is merged into the mirror with a console warning and is overwritten by the next server snapshot.

### Stubs and caveats

QBCore:Client:SharedUpdate is an empty handler. QBCore:Client:OnSharedUpdate and OnSharedUpdateMultiple patch the local view as a best effort and a later registry delta overrides them. QBCore.Functions.SpawnVehicle falls back to a local, non-networked vehicle when the server refuses; Progressbar requires a resource that provides the `progressbar` export; Notify maps unknown types to info; QBCore.Functions.GetStreetNametAtCoords keeps the stock misspelt name. CreateCallback, LoadAnimDict and Draw3DText are kora aliases that stock qb-core does not have. The Shared views can be empty until the registry snapshot arrives and refill in place afterwards.

## Compatibility surface overview (code-derived)

kora_core declares `provide 'qb-core'`, which satisfies other resources'
`dependency 'qb-core'`. The `qb-core` exports themselves are published with
kora_lib's export bridge (`Kora.compat.provideExport`). `provide` does not make
`@qb-core/...` file includes resolve; a separate `[compat]/qb-core` resource does
that (kora_core ships `shared/locale.lua` in its `files` for it). kora_core does
not provide `qb-multicharacter` or `qb-inventory`.

The legacy layer calls the native modules directly, so legacy and native calls
share validation, persistence, replication and events.

### Exports

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

### Core object

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

### Player object (server)

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

### QBCore.Functions (server)

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
  [Callbacks](./events.md)).
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

### QBCore.Functions (client)

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
[Vehicle spawn](../vehicle-spawn.md).

The draw-text events and exports (`DrawText`, `ChangeText`, `HideText`,
`KeyPressed`) draw a simple native text box at the `left`, `right` or `top`
position.

### Client PlayerData

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

### Commands

`QBCore.Commands.Add(name, help, args, argsRequired, cb, permission, ...)`
registers through `addCommand` with the lowest of the given levels, adds
`command.<name>` ACEs for `kora_core.<level>` (except `god` and `user`) and fires
`QBCore:Server:PreCommandExecution` before the callback. Extra levels make
`List[name].permission` an array. `QBCore.Commands.List` is keyed by lower-cased
name and includes `arguments`/`params`; it reflects commands present at the last
`Add` or `Refresh`. `QBCore:CallCommand` checks the `command.<name>` ACE and the
argument count like stock.

The 20 stock commands are on [Default qb-core commands](../default-commands.md).

### Legacy events

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

#### Stress events

`hud:server:GainStress(amount)` and `hud:server:RelieveStress(amount)` change the
sender's stress by a whole `amount` between 1 and 100 (clamped to 0..100), with
`Config.compat.stress` controlling the cooldown, job whitelist and an off switch.
They are ignored while a real `qb-hud` is started. The client receives
`hud:client:UpdateStress(value)` and a notification.

### qb-multicharacter and qb-spawn

kora_core answers the stock multicharacter protocol so a stock UI can work:

- Callbacks `qb-multicharacter:server:GetUserCharacters`, `GetNumberOfCharacters`,
  `setupCharacters`, `getSkin` (always `nil`), `deleteCharacter`, and
  `qb-spawn:server:getOwnedHouses` (always empty).
- Net events `qb-multicharacter:server:loadUserData` (select, then
  `qb-spawn:client:setupSpawns` and `qb-spawn:client:openUI`),
  `qb-multicharacter:server:createCharacter` (create, then
  `qb-multicharacter:client:closeNUIdefault`), `deleteCharacter` and `disconnect`.
  Failures send `multichar:client:selectFailed(err)`.

### Other compatibility pages

- [Default qb-core commands](../default-commands.md)
- [qbx facade for stock ox_inventory](../qbx-facade.md)
- [Stock vehicle spawn callbacks](../vehicle-spawn.md)
- [`player_vehicles` compatibility](../vehicles-compat.md)
