# qbcore API reference

Two ways to use qbcore: the modern flat exports (`exports.qbcore:getPlayer(src)`)
for new code, and the legacy `exports['qb-core']:GetCoreObject()` object for
existing QBCore resources (works unmodified).

## Setup

`server.cfg`, in order:
```
set mysql_connection_string "mysql://user:pass@localhost/qbcore?charset=utf8mb4"
ensure qbsql
ensure qblib
ensure qbcore
```
qbcore creates its own tables on first boot via qbsql's migration runner.

## Modern API (`exports.qbcore:*`)

All server-side unless noted. Fallible functions return `(value, errorString)`.

### Players
```lua
exports.qbcore:getPlayer(src)                 -- deep-cloned PlayerData snapshot
exports.qbcore:getPlayerByCitizenId(cid)
exports.qbcore:getPlayerData(src, path)       -- a sub-path, or the whole blob
exports.qbcore:getPlayers()                   -- array of sources
exports.qbcore:getAllPlayers()                -- array of snapshots
exports.qbcore:setPath(src, path, value)      -- THE funnel (path is a key array)
exports.qbcore:onChange(pathPrefix, handler)  -- server-side subscription -> id
exports.qbcore:offChange(id)                  -- tear down a server-side subscription
```
Client-side (over the replicated mirror):
```lua
exports.qbcore:getPlayerData(path)            -- live local mirror, zero network cost
exports.qbcore:onPlayerDataChange(prefix, handler)   -- handler(path, value)
exports.qbcore:offPlayerDataChange(id)
```

### Money
```lua
exports.qbcore:addMoney(src, account, amount, reason)     -- true | false, err
exports.qbcore:removeMoney(src, account, amount, reason)
exports.qbcore:setMoney(src, account, amount, reason)
exports.qbcore:getMoney(src, account)
exports.qbcore:transferMoney(fromSrc, toSrc, account, amount, reason)
```
Accounts: `cash`, `bank`, `crypto` (Config.money.types). `bank` may go negative
to `Config.money.minusLimit`.

### Jobs / gangs
```lua
exports.qbcore:setJob(src, name, grade)
exports.qbcore:setGang(src, name, grade)
exports.qbcore:setJobDuty(src, onDuty)
exports.qbcore:getJob(src)  exports.qbcore:getGang(src)
exports.qbcore:getPlayersByJob(name, onDutyOnly)   -- O(1), maintained index
exports.qbcore:getDutyCount(name)
```

### Metadata
```lua
exports.qbcore:getMetaData(src, key)
exports.qbcore:setMetaData(src, key, value)
exports.qbcore:incrementMetaData(src, key, delta, min, max)
```

### Inventory
```lua
exports.qbcore:addItem(src, name, amount, slot, info)     -- true | false, err
exports.qbcore:removeItem(src, name, amount, slot)
exports.qbcore:getItemByName(src, name)
exports.qbcore:getItemBySlot(src, slot)
exports.qbcore:getItemCount(src, name)
exports.qbcore:hasItem(src, nameOrList, amount)
exports.qbcore:canCarry(src, name, amount)
exports.qbcore:getWeight(src)                             -- weight, maxWeight
exports.qbcore:clearInventory(src, keep)
exports.qbcore:createUseable(name, handler)               -- handler(src, item)
exports.qbcore:useItem(src, slotOrName)
exports.qbcore:stashGet(id)  exports.qbcore:stashSet(id, items)  exports.qbcore:stashOpen(src, id, opts)
```
Items are slot-keyed (`items[slot] = {slot, name, amount, info, ...}`). No NUI is
shipped. qbinventory is the headless inventory authority and separately owns the
`qb-inventory` compatibility identity; its optional companion resource owns any UI.

### Shared registries (items/vehicles/jobs/gangs/weapons/locations)
```lua
exports.qbcore:getShared(name, key)          -- one record
exports.qbcore:allShared(name)               -- the dense array
exports.qbcore:registerShared(name, key, record)   -- server-authoritative
exports.qbcore:unregisterShared(name, key)
exports.qbcore:onSharedChange(name, handler) -- handler(action, key, record, previous) -> id
exports.qbcore:offSharedChange(name, id)     -- tear down a shared-registry subscription
```

Prefer the LIVE MIRROR in a consumer resource — add
`shared_script '@qbcore/init.lua'` (after `@qblib/init.lua`) and use:
```lua
QB.shared.get(name, key)      -- local hash lookup, zero boundary crossing
QB.shared.all(name)
QB.shared.register(name, key, record)
QB.shared.onChange(name, function(action, key, record, previous) ... end)
```
A registration in ANY resource fires every subscriber's `onChange` in every
resource that uses the list — the `/ideas` requirement.

### Identity / permissions / commands / logging
```lua
exports.qbcore:getIdentifiers(src)   exports.qbcore:generateCitizenId()
exports.qbcore:hasPermission(src, perm)   exports.qbcore:getPermission(src)
exports.qbcore:addCommand(name, help, args, argsRequired, handler, permission)
exports.qbcore:logEvent(category, src, data)
```

## Legacy QBCore compat

`local QBCore = exports['qb-core']:GetCoreObject()` returns the full legacy
object: `QBCore.Functions.*`, `QBCore.Player.*`, `QBCore.Players`,
`QBCore.Shared.Items/Vehicles/Jobs/Gangs/Weapons` + `Round/Trim/SplitStr/
RandomStr/RandomInt`, `QBCore.Commands.Add`, `QBCore.Debug`. Per-player:
```lua
local Player = QBCore.Functions.GetPlayer(src)
Player.Functions.AddMoney('cash', 500, 'reason')
Player.Functions.SetJob('police', 2)
Player.Functions.AddItem('water_bottle', 1)
```
All `Player.Functions.*` methods route through the same funnel as the modern
API. Legacy net events fire both directions (`QBCore:Server:PlayerLoaded`,
`QBCore:Client:OnPlayerLoaded`, `QBCore:Player:SetPlayerData`,
`QBCore:Server:OnJobUpdate`, `QBCore:Notify`, ...).

The compat surface targets **full parity with upstream qbcore-framework/qb-core**
(both the classic and current-main eras — the player object is the union of
both). Besides `GetCoreObject`, every `QBCore.Functions.*` is ALSO exposed as a
direct export in each realm, exactly as upstream does:
```lua
exports['qb-core']:GetPlayer(src)          -- server
exports['qb-core']:AddItem('burger', {...}) -- server: registry mutators (AddItem/AddJob/AddGang/...)
exports['qb-core']:GetShared('Items', 'water_bottle')
exports['qb-core']:SpawnVehicle(model)     -- client
```
Server helpers present: identity/player lookups (`GetPlayerBy*`), job/duty
(`GetPlayersByJob/OnDuty/GetDutyCount`), routing buckets
(`SetPlayerBucket`/`GetPlayersInBucket`/...), server vehicle spawn
(`SpawnVehicle`/`CreateVehicle`/`CreateAutomobile`), permissions
(`AddPermission`/`RemovePermission`/`HasPermission`/...), `IsWhitelisted`,
`IsPlayerBanned`, `TriggerClientCallback`, `GetCoreVersion`, `ExploitBan`,
`SetMethod`/`SetField`. Client helpers present: the full vehicle-property /
world / drawing / anim-and-particle set (`GetVehicleProperties`,
`SetVehicleProperties`, `GetClosest*`, `DrawText3D`, `StartParticle*`, ...).

For client UI visibility, prefer the server-owned replicated player state bag
`LocalPlayer.state['qbcore:loggedIn']` and `AddStateBagChangeHandler` over
legacy load/unload events. qbcore sets it true only after the initial PlayerData
snapshot and clears it before logout teardown; legacy lifecycle events remain
for compatibility. A bare `LocalPlayer.state['isLoggedIn']` is mirrored
alongside it for legacy consumers — real qb-core uses that unnamespaced key and
untouchable scripts (real qb-doorlock's client loop) read it directly. New code
should use the namespaced key.

### Known compat caveats
- A `Player` object returned to ANOTHER resource carries a `PlayerData` SNAPSHOT
  frozen at call time (it crossed the export boundary as a copy). The function
  refs stay live; for fresh data call `Player.Functions.GetPlayerData()`. (Legacy
  qb-core has the same footgun.)
- `SetPlayerData(key, value)` to a root key with no DB column mapping is refused
  with a warning rather than silently not persisting.
- `QBCore.Functions.ExecuteSql` is deprecated (its `wait` arg is ignored) —
  forwarded to `QB.sql.query`, warned once per calling resource.
- Writing `QBCore.Shared.Items['x'] = {...}` directly bypasses the registry, so
  subscribers won't fire. Use `exports['qb-core']:AddItem(name, item)` (or
  `QBCore.Functions.AddItem`) instead — it routes through the registry, so the
  item materialises, replicates to clients, and fires subscribers.
- `QBCore.Commands.List` is a table keyed by command name (matching upstream), but
  it reflects commands registered THROUGH the compat (`QBCore.Commands.Add`) or
  present at the last `Refresh`; commands added by another resource straight
  through `QB.commands` appear only after the next `Add`/`Refresh`.
- `QBCore.Player.CreatePlayer(PlayerData, Offline)` (the raw-blob form) is not
  supported — create characters via the multichar events /
  `exports.qbcore:createCharacter`. It refuses loudly rather than corrupting state.
- `QBCore:UpdatePlayer` does NOT decrement hunger/thirst here (the `needs` module
  owns decay on its own timer); the handler refreshes the stock HUD and persists,
  so a stock qb-hud keeps working without double-ticking.
- Client `QBCore.Functions.Progressbar` accepts `prop`/`propTwo` for signature
  parity but qblib's progressbar renders no props; `IsWearingGloves` returns
  `true` for unknown arm indices (our `QBCore.Shared` seeds no NoGloves tables).

## Character selection
No NUI ships. A bare server auto-selects character slot 1 (creating a default
character if none exist). A character-select UI calls
`exports.qbcore:claimUI()` and drives
`exports.qbcore:getCharacters/selectCharacter/deleteCharacter` (or the
`qbcore:server:*` / legacy `qb-multicharacter:*` events).

The character-slot cap is `Config.identity.maxCharacters` by default, but a
`users` row can override it per license (`exports.qbcore:setMaxCharacters`) --
see `modules/users/docs.md`. `Core.player.createCharacter` enforces the cap
and assigns the slot itself; a client-supplied `cid` is only honoured if it's
free and in bounds, never trusted to gate the limit.

## Config highlights (`config.lua`)
`Config.persistence.interval` (60s save window), `Config.money.types/default`,
`Config.inventory.maxWeight/slots`, `Config.compat.fireLegacyPlayerDataEvent`
(default true), `Config.persistence.generatedColumns` (opt into SQL-queryable
cash/bank/job virtual columns).
