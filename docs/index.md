---
layout: default
title: qbcore
---

Framework core for FiveM. Owns player state, money, jobs/gangs, metadata, and a
headless inventory, all behind a **single mutation funnel** with delta
replication to clients and minimum-write persistence through
[qbsql](https://qbcore2.github.io/qbsql/). Ships full drop-in compatibility
with legacy `qb-core` — existing QBCore resources run unmodified.

Two ways to use it: the modern flat exports (`exports.qbcore:getPlayer(src)`)
for new code, or `exports['qb-core']:GetCoreObject()` for legacy resources.

## Requirements

- [qblib](https://qbcore2.github.io/qblib/)
- [qbsql](https://qbcore2.github.io/qbsql/)

## Installation

`server.cfg`, in this order:
```
set mysql_connection_string "mysql://user:pass@localhost/qbcore?charset=utf8mb4"
ensure qbsql
ensure qblib
ensure qbcore
```
qbcore creates its own tables on first boot via qbsql's migration runner — no
manual schema import needed.

## Usage examples

### Activate development mode for one player
```lua
-- server; permission-gate this in the calling resource
exports.qbcore:setDevMode(source, true)
```
This grants ped invincibility, pauses that player's passive hunger/thirst, and
applies the configured fast walk rate until disabled or disconnected.

### Give a player money and an item
```lua
-- server
RegisterCommand('startingkit', function(source)
    exports.qbcore:addMoney(source, 'cash', 500, 'starting-kit')
    exports.qbcore:addItem(source, 'water_bottle', 2)
end)
```

### Read live player data on the client (zero network cost)
```lua
-- client
local job = exports.qbcore:getPlayerData('job')
print(('You are a %s (grade %d)'):format(job.label, job.grade.level))

exports.qbcore:onPlayerDataChange('job', function(path, value)
    print('Job changed:', value.label)
end)
```

### Subscribe to a player change server-side
```lua
-- server
exports.qbcore:onChange({'money', 'bank'}, function(src, path, value, previous)
    print(('player %d bank: %d -> %d'):format(src, previous, value))
end)
```

### Set a job and check it
```lua
-- server
exports.qbcore:setJob(source, 'police', 2)
local onDuty = exports.qbcore:getPlayersByJob('police', true)
print(#onDuty, 'police officers on duty')
```

### Custom useable item
```lua
-- server
exports.qbcore:createUseable('water_bottle', function(src, item)
    exports.qbcore:removeItem(src, 'water_bottle', 1, item.slot)
    -- restore thirst, play anim, etc.
end)
```

### Shared registry, live across resources
```lua
-- any resource, after `shared_script '@qbcore/init.lua'`
QB.shared.register('items', 'lockpick', { label = 'Lockpick', weight = 100 })

QB.shared.onChange('items', function(action, key, record, previous)
    print(action, key) -- fires in EVERY resource using the registry, including this one
end)
```

### Legacy qb-core compat, unmodified
```lua
local QBCore = exports['qb-core']:GetCoreObject()
local Player = QBCore.Functions.GetPlayer(source)
Player.Functions.AddMoney('cash', 500, 'reason')
Player.Functions.SetJob('police', 2)
Player.Functions.AddItem('water_bottle', 1)
```

## API reference

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
exports.qbcore:addMoney(src, account, amount, reason, ignoreTax)  -- true | false, err
exports.qbcore:removeMoney(src, account, amount, reason, ignoreTax)
exports.qbcore:setMoney(src, account, amount, reason)             -- never taxed
exports.qbcore:getMoney(src, account)
exports.qbcore:transferMoney(fromSrc, toSrc, account, amount, reason, ignoreTax)
```
Accounts: `cash`, `bank`, `crypto` (`Config.money.types`). `bank` may go negative
to `Config.money.minusLimit`.

**Transaction tax** (`Config.money.tax`, off by default) diverts a percentage of
each transaction into a banking account — `government` on `qb-banking` by
default. The tax is carved *out* of the amount rather than added on top, so a
`removeMoney(src, 'bank', 100)` still costs the player exactly 100 and no
existing shop or job resource needs re-auditing. Pass `ignoreTax = true` for
movements that are not economic activity (refunds, admin grants, a player's own
ATM deposit). A banking outage lets the transaction through untaxed rather than
failing it.

```lua
exports.qbcore:calculateTax(price, 'bank', 'remove')  -- for a tax-inclusive UI
exports.qbcore:collectTax(500, 'court fine')          -- an off-path levy; yields
```

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
shipped — [qbinventory](https://qbcore2.github.io/qbinventory/) is the headless
inventory authority; its optional companion resource owns any UI.

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
`shared_script '@qbcore/init.lua'` (after `@qblib/init.lua`) and use `QB.shared.*`
as shown above. A registration in ANY resource fires every subscriber's
`onChange` in every resource that uses the list. Always use `get` for one
record and call `all` when each UI/admin list is built; never cache or index the
legacy `QBCore.Shared.Jobs`/`Items` maps in new code.

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
RandomStr/RandomInt`, `QBCore.Commands.Add`, `QBCore.Debug`. All
`Player.Functions.*` methods route through the same funnel as the modern API.
Legacy net events fire both directions (`QBCore:Server:PlayerLoaded`,
`QBCore:Client:OnPlayerLoaded`, `QBCore:Player:SetPlayerData`,
`QBCore:Server:OnJobUpdate`, `QBCore:Notify`, ...).

The compat surface targets **full parity with upstream qbcore-framework/qb-core**
(both the classic and current-main eras). Besides `GetCoreObject`, every
`QBCore.Functions.*` is ALSO exposed as a direct export in each realm, exactly
as upstream does:
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

Current upstream behavior also includes the complete `QBCore.Config` shape,
`PlayersByCitizenId`, phone/account generators, runtime player method/field
extensions, and full offline player lookup/create/check/save objects. The
legacy draw-text events (`qb-core:client:drawText`, `changeText`, and
`hideText`) forward to qblib's text UI.

For client UI visibility, prefer the server-owned replicated player state bag
`LocalPlayer.state['qbcore:loggedIn']` and `AddStateBagChangeHandler` over
legacy load/unload events. A bare `LocalPlayer.state['isLoggedIn']` is set
alongside it as a legacy mirror (real qb-core uses that unnamespaced key, and
untouchable consumers such as real qb-doorlock read it directly) — new code
should use the namespaced key.

### Known compat caveats
- A `Player` object returned to ANOTHER resource carries a `PlayerData` SNAPSHOT
  frozen at call time. The function refs stay live; for fresh data call
  `Player.Functions.GetPlayerData()`.
- `SetPlayerData(key, value)` to a root key with no DB column mapping is refused
  with a warning rather than silently not persisting.
- `QBCore.Functions.ExecuteSql` is deprecated (its `wait` arg is ignored) —
  forwarded to `QB.sql.query`, warned once per calling resource.
- `QBCore.Shared.Items/Jobs/...` are legacy-only live views. Writing them
  bypasses the registry, so subscribers won't fire. New code uses
  `getShared`/`allShared` and `registerShared` instead.
- `QBCore.Commands.List` reflects commands registered THROUGH the compat
  (`QBCore.Commands.Add`) or present at the last `Refresh`.
- Client `QBCore.Functions.Progressbar` translates legacy `prop`/`propTwo`
  descriptors into qblib's networked progress props. `IsWearingGloves` returns
  `true` for unknown arm indices.

## Character selection

No NUI ships. A bare server auto-selects character slot 1 (creating a default
character if none exist). A character-select UI calls `exports.qbcore:claimUI()`
and drives `exports.qbcore:getCharacters/selectCharacter/deleteCharacter` (or the
`qbcore:server:*` / legacy `qb-multicharacter:*` events) — see
[qbmultichar](https://qbcore2.github.io/qbmultichar/) for a ready-made UI.

## Config highlights (`config.lua`)

`Config.persistence.interval` (60s save window), `Config.money.types/default`,
`Config.money.tax` (transaction tax into a government banking account; off by
default), `Config.inventory.maxWeight/slots`,
`Config.compat.fireLegacyPlayerDataEvent` (default true),
`Config.persistence.generatedColumns` (opt into SQL-queryable cash/bank/job
virtual columns).

## Related resources

Part of the [qbcore2](https://github.com/qbcore2) resource set:

- [qblib](https://qbcore2.github.io/qblib/) — shared helper library
- [qbsql](https://qbcore2.github.io/qbsql/) — database driver
- [qbinventory](https://qbcore2.github.io/qbinventory/) — headless inventory
- [qbtarget](https://qbcore2.github.io/qbtarget/) — targeting/interaction
- [qbclothing](https://qbcore2.github.io/qbclothing/) — clothing/wardrobe
- [qbadmin](https://qbcore2.github.io/qbadmin/) — admin menu
- [full resource list ↗](https://github.com/orgs/qbcore2/repositories)
