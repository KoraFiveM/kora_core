---
title: "Events, callbacks and state bags"
sidebar_position: 14
---


# Events, callbacks and state bags

## Server

kora_core raises most of its server events with `TriggerEvent`, so they are server-local: any server resource can subscribe with `AddEventHandler`, and no client can trigger them because kora_core does not register them with `RegisterNetEvent`. Only six server events accept a client packet: `kora_core:server:requestCharacters`, `kora_core:server:selectCharacter`, `kora_core:server:createCharacter`, `kora_core:server:deleteCharacter`, `kora_core:rep:resync` and `kora_core:registry:requestSnapshot`. Each is marked below with who may trigger it and what the server checks. Events that exist only in `compat/` (for example `QBCore:Server:SetMetaData`, `QBCore:Server:OnPlayerLoaded`, `QBCore:CallCommand`) are documented in the Compatibility module.

Namespace: `events` · Source: `modules/*/server.lua, modules/persistence/boot.lua, init.lua (server-side events); client-sendable net events are registered in modules/multichar/server.lua, modules/replication/server.lua and modules/registry/server.lua`

### State bags written by kora_core

All writes happen on the server. Replicated means the value is sent to clients. Keys are read with `Player(src).state[key]`, `GlobalState.OnDuty` or `Entity(entity).state.vehicleid`.

| State bag key | Value and replicated flag | Writer and when |
| --- | --- | --- |
| `GlobalState.OnDuty` | Table `{ [jobNameOrJobType] = onDutyCount }`, replicated to every client (GlobalState assignment). | modules/jobs/server.lua `publish`. A whole new table is assigned (in-place edits would not replicate). Updates are coalesced with a 100 ms timer. Starts as `{}` when the module loads. |
| `Player(src).state['kora_core:loggedIn']` | Boolean, replicated (`state:set(key, value, true)`). | modules/player/server.lua. `true` after the character is adopted and the replication snapshot has been sent; `false` during logout before the unload events fire. |
| `Player(src).state['isLoggedIn']` | Boolean, replicated. Legacy alias for scripts such as qb-doorlock. | Set together with `kora_core:loggedIn` at login and logout. |
| `Player(src).state['instance']` | Integer routing bucket, replicated. | `Core.player.setPlayerBucket` (modules/player/server.lua). Not written by login or logout. |
| `Player(src).state['kora_core:money:<account>']` | Number balance, replicated. One key per entry of `Config.money.types` (default `cash`, `bank`, `crypto`). | modules/money/server.lua. Written for every account at login (`syncState`, after the snapshot) and after each add, remove, set or transfer leg. Physical cash accounts are read from the registered inventory provider, not from PlayerData. Skipped when the balance is nil. |
| `Entity(vehicle).state.vehicleid` | Integer `player_vehicles.id`, NOT replicated (`state:set('vehicleid', id, false)`). | `Core.garage.tagVehicle` in modules/garage/server.lua, called by `Core.garage.spawnVehicle` after the database row is marked `out`. Inert when convar `kora:vehicleIdStateBag` is 0 (default 1). Never cleared on despawn. |

### How it works

Local events fire inside the server action that caused them, after the change is applied, so keep handlers short. Event names come in two spellings: the modern lowercase set (`kora_core:server:playerLoaded`) and legacy-named events (`QBCore:Server:PlayerLoaded`, `QBCore:Server:OnMoneyChange`) that stock qb scripts expect. Both are raised by the native modules, not only by compat. kora_core registers no kora_lib callbacks (`Kora.callback`) outside `compat/`; the only request/response paths are the net events below, which answer with a separate client event.

### Hooking a lifecycle event from another resource

1. **Pick the right spelling** — Use `kora_core:server:playerLoaded` and `kora_core:server:playerDropped` for new code: they pass `(src, citizenid)` plain values. Use `QBCore:Server:PlayerLoaded` only when a legacy script needs the Player object.
2. **Subscribe with AddEventHandler** — Server-local events are never remotely triggerable, so no source check is needed. Read state with `exports.kora_core:getPlayer(src)` (a deep-cloned snapshot or nil).
3. **Keep handlers short** — Several listeners (jobs index, jail, dev mode) run on the same event. Move slow work into `CreateThread`.

### Terms used on this page

| Term | Meaning |
| --- | --- |
| Server-local event | Raised with `TriggerEvent` inside the server process. Subscribe with `AddEventHandler`. A client cannot send it. |
| Net event | Registered with `RegisterNetEvent`. A client sends it with `TriggerServerEvent`; the handler reads the sender from `source`. |
| Client event | Sent by the server with `TriggerClientEvent`. Listed in the client realm of this module. |
| State bag | Key/value data replicated by the engine. kora_core writes `GlobalState.OnDuty`, four `Player(src).state` keys plus one key per money account, and a non-replicated `Entity(vehicle).state.vehicleid`. |
| citizenid | The character id string generated by the identity module; one source can own many over time but only one is loaded at once. |

### Order of events at login

In `adopt` (modules/player/server.lua) the order is: external PlayerData fields hydrated, physical cash migrated, `QBCore:Server:PlayerLoaded`, `kora_core:server:playerLoaded`, `kora_core:rep:snapshot` to the client, money state bags, `kora_core:loggedIn` and `isLoggedIn` set to true, then `QBCore:Client:OnPlayerLoaded` (unless `Config.compat.deferClientPlayerLoaded` is true, in which case compat sends it later). Server listeners run before the client has its snapshot, so do not trigger client events that read the mirror from inside `kora_core:server:playerLoaded`.

### Order of events at logout and disconnect

Logout (`Core.player.logout`) saves first, then sets both logged-in bags to false, sends `QBCore:Client:OnPlayerUnload`, fires `QBCore:Server:OnPlayerUnload` and evicts the player. A disconnect (`Core.player.dropPlayer`) saves immediately, fires `QBCore:Server:PlayerDropped` then `QBCore:Server:OnPlayerUnload`, evicts, then fires `kora_core:server:playerDropped`. `kora_core:server:playerDropped` does NOT fire on a plain logout or character switch, so per-source caches must also clear on `QBCore:Server:OnPlayerUnload`. The jobs module does this.

### Security: what a client may send and what the server validates

Client-sendable events are the six listed in the overview. The server derives the player from `source`; a payload never names another player. `requestCharacters`: no validation and no rate limit; it queries the database for the sender's primary identifier. `selectCharacter`: the character is loaded and its `license` must equal the sender's primary identifier; login refuses when the source or the character is already logged in. `createCharacter`: refused when already logged in or when a creation is running for that source; name fields are trimmed, 1 to 24 characters, no control characters; birthdate must be a real non-future `YYYY-MM-DD` date; gender must be 0 or 1; nationality 2 to 32 characters; the phone number is always generated server-side; the character limit is `Config.identity.maxCharacters` or the per-license override. A client-sent `cid` slot is accepted if it is within 1 to the limit and free. `deleteCharacter`: the character must belong to the sender; an online character is logged out (saved) first, then soft-deleted. `kora_core:rep:resync`: ignored without a loaded player, and answered at most once per `Config.replication.resyncRateLimit` ms per character. `kora_core:registry:requestSnapshot`: no check and no rate limit; any connected client gets the full shared registry snapshot. All other events here have no `RegisterNetEvent` in kora_core. If another resource registers the same name as a net event, a client could send it, so do not reuse these names.

### Security: the client side trusts local callers

Client handlers for server-pushed events (`kora_core:rep:snapshot`, `kora_core:client:jailTeleport`, `kora_core:client:itemBox` and others) are registered with `RegisterNetEvent` and, with one exception, do not check `source`. A remote client cannot send a client event to another client, but any client script running on the same player can fire them locally. Only `kora_core:client:vehicleCondition` checks `source ~= 65535` and validates its numbers. Treat these events as UI and mirror updates, never as proof the server decided something. See the client realm for the full list.

### Callbacks

kora_core does not call `Kora.callback.register` or `Kora.callback.await` in its native modules (modules/, build/, init.lua). The only callback style registrations are in `compat/` (legacy `QBCore.Functions.CreateCallback`) and are documented in the Compatibility module.

### Functions

Each card shows how to subscribe or send, the payload, who can trigger it, whether the server validates it, and the file that raises it.

#### `AddEventHandler('kora_core:server:databaseReady', function() end)`

Server-local. Raised once after the schema is applied and kora_sql is ready. Any server resource can trigger it (no client can). Not validated. Raised from modules/persistence/boot.lua. It is not raised if schema setup fails.

**Parameters**



**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('kora_core:server:databaseReady', function()
    print('kora_core database is ready')
end)
```

**Representative console output**

```text
kora_core database is ready
```

#### `AddEventHandler('kora_core:server:playerLoaded', function(src, citizenid) end)`

Server-local. Raised when a character has been adopted, before the client snapshot is sent and before the logged-in state bags are set. Cannot be sent by a client. Raised from `adopt` in modules/player/server.lua. Used internally by the jobs index, jail re-apply and development mode.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `citizenid` | string | Id of the character that loaded. |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('kora_core:server:playerLoaded', function(src, citizenid)
    print(('loaded %s on %d'):format(citizenid, src))
end)
```

**Representative console output**

```text
loaded AB12CD34 on 7
```

#### `AddEventHandler('QBCore:Server:PlayerLoaded', function(player) end)`

Server-local legacy-named twin of `kora_core:server:playerLoaded`, raised just before it from `adopt` in modules/player/server.lua. Cannot be sent by a client. The payload is the stock-shaped Player object (`.PlayerData`, `.Functions`) built by the compat layer when it is loaded; otherwise it is the internal player handle.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `player` | table | Legacy Player object with `PlayerData.source` and `PlayerData.citizenid`. |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local data = player.PlayerData
    print(data.source, data.citizenid)
end)
```

**Representative console output**

```text
7 AB12CD34
```

#### `AddEventHandler('kora_core:server:playerDropped', function(src, citizenid, reason) end)`

Server-local. Raised after a disconnect has been saved and the player evicted, so `getPlayer(src)` is already nil. Not raised on logout or character switch. Cannot be sent by a client. Raised from `Core.player.dropPlayer` in modules/player/server.lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Source that left. |
| `citizenid` | string | Character that was loaded. |
| `reason` | string \| nil | Disconnect reason from the `playerDropped` event. |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('kora_core:server:playerDropped', function(src, citizenid, reason)
    sessions[src] = nil
end)
```

**Representative console output**

```text
The per-source cache entry is removed.
```

#### `AddEventHandler('QBCore:Server:PlayerDropped', function(src, reason) end)`

Server-local legacy-named drop event. Raised before eviction, so `getPlayer(src)` still works inside the handler. Server only; the client is already gone. Raised from `Core.player.dropPlayer` in modules/player/server.lua just before `QBCore:Server:OnPlayerUnload`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Source that left. |
| `reason` | string \| nil | Disconnect reason. |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('QBCore:Server:PlayerDropped', function(src, reason)
    local data = exports.kora_core:getPlayer(src)
    if data then print(data.citizenid, reason) end
end)
```

**Representative console output**

```text
AB12CD34 Exiting
```

#### `AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) end)`

Server-local. Raised on a logout (after `QBCore:Client:OnPlayerUnload` is sent, before eviction) and on a disconnect (before eviction). The reliable hook for clearing per-character caches in both cases. Cannot be sent by a client. Raised from modules/player/server.lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Source whose character unloads. |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    activeJobs[src] = nil
end)
```

**Representative console output**

```text
The per-source entry is cleared for both logout and disconnect.
```

#### `AddEventHandler('kora_voice:server:bucketChanged', function(src) end)`

Server-local. Raised after `Core.player.setPlayerBucket` changed the routing bucket and set `Player(src).state.instance`. Cannot be sent by a client. Raised from modules/player/server.lua. The new bucket is not in the payload; read `GetPlayerRoutingBucket(src)` or `Player(src).state.instance`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player whose bucket changed. |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('kora_voice:server:bucketChanged', function(src)
    print(src, Player(src).state.instance)
end)
```

**Representative console output**

```text
7 3
```

#### `AddEventHandler('QBCore:Server:OnMoneyChange', function(src, account, amount, action, reason) end)`

Server-local. Raised after every successful money add, remove, set and transfer leg (one event per player). Cannot be sent by a client. Raised from `emitMoneyChange` in modules/money/server.lua, after the `kora_core:money:<account>` state bag is updated. With a transaction tax the amount is the net after tax. For `set` the amount is the new balance for ledger accounts but the absolute difference for physical cash accounts.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `account` | string | Account name such as `cash` or `bank`. |
| `amount` | number | Amount moved (see the note on `set`). |
| `action` | string | `add`, `remove` or `set`. |
| `reason` | string \| nil | Reason passed to the money call. |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('QBCore:Server:OnMoneyChange', function(src, account, amount, action, reason)
    if account == 'bank' and action == 'remove' then print(src, amount, reason) end
end)
```

**Representative console output**

```text
7 250 shop-purchase
```

#### `AddEventHandler('kora_core:server:taxCollected', function(account, amount, reason) end)`

Server-local. Raised after the transaction tax was deposited into the banking provider. Not raised when tax is disabled, the provider is not started, or the deposit failed. Cannot be sent by a client. Raised from `Core.money.collectTax` in modules/money/server.lua (run on its own thread).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `account` | string | Banking account that received the tax (`Config.money.tax.account`). |
| `amount` | number | Tax deposited. |
| `reason` | string \| nil | Reason of the original transaction. |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('kora_core:server:taxCollected', function(account, amount, reason)
    print(('%s received %d'):format(account, amount))
end)
```

**Representative console output**

```text
government received 25
```

#### `AddEventHandler('QBCore:Server:OnMetaDataChange', function(src, key, value) end)`

Server-local. Raised after `Core.metadata.setMetaData` or `incrementMetaData` committed a metadata key (including the hunger and thirst ticks). Writes made directly with `Core.player.setPath` do not raise it. Cannot be sent by a client. Raised from modules/metadata/server.lua. The legacy client write event `QBCore:Server:SetMetaData` is compat only.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `key` | string | Metadata key. |
| `value` | any | New value (the clamped value for increments). |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('QBCore:Server:OnMetaDataChange', function(src, key, value)
    if key == 'hunger' and value <= 0 then print(src, 'is starving') end
end)
```

**Representative console output**

```text
7 is starving
```

#### `AddEventHandler('QBCore:Server:OnJobUpdate', function(src, job) end)`

Server-local. Raised after `Core.jobs.setJob` and after a duty change (`setJobDuty`), always, regardless of `Config.compat.jobUpdateEventSource`. Cannot be sent by a client. Raised from modules/jobs/server.lua. The payload is legacy-shaped: grade level is zero-based.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `job` | table | Legacy job table (`name`, `label`, `type`, `onduty`, `grade` with a zero-based `level`). |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('QBCore:Server:OnJobUpdate', function(src, job)
    print(src, job.name, job.grade.level, job.onduty)
end)
```

**Representative console output**

```text
7 police 0 true
```

#### `AddEventHandler('QBCore:Server:OnGangUpdate', function(src, gang) end)`

Server-local. Raised after `Core.jobs.setGang` committed. Cannot be sent by a client. Raised from modules/jobs/server.lua. Payload is legacy-shaped (zero-based grade level).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `gang` | table | Legacy gang table. |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('QBCore:Server:OnGangUpdate', function(src, gang)
    print(src, gang.name)
end)
```

**Representative console output**

```text
7 ballas
```

#### `AddEventHandler('QBCore:Server:OnPlayerUpdated', function(src, key, value) end)`

Server-local. Raised with `'job'` or `'gang'` right after the matching OnJobUpdate or OnGangUpdate (including duty changes). The stock qb-core event legacy scripts listen for. Cannot be sent by a client. Raised from modules/jobs/server.lua. Only job and gang keys are raised natively.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `key` | string | `job` or `gang`. |
| `value` | table | Legacy job or gang table. |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('QBCore:Server:OnPlayerUpdated', function(src, key, value)
    if key == 'job' then print(src, value.name) end
end)
```

**Representative console output**

```text
7 police
```

#### `AddEventHandler('QBCore:Server:SetDuty', function(src, onDuty) end)`

Server-local. Raised by `Core.jobs.setJobDuty` after the duty flag and the on-duty index changed. Raised only when the value was written (no event if the write failed). Cannot be sent by a client. Raised from modules/jobs/server.lua; a client copy `QBCore:Client:SetDuty` is sent as well.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `onDuty` | boolean | New duty state. |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('QBCore:Server:SetDuty', function(src, onDuty)
    print(src, onDuty and 'clocked in' or 'clocked out')
end)
```

**Representative console output**

```text
7 clocked in
```

#### `RegisterNetEvent / TriggerServerEvent('kora_core:server:requestCharacters')`

Net event, client to server. Any connected client may send it, logged in or not. Not rate limited. The server lists characters for the sender's primary identifier (and records the Discord id if `Config.identity.saveDiscord`), then replies with `kora_core:client:receiveCharacters`. Registered in modules/multichar/server.lua. The bundled client flow sends it 500 ms after start unless a UI called `exports.kora_core:claimUI()`.

**Parameters**



**Returns**

- **nil** — No return value. The answer arrives as `kora_core:client:receiveCharacters`.

**Example**

```lua
TriggerServerEvent('kora_core:server:requestCharacters')
```

**Representative console output**

```text
The client receives its character list.
```

#### `RegisterNetEvent / TriggerServerEvent('kora_core:server:selectCharacter', citizenid)`

Net event, client to server. Any connected client may send it. The server loads the character, requires its `license` to match the sender's primary identifier, and logs the player in (refused if the source or the character is already logged in). Replies with `kora_core:client:characterSelected(ok, err)`. Registered in modules/multichar/server.lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `citizenid` | string | Character to load. Must belong to the sender. |

**Returns**

- **nil** — No return value. The answer arrives as `kora_core:client:characterSelected`.

**Example**

```lua
TriggerServerEvent('kora_core:server:selectCharacter', selectedCitizenId)
```

**Representative console output**

```text
The reply is (true) on success or (false, reason), for example character does not belong to this player.
```

#### `RegisterNetEvent / TriggerServerEvent('kora_core:server:createCharacter', charinfo, cid)`

Net event, client to server. Any connected, not yet logged in client may send it. The server normalises `charinfo`, picks a free slot, inserts the character and logs the player in through `Core.player.createCharacter`. Replies with `kora_core:client:characterSelected(true)` or `(false, err)`. Registered in modules/multichar/server.lua. See the security section for the validation rules.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `charinfo` | table | `{ firstname, lastname, birthdate = 'YYYY-MM-DD', gender = 0 or 1, nationality }`. A client `phone` is ignored. |
| `cid` | integer \| nil | Requested slot. Accepted if in range and free; otherwise the next free slot is used when nil. |

**Returns**

- **nil** — No return value. The answer arrives as `kora_core:client:characterSelected`.

**Example**

```lua
TriggerServerEvent('kora_core:server:createCharacter', {
    firstname = 'Ada', lastname = 'Stone', birthdate = '1992-04-12', gender = 1, nationality = 'USA',
}, 1)
```

**Representative console output**

```text
The reply is (true) once the character exists and is loaded.
```

#### `RegisterNetEvent / TriggerServerEvent('kora_core:server:deleteCharacter', citizenid)`

Net event, client to server. Any connected client may send it. The server checks the character belongs to the sender, logs it out first if online, then soft-deletes the row. It always answers with `kora_core:client:receiveCharacters` carrying the refreshed list, whether or not the delete worked. Registered in modules/multichar/server.lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `citizenid` | string | Character to delete. Must belong to the sender. |

**Returns**

- **nil** — No return value. The answer arrives as `kora_core:client:receiveCharacters`.

**Example**

```lua
TriggerServerEvent('kora_core:server:deleteCharacter', selectedCitizenId)
```

**Representative console output**

```text
The client receives the updated list without that character.
```

#### `AddEventHandler('kora_core:registry:delta', function(name, action, key, record, epoch) end)`

Server-local. Raised after a shared registry record changed (`registerShared`, removal, resource-stop cleanup). Reaches every other server resource that loaded `@kora_core/init.lua` (its mirror applies it) and is also broadcast to all clients. No client can send it to the server: only the client mirror registers it with `RegisterNetEvent`, deliberately, so no client can inject records. Raised from `broadcast` in modules/registry/server.lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Registry name: `items`, `vehicles`, `jobs`, `gangs`, `weapons` or `locations`. |
| `action` | string | `add`, `update` or `remove`. |
| `key` | string | Record key (the registry key field). |
| `record` | table \| nil | New record; nil for `remove`. |
| `epoch` | integer | Registry epoch at the time of the change. |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('kora_core:registry:delta', function(name, action, key, record, epoch)
    if name == 'jobs' and action == 'add' then print('new job', key) end
end)
```

**Representative console output**

```text
new job courier
```

#### `RegisterNetEvent / TriggerServerEvent('kora_core:registry:requestSnapshot')`

Net event, client to server. Any connected client may send it, with no check and no rate limit. The server replies to the sender only with `kora_core:registry:snapshotAll`. Registered in modules/registry/server.lua. Sent by the client registry at start and again by the client when it sees an epoch gap.

**Parameters**



**Returns**

- **nil** — No return value. The answer arrives as `kora_core:registry:snapshotAll`.

**Example**

```lua
TriggerServerEvent('kora_core:registry:requestSnapshot')
```

**Representative console output**

```text
The client mirror is reseeded.
```

#### `RegisterNetEvent / TriggerServerEvent('kora_core:rep:resync')`

Net event, client to server. Sent by the client mirror when a delta arrives out of order or before any snapshot. The server ignores it unless the sender has a loaded character, and answers at most once per `Config.replication.resyncRateLimit` ms (default 5000) per character, silently dropping extras. The reply is a full `kora_core:rep:snapshot`. Registered in modules/replication/server.lua. `exports.kora_core:requestResync()` on the client sends it.

**Parameters**



**Returns**

- **nil** — No return value. The answer arrives as `kora_core:rep:snapshot`.

**Example**

```lua
TriggerServerEvent('kora_core:rep:resync')
```

**Representative console output**

```text
A fresh PlayerData snapshot arrives, at most every 5 seconds.
```

#### `AddEventHandler('kora_core:server:inventoryChanged', function(src, path, value) end)`

Server-local. Raised by the player write funnel (`Core.player.setPath`) after any write whose path starts with `items`. Lets inventory authorities invalidate cached views, and refreshes the physical cash mirror in the money module. Cannot be sent by a client. Raised from modules/player/server.lua. Both `path` and `value` are deep copies.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `path` | table | Written path array, for example `{ 'items', 3 }`. |
| `value` | any | New value at that path; nil when the slot was cleared. |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('kora_core:server:inventoryChanged', function(src, path, value)
    cachedViews[src] = nil
end)
```

**Representative console output**

```text
The cached view for that player is dropped.
```

#### `AddEventHandler('QBCore:Server:UseItem', function(src, item) end)`

Server-local legacy hook. `Core.inventory.useItem` raises it only when the item has no registered useable handler (it then returns false). Not raised when a handler exists. Cannot be sent by a client natively. Raised from modules/inventory/server.lua. Note that kora_inventory registers its own net event with this name; that is documented in the kora_inventory docs.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `item` | table | The item table from the player inventory (`name`, `amount`, `slot`, `info`). |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('QBCore:Server:UseItem', function(src, item)
    if item.name == 'old_radio' then print(src, 'used an unhandled old_radio') end
end)
```

**Representative console output**

```text
7 used an unhandled old_radio
```

#### `AddEventHandler('kora_core:inventory:open', function(src, request) end)`

Server-local. Raised by `Core.inventory.stashOpen` so an inventory UI resource can open the stash. kora_core ships no UI. The function returns true either way and prints a warning when `Config.inventory.warnOnUnhandledOpen` is on and the in-VM flag `_G.__qbcoreInventoryUIHandled` was not set. Cannot be sent by a client. Raised from modules/inventory/server.lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player who should see the stash. |
| `request` | table | `{ kind = 'stash', identifier, slots, maxweight }`; slots defaults to 50, maxweight to 100000. |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('kora_core:inventory:open', function(src, request)
    openStashUi(src, request.identifier, request.slots, request.maxweight)
end)
```

**Representative console output**

```text
The UI opens the stash for that player.
```

#### `AddEventHandler('kora_core:server:dispatchAlert', function(payload, recipientCount) end)`

Server-local mirror of every `Core.dispatch.alert`, fired once after the client fan-out so a dispatch or MDT resource can record one incident instead of one per recipient. Cannot be sent by a client. Raised from modules/dispatch/server.lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `payload` | table | The alert as passed: `{ jobs, title, message, coords, code, blip, sound, radius, data }`. |
| `recipientCount` | integer | On-duty players who received it. |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('kora_core:server:dispatchAlert', function(payload, recipientCount)
    saveIncident(payload.code, payload.message, recipientCount)
end)
```

**Representative console output**

```text
One incident is stored per alert.
```

#### `AddEventHandler('police:server:policeAlert', function(text) end)`

Server-local legacy-named event. Raised once by `Core.dispatch.alert` when `Config.dispatch.legacyEvents` is true and `police` is in `payload.jobs`. Cannot be sent by a client. Raised from modules/dispatch/server.lua. Ambulance and EMS have no server-local legacy event.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `text` | string | `payload.message`, else `payload.title`, else an empty string. |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('police:server:policeAlert', function(text)
    print('police alert', text)
end)
```

**Representative console output**

```text
police alert Shots fired
```

#### `AddEventHandler('kora_core:server:devModeChanged', function(src, enabled) end)`

Server-local. Raised by `Core.development.setDevMode` after the per-player development mode flag actually changed (not when set to the same value). Cannot be sent by a client. Raised from modules/development/server.lua. The needs decay loop skips players in dev mode.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `enabled` | boolean | New dev mode state. |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('kora_core:server:devModeChanged', function(src, enabled)
    print(src, enabled)
end)
```

**Representative console output**

```text
7 true
```

#### `AddEventHandler('kora_core:server:onJailRequest', function(src, minutes, reason, resourceName) end)`

Server-local. Raised by `Core.jail.jailPlayer` instead of jailing natively when a resource from `Config.jail.deferToResources` (default `xt-prison`, `qbx_prison`) is started. The external prison must do the jailing. kora_core then raises neither `playerJailed` nor its own teleport. Cannot be sent by a client. Raised from modules/jail/server.lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player to jail. |
| `minutes` | number | Sentence in minutes (positive). |
| `reason` | string \| nil | Reason text. |
| `resourceName` | string | The started prison resource that was found first. |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('kora_core:server:onJailRequest', function(src, minutes, reason, resourceName)
    print(('%s should jail %d for %d minutes'):format(resourceName, src, minutes))
end)
```

**Representative console output**

```text
xt-prison should jail 7 for 15 minutes
```

#### `AddEventHandler('kora_core:server:playerJailed', function(src, minutes, reason) end)`

Server-local. Raised after the native jail wrote `metadata.jailed` and `metadata.injail` (unix release time) and sent `kora_core:client:jailTeleport`. Not raised when jailing was deferred to an external prison. Cannot be sent by a client. Raised from `Core.jail.jailPlayer` in modules/jail/server.lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Jailed player. |
| `minutes` | number | Sentence length. |
| `reason` | string \| nil | Reason text. |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('kora_core:server:playerJailed', function(src, minutes, reason)
    print(src, minutes, reason)
end)
```

**Representative console output**

```text
7 15 Assault
```

#### `AddEventHandler('kora_core:server:playerReleased', function(src) end)`

Server-local. Raised after the native jail cleared `metadata.jailed` and `metadata.injail` and sent `kora_core:client:jailRelease`. Not raised if the player was not jailed or an external prison owns the sentence. Cannot be sent by a client. Raised from `Core.jail.release` in modules/jail/server.lua (timer, `/unjail`, or a login with an expired sentence).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Released player. |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('kora_core:server:playerReleased', function(src)
    print(src, 'released')
end)
```

**Representative console output**

```text
7 released
```

### Common use cases

- Clear per-character state on `QBCore:Server:OnPlayerUnload` so logout and disconnect are both covered.
- Record one incident per dispatch alert with `kora_core:server:dispatchAlert` instead of listening on every client.
- Mirror money in an external ledger or HUD with `QBCore:Server:OnMoneyChange` or the `kora_core:money:<account>` state bag.

### Limits and related APIs

- Local events carry no delivery guarantee across resource restarts; a resource that starts late misses earlier loads. Read current players with `exports.kora_core:getPlayers()` on start.
- `QBCore:Server:OnMetaDataChange` and the two job events are not raised by direct `Core.player.setPath` writes.
- The `kora_core:server:*` lifecycle events have no `RegisterNetEvent`; do not register them as net events in your own resource.

### Related guides

- [Player](./player.md)
- [Replication](./replication.md)
- [Registry](./registry.md)
- [Money](./money.md)
- [Jobs](./jobs.md)
- [Characters](./characters.md)
- [Compatibility](./compatibility.md)
- [Configuration](./configuration.md)

## Client

These are the events the server sends to a client, plus a few that kora_core fires locally on the client. Most are registered with `RegisterNetEvent` and do not check `source`: a remote client cannot send them to another player, but any client script on the same player can trigger them locally. Only `kora_core:client:vehicleCondition` validates `source` and its arguments. Treat every handler here as a display or mirror update, never as proof of a server decision. kora_core registers a handler itself only for the events marked "handled by kora_core"; for the others (HUD, drops, dispatch, money) it only sends, and your resource must listen. Legacy client events that exist only in `compat/` are documented in the Compatibility module.

Namespace: `events` · Source: `modules/*/client.lua, init.lua (client-side mirror)`

### How it works

Replication is sequenced: the server sends one `kora_core:rep:snapshot` at login, then numbered `kora_core:rep:delta` batches. A gap in the sequence makes the client send `kora_core:rep:resync`, which the server rate limits. The legacy-named job and gang events are fired locally from the mirror by default (`Config.compat.jobUpdateEventSource = 'client'`), or sent by the server, or both, depending on that setting.

### Reading the player on the client

1. **Wait for the snapshot** — Subscribe to `kora_core:client:playerLoaded` (local, fired with the mirror on every snapshot) or watch `LocalPlayer.state['kora_core:loggedIn']`.
2. **React to deltas** — Use `exports.kora_core:onChange(pathPrefix, handler)` on the client for path based updates instead of listening for legacy events.
3. **Never trust the payload for decisions** — Anything the client reads is a copy. Ask the server for any authoritative action.

### Terms used on this page

| Term | Meaning |
| --- | --- |
| Mirror | The client copy of PlayerData built from `kora_core:rep:snapshot` and `kora_core:rep:delta`. Legacy events are fired from it. |
| Sequence number | Per-character counter. A delta must equal the previous number plus one, otherwise a resync is requested. |
| Local event | Fired on the client with `TriggerEvent`; never sent over the network. |
| Server id 65535 | The `source` value a client sees for an event sent by the server. Only `kora_core:client:vehicleCondition` checks it. |

### Trust caveat

Client handlers registered in modules (`rep:snapshot`, `rep:delta`, `jailTeleport`, `jailRelease`, `itemBox`, `setDevMode`, `receiveCharacters`, `characterSelected`, `registry:snapshotAll`, `registry:delta`) do not check `source` or validate payload shape beyond basic type reads. A malicious script on the same client can replace its own mirror, free itself from containment or fake HUD values. None of this changes server state: money, jail, inventory and job writes are all server authoritative, and the server persists only its own copy.

### State bags readable on the client

`GlobalState.OnDuty`, `LocalPlayer.state['kora_core:loggedIn']`, `LocalPlayer.state['isLoggedIn']`, `LocalPlayer.state.instance` and `LocalPlayer.state['kora_core:money:<account>']` are replicated; `Entity(vehicle).state.vehicleid` is not. Details are in the server realm table.

### Functions

Each card shows how to subscribe, the payload, direction, who can trigger it and where it is raised.

#### `RegisterNetEvent('kora_core:rep:snapshot', function(seq, data) end)`

Client event, server to client. Sent at login and as the reply to `kora_core:rep:resync`. Replaces the whole PlayerData mirror (handled by kora_core), resets the expected sequence, fires local `kora_core:client:playerLoaded`, then the legacy job and gang events. No `source` check and no payload validation; any local script could replace the mirror. Raised from `Core.replication._sendSnapshot` in modules/replication/server.lua; handled in modules/replication/client.lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `seq` | integer | Server sequence number the next delta must follow. |
| `data` | table | Full PlayerData with real balances (physical cash overlaid). |

**Returns**

- **No return value.**

**Example**

```lua
RegisterNetEvent('kora_core:rep:snapshot', function(seq, data)
    print('snapshot', seq, data.citizenid)
end)
```

**Representative console output**

```text
snapshot 0 AB12CD34
```

#### `RegisterNetEvent('kora_core:rep:delta', function(seq, ops) end)`

Client event, server to client. A coalesced batch of PlayerData changes, sent at most once per frame per player (also for cash mirror updates). kora_core applies it in order and fires local subscribers and legacy events. If there is no mirror yet or `seq` is not the expected next number, it sends `kora_core:rep:resync` instead and ignores the batch. No `source` check. Raised from modules/replication/server.lua; handled in modules/replication/client.lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `seq` | integer | Batch number, previous plus one. |
| `ops` | table[] | Array of `{ p = pathArray, v = value }`, or `{ p = pathArray, d = true }` for a delete. |

**Returns**

- **No return value.**

**Example**

```lua
RegisterNetEvent('kora_core:rep:delta', function(seq, ops)
    for _, op in ipairs(ops) do print(table.concat(op.p, '.')) end
end)
```

**Representative console output**

```text
money.cash
```

#### `AddEventHandler('kora_core:client:playerLoaded', function(mirror) end)`

Client-local event (not a net event). Fired by the mirror on every `kora_core:rep:snapshot`, including a resync, not only at login. Raised from modules/replication/client.lua. The payload is the live mirror table, so do not mutate it.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `mirror` | table | The live PlayerData mirror. |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('kora_core:client:playerLoaded', function(mirror)
    print('loaded as', mirror.charinfo.firstname)
end)
```

**Representative console output**

```text
loaded as Ada
```

#### `RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() end)`

Client event, server to client, no payload. Sent at login right after the snapshot (and after the logged-in state bags) unless `Config.compat.deferClientPlayerLoaded` is true; then compat sends it after the client's spawn. No `source` check. Raised from `adopt` in modules/player/server.lua. kora_core registers no handler for it in the native modules.

**Parameters**



**Returns**

- **No return value.**

**Example**

```lua
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    startMyHud()
end)
```

**Representative console output**

```text
The HUD starts once the character is ready.
```

#### `RegisterNetEvent('QBCore:Client:OnPlayerUnload', function() end)`

Client event, server to client, no payload. Sent on logout after both logged-in state bags are set to false. kora_core clears its mirror and sequence on it, and the jail module removes its containment zone. No `source` check. Raised from `Core.player.logout` in modules/player/server.lua. It is not sent on a disconnect.

**Parameters**



**Returns**

- **No return value.**

**Example**

```lua
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    stopMyHud()
end)
```

**Representative console output**

```text
The HUD stops when the character logs out.
```

#### `RegisterNetEvent('QBCore:Client:OnMoneyChange', function(account, amount, action, reason) end)`

Client event, server to client. Sent after every money add, remove, set or transfer leg for that player, together with the server event of the same name. No `source` check. Raised from `emitMoneyChange` in modules/money/server.lua. kora_core registers no handler for it in the native modules. For `set` the amount follows the same rule as the server event.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `account` | string | Account name. |
| `amount` | number | Amount moved. |
| `action` | string | `add`, `remove` or `set`. |
| `reason` | string \| nil | Reason text. |

**Returns**

- **No return value.**

**Example**

```lua
RegisterNetEvent('QBCore:Client:OnMoneyChange', function(account, amount, action, reason)
    print(account, action, amount)
end)
```

**Representative console output**

```text
cash add 100
```

#### `RegisterNetEvent('hud:client:OnMoneyChange', function(account, amount, isRemove) end)`

Client event, server to client. Sent with every money change for the stock qb-hud money popup (kora_hud uses the state bag instead). No `source` check. Raised from `emitMoneyChange` in modules/money/server.lua. No native handler.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `account` | string | Account name. |
| `amount` | number | Amount moved. |
| `isRemove` | boolean | True when the action was `remove`; `add` and `set` are both false. |

**Returns**

- **No return value.**

**Example**

```lua
RegisterNetEvent('hud:client:OnMoneyChange', function(account, amount, isRemove)
    showPopup(account, isRemove and -amount or amount)
end)
```

**Representative console output**

```text
A popup shows +100 on cash.
```

#### `RegisterNetEvent('qb-phone:client:RemoveBankMoney', function(amount) end)`

Client event, server to client. Sent only when the `bank` account was reduced by a remove action (including the sender leg of a transfer). No `source` check. Raised from `emitMoneyChange` in modules/money/server.lua. No native handler.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `amount` | number | Amount removed from the bank account. |

**Returns**

- **No return value.**

**Example**

```lua
RegisterNetEvent('qb-phone:client:RemoveBankMoney', function(amount)
    addPhoneTransaction(-amount)
end)
```

**Representative console output**

```text
The phone shows a bank debit.
```

#### `RegisterNetEvent('hud:client:UpdateNeeds', function(hunger, thirst) end)`

Client event, server to client. Sent every `Config.needs.tickInterval` ms (default 60000) to each logged-in player not in dev mode, after the decay is applied, so a stock qb-hud keeps moving. No `source` check. Raised from `Core.needs._tick` in modules/needs/server.lua. Values can be nil if the metadata write failed. No native handler (the needs client reads the mirror instead).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `hunger` | number \| nil | Hunger after decay, 0 to 100. |
| `thirst` | number \| nil | Thirst after decay, 0 to 100. |

**Returns**

- **No return value.**

**Example**

```lua
RegisterNetEvent('hud:client:UpdateNeeds', function(hunger, thirst)
    setBars(hunger, thirst)
end)
```

**Representative console output**

```text
The bars show 79 and 74.
```

#### `AddEventHandler('QBCore:Client:OnJobUpdate', function(job) end)`

Legacy-named job event with two sources. By default it is fired locally on the client from the mirror when the job root changed (source is not `'server'`). When `Config.compat.jobUpdateEventSource` is `'server'` or `'both'`, the server also sends it with `TriggerClientEvent` on every job change and duty change. No `source` check. Raised from modules/replication/client.lua and modules/jobs/server.lua. Payload is legacy-shaped (zero-based grade level).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `job` | table | Legacy job table. |

**Returns**

- **No return value.**

**Example**

```lua
RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    print(job.name, job.onduty)
end)
```

**Representative console output**

```text
police true
```

#### `AddEventHandler('QBCore:Client:OnGangUpdate', function(gang) end)`

Same dual source as `QBCore:Client:OnJobUpdate`, for the gang root. Fired locally from the mirror unless `jobUpdateEventSource` is `'server'`; sent by `Core.jobs.setGang` unless it is `'client'`. Raised from modules/replication/client.lua and modules/jobs/server.lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `gang` | table | Legacy gang table. |

**Returns**

- **No return value.**

**Example**

```lua
RegisterNetEvent('QBCore:Client:OnGangUpdate', function(gang)
    print(gang.name)
end)
```

**Representative console output**

```text
ballas
```

#### `AddEventHandler('QBCore:Client:OnPlayerUpdated', function(key, value, token) end)`

Stock qb-core style event for job and gang changes. Fired locally with a third internal token argument (so compat does not fire OnJobUpdate twice), or sent by the server as `(key, value)` when `jobUpdateEventSource` is not `'client'`. Only `job` and `gang` keys are raised natively. Raised from modules/replication/client.lua and modules/jobs/server.lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `key` | string | `job` or `gang`. |
| `value` | table | Legacy job or gang table. |
| `token` | string \| nil | Internal re-fire marker, only on the locally fired copy. Ignore it. |

**Returns**

- **No return value.**

**Example**

```lua
RegisterNetEvent('QBCore:Client:OnPlayerUpdated', function(key, value)
    if key == 'job' then print(value.name) end
end)
```

**Representative console output**

```text
police
```

#### `RegisterNetEvent('QBCore:Client:SetDuty', function(onDuty) end)`

Client event, server to client. Sent by `Core.jobs.setJobDuty` to the player whose duty changed, regardless of `jobUpdateEventSource`. No `source` check. Raised from modules/jobs/server.lua. No native handler.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `onDuty` | boolean | New duty state. |

**Returns**

- **No return value.**

**Example**

```lua
RegisterNetEvent('QBCore:Client:SetDuty', function(onDuty)
    print('on duty', onDuty)
end)
```

**Representative console output**

```text
on duty true
```

#### `AddEventHandler('QBCore:Player:SetPlayerData', function(data) end)`

Client-local legacy event. Fired from the mirror (legacy-shaped PlayerData, also kept in the `QBCore.PlayerData` global) after each snapshot and delta when `Config.compat.fireLegacyPlayerDataEvent` is true. Inventory-only deltas are coalesced into one event per `Config.compat.inventoryPlayerDataEventInterval` ms (default 250; 0 fires each one). It is also registered as a net event: a foreign resource firing it overwrites the mirror, with a console warning, until the next snapshot. Raised and handled in modules/replication/client.lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `data` | table | Legacy-shaped PlayerData (zero-based grade levels). |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('QBCore:Player:SetPlayerData', function(data)
    print(data.money.cash)
end)
```

**Representative console output**

```text
500
```

#### `RegisterNetEvent('kora_core:client:itemBox', function(itemDef, action, amount) end)`

Client event, server to client. Sent after `Core.inventory.addItem` or `removeItem` changed the player inventory (not for kora_inventory writes). kora_core handles it with a `Kora.notify` toast ("Received 2x Water" or "Removed ..."). No `source` check. Raised from modules/inventory/server.lua; handled in modules/inventory/client.lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `itemDef` | table | Shared item definition (`name`, `label`, ...). |
| `action` | string | `add` or `remove`. |
| `amount` | integer | Amount added or removed. |

**Returns**

- **No return value.**

**Example**

```lua
RegisterNetEvent('kora_core:client:itemBox', function(itemDef, action, amount)
    print(action, amount, itemDef.name)
end)
```

**Representative console output**

```text
add 2 water
```

#### `RegisterNetEvent('kora_core:client:dropCreated', function(dropId, coords) end)`

Client event, server to all clients (`-1`). Sent by `Core.inventory.dropCreate` for a native ground drop. No `source` check. Raised from modules/inventory/server.lua. kora_core ships no handler or world prop, a drop UI resource must listen.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `dropId` | integer | Drop id. |
| `coords` | table | Coordinates table given to `dropCreate`. |

**Returns**

- **No return value.**

**Example**

```lua
RegisterNetEvent('kora_core:client:dropCreated', function(dropId, coords)
    drops[dropId] = coords
end)
```

**Representative console output**

```text
The drop is tracked locally.
```

#### `RegisterNetEvent('kora_core:client:dropRemoved', function(dropId) end)`

Client event, server to all clients (`-1`). Sent when a drop is emptied by `dropTake` or expires in the sweep (`Config.inventory.dropTTL`, default 30 minutes, checked every `dropSweepInterval`). No `source` check. Raised from modules/inventory/server.lua. No native handler.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `dropId` | integer | Drop id that no longer exists. |

**Returns**

- **No return value.**

**Example**

```lua
RegisterNetEvent('kora_core:client:dropRemoved', function(dropId)
    drops[dropId] = nil
end)
```

**Representative console output**

```text
The drop entry is removed.
```

#### `RegisterNetEvent('kora_core:client:dispatchAlert', function(payload) end)`

Client event, server to each on-duty player of the alerted jobs (one `TriggerClientEvent` per recipient, never `-1`, so coordinates do not leak). No `source` check. Raised from `Core.dispatch.alert` in modules/dispatch/server.lua. No native handler; the job resource renders it and consumes `blip`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `payload` | table | `{ jobs, title, message, coords, code, blip, sound, radius, data }`; fields may be nil. |

**Returns**

- **No return value.**

**Example**

```lua
RegisterNetEvent('kora_core:client:dispatchAlert', function(payload)
    print(payload.code, payload.message)
end)
```

**Representative console output**

```text
10-31 Shots fired
```

#### `RegisterNetEvent('police:client:policeAlert', function(coords, text) end)`

Legacy-named client event, server to each recipient, sent by `Core.dispatch.alert` when `Config.dispatch.legacyEvents` is true and `police` is in `payload.jobs`. No `source` check. Raised from modules/dispatch/server.lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `coords` | table \| nil | `payload.coords`. |
| `text` | string | `payload.message`, else `payload.title`, else an empty string. |

**Returns**

- **No return value.**

**Example**

```lua
RegisterNetEvent('police:client:policeAlert', function(coords, text)
    createAlertBlip(coords, text)
end)
```

**Representative console output**

```text
A blip is created at the alert location.
```

#### `RegisterNetEvent('hospital:client:ambulanceAlert', function(coords, text) end)`

Legacy-named client event, server to each recipient, sent by `Core.dispatch.alert` when `Config.dispatch.legacyEvents` is true and `ambulance` or `ems` is in `payload.jobs`. Because both job names map to it, an alert listing both sends it twice to each recipient. No `source` check. Raised from modules/dispatch/server.lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `coords` | table \| nil | `payload.coords`. |
| `text` | string | Message or title, else an empty string. |

**Returns**

- **No return value.**

**Example**

```lua
RegisterNetEvent('hospital:client:ambulanceAlert', function(coords, text)
    createAlertBlip(coords, text)
end)
```

**Representative console output**

```text
A blip is created at the alert location.
```

#### `RegisterNetEvent('kora_core:client:setDevMode', function(enabled) end)`

Client event, server to client. Turns the local development mode (walk speed override and stamina restore) on or off (handled by kora_core). Sent by `Core.development.setDevMode` when the flag changes, and again after each character load to resync. No `source` check, so a local script can switch the visual mode, but the server decides whether needs decay applies. Raised from modules/development/server.lua; handled in modules/development/client.lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `enabled` | boolean | Dev mode state; anything but `true` is treated as off. |

**Returns**

- **No return value.**

**Example**

```lua
RegisterNetEvent('kora_core:client:setDevMode', function(enabled)
    print('dev mode', enabled)
end)
```

**Representative console output**

```text
dev mode true
```

#### `AddEventHandler('kora_core:client:devModeChanged', function(active) end)`

Client-local event fired by the development module when the local mode actually flips. Not a net event and not sent by the server. Raised from modules/development/client.lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `active` | boolean | New local dev mode state. |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('kora_core:client:devModeChanged', function(active)
    print('local dev mode', active)
end)
```

**Representative console output**

```text
local dev mode true
```

#### `RegisterNetEvent('kora_core:client:jailTeleport', function(coords, remainingSeconds) end)`

Client event, server to client. Teleports the ped to the cell, creates a 30 m containment zone (leaving it teleports back) and shows a jail notification (handled by kora_core). Sent when a player is jailed and again at login while a sentence is active. No `source` check or coords validation, so a local script can fire it. Raised from modules/jail/server.lua; handled in modules/jail/client.lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `coords` | vector4 | `Config.jail.coords`. |
| `remainingSeconds` | number | Seconds left. The toast shows minutes rounded up. |

**Returns**

- **No return value.**

**Example**

```lua
RegisterNetEvent('kora_core:client:jailTeleport', function(coords, remainingSeconds)
    print(coords.x, remainingSeconds)
end)
```

**Representative console output**

```text
1651.86 900
```

#### `RegisterNetEvent('kora_core:client:jailRelease', function() end)`

Client event, server to client, no payload. Removes the containment zone and shows a release notification (handled by kora_core; also cleared on `QBCore:Client:OnPlayerUnload`). No `source` check. Raised from `Core.jail.release` in modules/jail/server.lua.

**Parameters**



**Returns**

- **No return value.**

**Example**

```lua
RegisterNetEvent('kora_core:client:jailRelease', function()
    print('released')
end)
```

**Representative console output**

```text
released
```

#### `RegisterNetEvent('kora_core:client:vehicleCondition', function(netId, fuel, engineHealth) end)`

Client event, server to the player who took the vehicle out of the garage. The only client handler that validates: it ignores the event unless `source == 65535`, and requires finite numbers with an integer `netId > 0`. It waits up to 5 s for the entity, requires a vehicle entity, gets control and applies fuel and engine health. Raised from `Core.garage.spawnVehicle` in modules/garage/server.lua; handled in modules/garage/client.lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `netId` | integer | Network id of the spawned vehicle. |
| `fuel` | number | Saved fuel level. |
| `engineHealth` | number | Saved engine health. |

**Returns**

- **No return value.**

**Example**

```lua
RegisterNetEvent('kora_core:client:vehicleCondition', function(netId, fuel, engineHealth)
    print(netId, fuel, engineHealth)
end)
```

**Representative console output**

```text
4821 87.0 950.0
```

#### `RegisterNetEvent('kora_core:client:receiveCharacters', function(characters) end)`

Client event, server to client. Reply to `requestCharacters` and `deleteCharacter`. The built-in default flow (handled by kora_core) selects slot 1 or creates a default character `John Doe`, unless a UI called `exports.kora_core:claimUI()` first or a selection is already running. No `source` check. Raised from modules/multichar/server.lua; handled in modules/multichar/client.lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `characters` | table[] | Rows `{ citizenid, cid, name, charinfo, money, job, gang }` with decoded tables. |

**Returns**

- **No return value.**

**Example**

```lua
RegisterNetEvent('kora_core:client:receiveCharacters', function(characters)
    for _, character in ipairs(characters) do print(character.cid, character.citizenid) end
end)
```

**Representative console output**

```text
1 AB12CD34
```

#### `RegisterNetEvent('kora_core:client:characterSelected', function(ok, err) end)`

Client event, server to client. Reply to `selectCharacter` and `createCharacter`. On failure the default flow (handled by kora_core) prints the error and re-arms itself. No `source` check. Raised from modules/multichar/server.lua; handled in modules/multichar/client.lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `ok` | boolean | Whether the character was loaded. |
| `err` | string \| nil | Failure reason, for example `character limit reached`. |

**Returns**

- **No return value.**

**Example**

```lua
RegisterNetEvent('kora_core:client:characterSelected', function(ok, err)
    if not ok then print('select failed', err) end
end)
```

**Representative console output**

```text
select failed character limit reached
```

#### `RegisterNetEvent('kora_core:registry:snapshotAll', function(all) end)`

Client event, server to the requesting client. Reseeds every shared registry mirror (handled by kora_core and by the mirror in `@kora_core/init.lua`), then fires local `kora_core:registry:synced`. No `source` check. Raised from the `requestSnapshot` handler in modules/registry/server.lua; handled in modules/registry/client.lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `all` | table | `{ [registryName] = { epoch, keyField, records } }`. |

**Returns**

- **No return value.**

**Example**

```lua
RegisterNetEvent('kora_core:registry:snapshotAll', function(all)
    print(#all.jobs.records)
end)
```

**Representative console output**

```text
7
```

#### `RegisterNetEvent('kora_core:registry:delta', function(name, action, key, record, epoch) end)`

Client event, server to all clients (`-1`). One shared registry record changed. The handler (modules/registry/client.lua) ignores unknown registries; on an epoch mismatch for a non-remove action it sends `kora_core:registry:requestSnapshot` instead of applying. No `source` check. Raised from `broadcast` in modules/registry/server.lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Registry name. |
| `action` | string | `add`, `update` or `remove`. |
| `key` | string | Record key. |
| `record` | table \| nil | New record; nil on remove. |
| `epoch` | integer | Registry epoch. |

**Returns**

- **No return value.**

**Example**

```lua
RegisterNetEvent('kora_core:registry:delta', function(name, action, key, record, epoch)
    print(name, action, key)
end)
```

**Representative console output**

```text
jobs add courier
```

#### `AddEventHandler('kora_core:registry:synced', function() end)`

Client-local event fired after each `kora_core:registry:snapshotAll` has been applied. Not a net event. Raised from modules/registry/client.lua. Fires again on every resync.

**Parameters**



**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('kora_core:registry:synced', function()
    print('registries ready')
end)
```

**Representative console output**

```text
registries ready
```

### Common use cases

- Read shared jobs and items on the client after `kora_core:registry:synced` without a network call per read.
- Drive a custom HUD from `kora_core:rep:delta` paths via `onChange` instead of legacy events.

### Limits and related APIs

- Client handlers do not verify the sender; use them only for display and local mirror updates.
- `kora_core:client:dropCreated`, `dropRemoved`, `dispatchAlert` and the HUD events have no handler in kora_core; if nothing listens, the event is dropped.

### Related guides

- [Replication](./replication.md)
- [Registry](./registry.md)
- [Characters](./characters.md)
- [Jail](./jail.md)
- [Compatibility](./compatibility.md)

## Callbacks reference (code-derived)

New code should use kora_lib's callbacks directly (`Kora.callback.register` and
`Kora.callback.trigger`). kora_core adds a bridge so a callback is reachable over
both the Kora transport and the legacy QBCore event wire.

### Server callbacks

```lua
-- server
exports.kora_core:createCallback('myres:getBalance', function(source, reply, account)
    reply(exports.kora_core:getMoney(source, account))
end)
```

`createCallback(name, handler)` (also `QBCore.Functions.CreateCallback`) registers
`handler(source, reply, ...)`:

- on the legacy wire: the client event `QBCore:Server:TriggerCallback` calls the
  handler and the reply is sent back with `QBCore:Client:TriggerCallback`;
- on the Kora wire: `Kora.callback.register(name, ...)`; if the handler does not
  call `reply` within `Config.compat.callbackTimeoutMs` (5000 ms by default) the
  request is answered with no values.

```lua
-- client, native
local balance = Kora.callback.trigger('myres:getBalance', 'bank')

-- client, legacy (callback form)
QBCore.Functions.TriggerCallback('myres:getBalance', function(balance) end, 'bank')

-- client, legacy (await form, must run inside a thread)
CreateThread(function()
    local balance = QBCore.Functions.TriggerCallback('myres:getBalance', 'bank')
end)
```

Client `QBCore.Functions.TriggerCallback(name, ...)` follows qb-core 1.3.0: a
function as the first argument after the name is the callback; otherwise the call
awaits and returns the reply. The await form errors when not called from a thread
and resolves `nil` after `Config.compat.callbackTimeoutMs`. Concurrent calls with
the same name are answered first in, first out, because the reply carries only the
name. A leading `nil` is forwarded and selects the await form.

Server `QBCore.Functions.TriggerCallback(name, source, cb, ...)` runs the
callback through `Kora.callback.trigger(source, name, ...)` and passes the results
to `cb`.

### Client callbacks

```lua
-- client
QBCore.Functions.CreateClientCallback('myres:getStreet', function(reply)
    local coords = GetEntityCoords(PlayerPedId())
    reply(GetStreetNameFromHashKey(GetStreetNameAtCoord(coords.x, coords.y, coords.z)))
end)

-- server
QBCore.Functions.TriggerClientCallback('myres:getStreet', source, function(street) end)
local street = QBCore.Functions.TriggerClientCallback('myres:getStreet', source) -- await form
```

`CreateClientCallback` (and the client `QBCore.Functions.CreateCallback`) registers
the handler on `QBCore:Client:TriggerClientCallback` and on the Kora client
transport, with the same timeout. `TriggerClientCallback` stores the callback or a
promise under `name .. source` and resolves it from
`QBCore:Server:TriggerClientCallback`.

### Callbacks registered by kora_core

| Name | Realm | Returns |
| --- | --- | --- |
| `QBCore:Server:SpawnVehicle` | server | Network ID or `nil`; see [Vehicle spawn](../vehicle-spawn.md). |
| `QBCore:Server:CreateVehicle` | server | Network ID or `nil`. |
| `qb-multicharacter:server:GetUserCharacters` | server (Kora wire) | All active `players` rows of the caller's license. |
| `qb-multicharacter:server:GetNumberOfCharacters` | server (Kora wire) | The caller's slot cap and an empty table. |
| `qb-multicharacter:server:setupCharacters` | server (Kora wire) | `getCharacters(source)` summaries. |
| `qb-multicharacter:server:getSkin` | server (Kora wire) | Always `nil`. |
| `qb-multicharacter:server:deleteCharacter` | server (Kora wire) | `deleteCharacter(source, citizenid)` result. |
| `qb-spawn:server:getOwnedHouses` | server (Kora wire) | Always an empty table. |

## Event listing (code-derived)

Grades in legacy (`QBCore:*`) payloads are zero-based; native kora_core payloads
use one-based grades.

### Server events to listen to

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

### Client events to listen to

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

### Net events handled by the server

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

### State bags

| Bag | Scope | Value |
| --- | --- | --- |
| `kora_core:loggedIn` | player, replicated | `true` after the initial snapshot, `false` before logout teardown. Preferred for UI visibility. |
| `isLoggedIn` | player, replicated | Legacy mirror of the above. |
| `kora_core:money:<account>` | player, replicated | Current balance of each account. |
| `instance` | player, replicated | Routing bucket set by `setPlayerBucket`. |
| `loadInventory` | player, replicated | qbx facade only. |
| `vehicleid` | entity, server-only | `player_vehicles.id` set by `tagVehicle`. |
| `GlobalState.OnDuty` | global | On-duty counts by job name and job type. |
