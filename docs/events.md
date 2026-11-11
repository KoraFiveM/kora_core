---
title: Events
sidebar_position: 6
---

# Events

Grades in legacy (`QBCore:*`) payloads are zero-based; native kora_core payloads
use one-based grades.

## Server events to listen to

These are local server events (`AddEventHandler`). Do not trigger them yourself
unless noted.

| Event | Payload | When |
| --- | --- | --- |
| `kora_core:server:playerLoaded` | `src, citizenid` | A character was adopted (after `QBCore:Server:PlayerLoaded`). |
| `kora_core:server:playerDropped` | `src, citizenid, reason` | After a dropped player was saved and evicted. |
| `kora_core:server:inventoryChanged` | `src, path, value` | Any write under `PlayerData.items`. |
| `kora_core:server:taxCollected` | `account, amount, reason` | A tax deposit succeeded. |
| `kora_core:server:devModeChanged` | `src, enabled` | Development mode changed. |
| `kora_core:server:dispatchAlert` | `payload, recipientCount` | Once per `alert` call, after fan-out. |
| `kora_core:server:onJailRequest` | `src, minutes, reason, resourceName` | `jailPlayer` deferred to an external prison resource. |
| `kora_core:server:playerJailed` | `src, minutes, reason` | Built-in jail applied. |
| `kora_core:server:playerReleased` | `src` | Built-in jail released. |
| `kora_core:server:databaseReady` | none | Schema and triggers are in place. |
| `kora_core:registry:delta` | `name, action, key, record, epoch` | A registry record was added, updated or removed (also sent to clients). |
| `kora_core:inventory:open` | `src, data` | `stashOpen` asks a UI resource to open a stash (`kind`, `identifier`, `slots`, `maxweight`). |
| `kora_voice:server:bucketChanged` | `src` | Fired by `setPlayerBucket`. |
| `QBCore:Server:PlayerLoaded` | `Player` | Legacy player object (`PlayerData`, `Functions`), same object as `QBCore.Players[src]`. |
| `QBCore:Server:OnPlayerUnload` | `src` | Logout or drop, before eviction. |
| `QBCore:Server:PlayerDropped` | `src, reason` | Drop, before eviction. |
| `QBCore:Server:OnJobUpdate` | `src, job` | `setJob` or `setJobDuty`. |
| `QBCore:Server:OnGangUpdate` | `src, gang` | `setGang`. |
| `QBCore:Server:OnPlayerUpdated` | `src, key, value` | Job/gang changes and legacy `UpdateClient`. With key `nil` or `all`, kora_core re-fires `OnJobUpdate` and `OnGangUpdate`. |
| `QBCore:Server:SetDuty` | `src, onDuty` | `setJobDuty`. |
| `QBCore:Server:OnMoneyChange` | `src, account, amount, action, reason` | Every balance change (`add`, `remove`, `set`). |
| `QBCore:Server:OnMetaDataChange` | `src, key, value` | `setMetaData` and `incrementMetaData`. |
| `QBCore:Server:UseItem` | `src, item` | Fallback `useItem` found no registered useable. |
| `QBCore:Server:PreCommandExecution` | `src, name, args, rawCommand` | Before every `QBCore.Commands.Add` command; `CancelEvent()` stops it. |
| `QBCore:Server:UpdateObject` | none | Legacy shared data or `QBCore.Functions` changed. |
| `QBCore:Player:SetPlayerData` | `PlayerData` | Server-side, from legacy `UpdateClient()` without a key. |
| `police:server:policeAlert` | `message` | A `police` dispatch alert with `Config.dispatch.legacyEvents`. |
| `qbx_core:server:playerLoggedOut` | `src` | qbx facade only. |
| `qbx_core:server:onGroupUpdate` | `src, group, grade` | qbx facade only; `grade` is `nil` when a group was removed. |

Events kora_core listens to and you may fire:

| Event | Payload | Effect |
| --- | --- | --- |
| `qb-log:server:CreateLog` | `name, title, color, message, tagEveryone, imageUrl` | Local only. Forwarded to `logEvent(name, 0, ...)` with strings truncated. |

## Client events to listen to

| Event | Payload | When |
| --- | --- | --- |
| `kora_core:client:playerLoaded` | `PlayerData` (the mirror) | Local event on every full snapshot (login and resyncs). |
| `kora_core:client:devModeChanged` | `enabled` | Local event when development mode changes. |
| `kora_core:client:dispatchAlert` | `payload` | Sent to each on-duty recipient of `alert`. |
| `kora_core:client:itemBox` | `itemDef, action, amount` | Fallback inventory add/remove (`add` or `remove`). |
| `kora_core:client:dropCreated` | `id, coords` | Fallback ground drop created (all clients). |
| `kora_core:client:dropRemoved` | `id` | Fallback ground drop removed (all clients). |
| `kora_core:client:jailTeleport` | `coords, remainingSeconds` | Built-in jail started (kora_core handles it). |
| `kora_core:client:jailRelease` | none | Built-in jail released. |
| `kora_core:client:receiveCharacters` | `characters` | Reply to `kora_core:server:requestCharacters`. |
| `kora_core:client:characterSelected` | `ok, err` | Result of select/create. |
| `kora_core:registry:synced` | none | Local event after a full registry snapshot. |
| `QBCore:Client:OnPlayerLoaded` | none | At login, or later with `Config.compat.deferClientPlayerLoaded`. |
| `QBCore:Client:OnPlayerUnload` | none | Logout. |
| `QBCore:Player:SetPlayerData` | `PlayerData` (legacy view) | Local re-fire after snapshots and deltas (see [Compatibility](./compatibility.md#client-playerdata)). |
| `QBCore:Client:OnJobUpdate` / `OnGangUpdate` | `job` / `gang` | Per `Config.compat.jobUpdateEventSource`. |
| `QBCore:Client:OnPlayerUpdated` | `key, value` | Job/gang changes and legacy `UpdateClient`. |
| `QBCore:Client:SetDuty` | `onDuty` | `setJobDuty`. |
| `QBCore:Client:OnMoneyChange` | `account, amount, action, reason` | Every balance change. |
| `hud:client:OnMoneyChange` | `account, amount, isRemove` | Every balance change. |
| `hud:client:UpdateNeeds` | `hunger, thirst` | Needs tick and `QBCore:UpdatePlayer`. |
| `hud:client:UpdateStress` | `stress` | Legacy stress events. |
| `qb-phone:client:RemoveBankMoney` | `amount` | Bank removals. |
| `police:client:policeAlert` | `coords, message` | Legacy dispatch. |
| `hospital:client:ambulanceAlert` | `coords, message` | Legacy dispatch. |
| `QBCore:Notify` | `text, type, length, icon` | Shown through `Kora.notify`. You may trigger it from the server. |
| `QBCore:Client:PvpHasToggled` | `enabled` | `/togglepvp` and at login while PVP is off. |
| `QBCore:Client:OnSharedUpdate` | `tableName, key, value` | Legacy shared add/update/remove. |
| `QBCore:Client:OnSharedUpdateMultiple` | `tableName, values` | Legacy bulk shared add. |
| `QBCore:Client:UpdateObject` | none | Local, after the shared updates above. |
| `QBCore:Client:EnteringVehicle`, `EnteredVehicle`, `LeftVehicle` | `data` | Local, derived from kora_lib's cache (`vehicle`, `seat`, `name`, `plate`, `driver`, `inseat`, `haskeys`). |
| `QBCore:Client:AbortVehicleEntering` | none | Local, entering was cancelled. |
| `qbx_core:client:setGroups` | `groups` | qbx facade only, once per load. |
| `qbx_core:client:onGroupUpdate` | `group, grade` | qbx facade only. |

Client events kora_core handles and other resources may trigger on a client:
`qb-core:client:DrawText(text, position)`, `qb-core:client:ChangeText(text, position)`,
`qb-core:client:HideText()`, `qb-core:client:KeyPressed()`,
`QBCore:Command:TeleportToPlayer(coords)`, `QBCore:Command:TeleportToCoords(x, y, z, h)`,
`QBCore:Command:GoToMarker()`, `QBCore:Command:SpawnVehicle(model)`,
`QBCore:Command:DeleteVehicle()`, `QBCore:Command:ShowMe3D(senderId, message)`.

## Net events handled by the server

These are triggered by clients. They validate the sender and their input; do not
build features on them, and treat the internal ones as private protocol.

| Event | Payload | Guarding |
| --- | --- | --- |
| `kora_core:rep:resync` | none | Internal. Rate-limited by `Config.replication.resyncRateLimit`. |
| `kora_core:registry:requestSnapshot` | none | Internal. Coalesced by `Config.replication.snapshotCoalesceMs`. |
| `kora_core:server:requestCharacters` | none | Character-select protocol; lists only the sender's characters. |
| `kora_core:server:selectCharacter` | `citizenid` | Ownership checked. |
| `kora_core:server:createCharacter` | `charinfo, cid` | Validated, slot cap enforced. |
| `kora_core:server:deleteCharacter` | `citizenid` | Ownership checked; replies with a fresh list. |
| `QBCore:Server:SetMetaData` | `key, value` | Only keys in `Config.compat.clientMetadataKeys`; hunger/thirst/stress clamped. |
| `QBCore:ToggleDuty` | none | `Config.compat.toggleDutyEvent`, 2 s cooldown, not for the default job. |
| `QBCore:Server:Logout` | none | Logs the sender out. |
| `QBCore:Server:OnPlayerLoaded` | none | Only acts with `deferClientPlayerLoaded`, once per login. |
| `QBCore:UpdatePlayer` | none | 10 s cooldown; refreshes the HUD and saves. Does not decay needs. |
| `QBCore:DebugSomething` | any | 1 s cooldown; prints with `QBCore.Debug`. |
| `QBCore:Server:CloseServer` / `OpenServer` | `reason` | Admin only; other senders are kicked. |
| `QBCore:CallCommand` | `name, args` | Requires the `command.<name>` ACE; argument checks as stock. |
| `QBCore:Command:TeleportToCoords` | `x, y, z` | Echoes the teleport back to the sender only. |
| `QBCore:Server:TriggerCallback` | `name, ...` | Legacy callback wire. |
| `QBCore:Server:TriggerClientCallback` | `name, ...` | Legacy client-callback replies. |
| `QBCore:Server:UpdateObject` | none | No-op. |
| `hud:server:GainStress` / `RelieveStress` | `amount` | 1 to 100, cooldown, job whitelist, ignored while `qb-hud` runs. |
| `qb-multicharacter:server:loadUserData` | `cData` | Ownership checked via `selectCharacter`. |
| `qb-multicharacter:server:createCharacter` | `data` | Same validation as `createCharacter`. |
| `qb-multicharacter:server:deleteCharacter` | `citizenid` | Ownership checked. |
| `qb-multicharacter:server:disconnect` | `reason` | Drops the sender. |

Server-to-client protocol events `kora_core:rep:snapshot`, `kora_core:rep:delta`,
`kora_core:registry:snapshotAll`, `kora_core:client:setDevMode` and
`kora_core:client:vehicleCondition` are internal. Legacy multicharacter replies
`qb-spawn:client:setupSpawns`, `qb-spawn:client:openUI`,
`qb-multicharacter:client:closeNUIdefault` and `multichar:client:selectFailed` are
sent to the matching legacy UIs.

## State bags

| Bag | Scope | Value |
| --- | --- | --- |
| `kora_core:loggedIn` | player, replicated | `true` after the initial snapshot, `false` before logout teardown. Preferred for UI visibility. |
| `isLoggedIn` | player, replicated | Legacy mirror of the above. |
| `kora_core:money:<account>` | player, replicated | Current balance of each account. |
| `instance` | player, replicated | Routing bucket set by `setPlayerBucket`. |
| `loadInventory` | player, replicated | qbx facade only. |
| `vehicleid` | entity, server-only | `player_vehicles.id` set by `tagVehicle`. |
| `GlobalState.OnDuty` | global | On-duty counts by job name and job type. |
