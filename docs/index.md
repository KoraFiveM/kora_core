---
layout: default
title: kora_core
---

Framework core for FiveM. Owns player state, money, jobs/gangs, metadata, and a
headless inventory, all behind a **single mutation funnel** with delta
replication to clients and minimum-write persistence through
[kora_sql](https://qbcore2.github.io/kora_sql/). Ships full drop-in compatibility
with legacy `qb-core` — existing QBCore resources run unmodified.

Two ways to use it: the modern flat exports (`exports.kora_core:getPlayer(src)`)
for new code, or `exports['qb-core']:GetCoreObject()` for legacy resources.

## Requirements

- [kora_lib](https://qbcore2.github.io/kora_lib/)
- [kora_sql](https://qbcore2.github.io/kora_sql/)

## Installation

`server.cfg`, in this order:
```
set mysql_connection_string "mysql://user:pass@localhost/kora_core?charset=utf8mb4"
ensure kora_sql
ensure kora_lib
ensure kora_core
```
kora_core creates its own tables on first boot from the declarative schema in `modules/persistence/schema.lua` (kora_sql `ensureTables`, additive only) — no
manual schema import needed.

## Usage examples

### Activate development mode for one player
```lua
-- server; permission-gate this in the calling resource
exports.kora_core:setDevMode(source, true)
```
This grants ped invincibility, pauses that player's passive hunger/thirst, and
applies the configured fast walk rate until disabled or disconnected.

### Give a player money and an item
```lua
-- server
RegisterCommand('startingkit', function(source)
    exports.kora_core:addMoney(source, 'cash', 500, 'starting-kit')
    exports.kora_core:addItem(source, 'water_bottle', 2)
end)
```

### Read live player data on the client (zero network cost)
```lua
-- client
local job = exports.kora_core:getPlayerData('job')
print(('You are a %s (grade %d)'):format(job.label, job.grade.level))

exports.kora_core:onPlayerDataChange('job', function(path, value)
    print('Job changed:', value.label)
end)
```

### Commit money and inventory changes together
```lua
local ok, err = exports.kora_core:transaction(source, {
    reason = 'shop purchase',
    coords = vector3(1, 2, 3), -- metadata only; no distance check
    money = {
        remove = { { account = 'cash', amount = 500 } },
        add = { { account = 'bank', amount = 500 } }
    },
    items = {
        remove = { { item = 'water_bottle', amount = 1 } },
        add = { { item = 'sandwich', amount = 2, info = {} } }
    }
})
if not ok then print(('transaction rejected: %s'):format(err)) end
```

The transaction checks all balances, item quantities, and carry capacity before
mutating. It then removes money/items and adds items/money. If a later operation
fails, it attempts to compensate completed operations. Amounts must be positive
whole numbers. Callers must perform authorization, price, ownership, permission,
and distance checks; never pass an untrusted client-defined transaction. This is
compensating rollback, not crash-proof atomicity, and concurrent calls can race.

### Subscribe to a player change server-side
```lua
-- server
exports.kora_core:onChange({'money', 'bank'}, function(src, path, value, previous)
    print(('player %d bank: %d -> %d'):format(src, previous, value))
end)
```

### Set a job and check it
```lua
-- server
exports.kora_core:setJob(source, 'police', 2)
local onDuty = exports.kora_core:getPlayersByJob('police', true)
print(#onDuty, 'police officers on duty')
```

### Custom useable item
```lua
-- server
exports.kora_core:createUseable('water_bottle', function(src, item)
    exports.kora_core:removeItem(src, 'water_bottle', 1, item.slot)
    -- restore thirst, play anim, etc.
end)
```

### Shared registry, live across resources
```lua
-- any resource, after `shared_script '@kora_core/init.lua'`
Kora.shared.register('items', 'lockpick', { label = 'Lockpick', weight = 100 })

Kora.shared.onChange('items', function(action, key, record, previous)
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
exports.kora_core:getPlayer(src)                 -- deep-cloned PlayerData snapshot
exports.kora_core:getPlayerByCitizenId(cid)
exports.kora_core:getPlayerData(src, path)       -- a sub-path, or the whole blob
exports.kora_core:getPlayers()                   -- array of sources
exports.kora_core:getAllPlayers()                -- array of snapshots
exports.kora_core:setPath(src, path, value)      -- THE funnel (path is a key array)
exports.kora_core:onChange(pathPrefix, handler)  -- server-side subscription -> id
exports.kora_core:offChange(id)                  -- tear down a server-side subscription
```
Client-side (over the replicated mirror):
```lua
exports.kora_core:getPlayerData(path)            -- live local mirror, zero network cost
exports.kora_core:onPlayerDataChange(prefix, handler)   -- handler(path, value)
exports.kora_core:offPlayerDataChange(id)
```

### Money
```lua
exports.kora_core:addMoney(src, account, amount, reason, ignoreTax)  -- true | false, err
exports.kora_core:removeMoney(src, account, amount, reason, ignoreTax)
exports.kora_core:setMoney(src, account, amount, reason)             -- never taxed
exports.kora_core:getMoney(src, account)
exports.kora_core:transferMoney(fromSrc, toSrc, account, amount, reason, ignoreTax)
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
exports.kora_core:calculateTax(price, 'bank', 'remove')  -- for a tax-inclusive UI
exports.kora_core:collectTax(500, 'court fine')          -- an off-path levy; yields
```

### Transactions
```lua
exports.kora_core:transaction(src, definition) -- true | false, errorString
```

`definition` supports `money.remove`, `money.add`, `items.remove`, and
`items.add`. Item entries use `item`, `amount`, optional `slot`/`info`; money
entries use `account` and `amount`. `reason` and `coords` are optional metadata.

An optional `random` list rolls bonus items independently by their percentage
`chance`. Entries without a chance split 100% equally among themselves. Random
amounts default to `1` and support positive integer `{ min, max }` ranges.
An all-miss roll still permits the normal payout; winning bonuses participate
in the existing capacity checks and rollback. Missing or empty lists do nothing.

### Jobs / gangs
```lua
exports.kora_core:setJob(src, name, grade)
exports.kora_core:setGang(src, name, grade)
exports.kora_core:setJobDuty(src, onDuty)
exports.kora_core:getJob(src)  exports.kora_core:getGang(src)
exports.kora_core:getPlayersByJob(name, onDutyOnly)   -- O(1), maintained index
exports.kora_core:getDutyCount(name)
```

### Metadata
```lua
exports.kora_core:getMetaData(src, key)
exports.kora_core:setMetaData(src, key, value)
exports.kora_core:incrementMetaData(src, key, delta, min, max)
```

### Inventory
```lua
exports.kora_core:addItem(src, name, amount, slot, info)     -- true | false, err
exports.kora_core:removeItem(src, name, amount, slot)
exports.kora_core:getItemByName(src, name)
exports.kora_core:getItemBySlot(src, slot)
exports.kora_core:getItemCount(src, name)
exports.kora_core:hasItem(src, nameOrList, amount)
exports.kora_core:canCarry(src, name, amount)
exports.kora_core:getWeight(src)                             -- weight, maxWeight
exports.kora_core:clearInventory(src, keep)
exports.kora_core:createUseable(name, handler)               -- handler(src, item)
exports.kora_core:useItem(src, slotOrName)
exports.kora_core:stashGet(id)  exports.kora_core:stashSet(id, items)  exports.kora_core:stashOpen(src, id, opts)
```
Items are slot-keyed (`items[slot] = {slot, name, amount, info, ...}`). No NUI is
shipped — [kora_inventory](https://qbcore2.github.io/kora_inventory/) is the headless
inventory authority; its optional companion resource owns any UI.

### Shared registries (items/vehicles/jobs/gangs/weapons/locations)
```lua
exports.kora_core:getShared(name, key)          -- one record
exports.kora_core:allShared(name)               -- the dense array
exports.kora_core:registerShared(name, key, record)   -- server-authoritative
exports.kora_core:unregisterShared(name, key)
exports.kora_core:onSharedChange(name, handler) -- handler(action, key, record, previous) -> id
exports.kora_core:offSharedChange(name, id)     -- tear down a shared-registry subscription
```
Prefer the LIVE MIRROR in a consumer resource — add
`shared_script '@kora_core/init.lua'` (after `@kora_lib/init.lua`) and use `Kora.shared.*`
as shown above. A registration in ANY resource fires every subscriber's
`onChange` in every resource that uses the list. Always use `get` for one
record and call `all` when each UI/admin list is built; never cache or index the
legacy `QBCore.Shared.Jobs`/`Items` maps in new code.

### Identity / permissions / commands / logging
```lua
exports.kora_core:getIdentifiers(src)   exports.kora_core:generateCitizenId()
exports.kora_core:hasPermission(src, perm)   exports.kora_core:getPermission(src)
exports.kora_core:addCommand(name, help, args, argsRequired, handler, permission)
exports.kora_core:logEvent(category, src, data)
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
Vehicle RGB snapshots are persisted as JSON-stable `{ r, g, b }` objects; the
setter also accepts arrays and legacy JSON objects with numeric string keys.

Current upstream behavior also includes the complete `QBCore.Config` shape,
`PlayersByCitizenId`, phone/account generators, runtime player method/field
extensions, and full offline player lookup/create/check/save objects. The
legacy draw-text events (`qb-core:client:drawText`, `changeText`, and
`hideText`) forward to kora_lib's text UI.

For client UI visibility, prefer the server-owned replicated player state bag
`LocalPlayer.state['kora_core:loggedIn']` and `AddStateBagChangeHandler` over
legacy load/unload events. A bare `LocalPlayer.state['isLoggedIn']` is set
alongside it as a legacy mirror (real qb-core uses that unnamespaced key, and
untouchable consumers such as real qb-doorlock read it directly) — new code
should use the namespaced key.

Domain resources can add client-visible, replicated-only PlayerData roots with
`registerPlayerDataField(key, provider)` and update them through
`setPlayerDataField(source, key, value)`. Providers run before the initial
snapshot. These fields are resource-owned read models, are not saved by kora_core,
and must never be trusted for server authorization.

### Known compat caveats
- A `Player` object returned to ANOTHER resource carries a `PlayerData` SNAPSHOT
  frozen at call time. The function refs stay live; for fresh data call
  `Player.Functions.GetPlayerData()`.
- `SetPlayerData(key, value)` to a root key with no DB column mapping is refused
  with a warning rather than silently not persisting.
- `QBCore.Functions.ExecuteSql` is deprecated (its `wait` arg is ignored) —
  forwarded to `Kora.sql.query`, warned once per calling resource.
- `QBCore.Shared.Items/Jobs/...` are legacy-only live views. Writing them
  bypasses the registry, so subscribers won't fire. New code uses
  `getShared`/`allShared` and `registerShared` instead.
- The 20 stock qb-core commands (`/setjob`, `/givemoney`, `/car`, `/tp`, ...) are
  registered by default; see [default-commands.md](default-commands.md) and
  `Config.compat.defaultCommands`. `QBCore.Commands.Add` also fires
  `QBCore:Server:PreCommandExecution`.
- With `kora_inventory` cash-as-item on, `PlayerData.money.cash` (server compat
  view and the replicated client PlayerData) MIRRORS the real cash item balance
  and is refreshed whenever the cash stack changes (Core.money paths and
  `kora_core:server:inventoryChanged`; no polling). The persisted ledger stays 0.
  A `SetPlayerData('money', { cash = x })` write-back means "cash becomes x" and
  applies the delta against the mirrored balance the script saw (not a live item
  query), so a stack that moved after the read still receives the intended change;
  the live balance only gates insufficient funds.
- `PlayerData.metadata` in the compat view is filled with the stock
  `CheckPlayerData` defaults (`criminalrecord`, `phonedata`, `inside`, `rep`,
  `callsign`, `licences.business`, ...) without overwriting stored values;
  nothing is persisted by this. `job.grade.payment`/`isboss` and
  `gang.grade.isboss` are present, and `SetJob`/`SetGang` lower-case the name.
- Client `QBCore.Functions.TriggerCallback(name, ...)` follows qb-core 1.3.0:
  a function as the first argument after the name is the callback; without one
  the call awaits and returns the reply. The await form must run in a thread
  (it errors otherwise), resolves `nil` after `Config.compat.callbackTimeoutMs`
  with no reply, and concurrent same-name calls are answered first-in-first-out
  (the reply wire carries only the name). As in stock, a leading `nil` is
  forwarded and selects the await form.
- `QBCore.Commands.List` reflects commands registered THROUGH the compat
  (`QBCore.Commands.Add`) or present at the last `Refresh`.
- Client `QBCore.Functions.Progressbar` translates legacy `prop`/`propTwo`
  descriptors into kora_lib's networked progress props. `IsWearingGloves` returns
  `true` for unknown arm indices.

## Character selection

No NUI ships. A bare server auto-selects character slot 1 (creating a default
character if none exist). A character-select UI calls `exports.kora_core:claimUI()`
and drives `exports.kora_core:getCharacters/selectCharacter/deleteCharacter` (or the
`kora_core:server:*` / legacy `qb-multicharacter:*` events) — see
[kora_multichar](https://qbcore2.github.io/kora_multichar/) for a ready-made UI.

## Config highlights (`config.lua`)

`Config.persistence.interval` (60s save window), `Config.money.types/default`,
`Config.money.tax` (transaction tax into a government banking account; off by
default), `Config.inventory.maxWeight/slots`,
`Config.compat.fireLegacyPlayerDataEvent` (default true),
`Config.compat.defaultCommands` (default true; the stock qb-core command set),
`Config.persistence.generatedColumns` (opt into SQL-queryable cash/bank/job
virtual columns).

`Config.vehicleAirControl` (client; `disable` default true, `exemptClasses`
default `{ 8, 13, 14, 15, 16, 21 }`) removes steering/pitch/roll control from the
driver of a land vehicle while it is airborne. Aircraft, boats, motorcycles,
cycles and trains are exempt by default; remove 8 from `exemptClasses` to make
motorcycles lose air control too. Set `disable = false` to restore stock GTA air control. Grounded
vehicles (including upside down) are never affected. The setting is read each
time the driver enters a vehicle.

## Related resources

Part of the [qbcore2](https://github.com/qbcore2) resource set:

- [kora_lib](https://qbcore2.github.io/kora_lib/) — shared helper library
- [kora_sql](https://qbcore2.github.io/kora_sql/) — database driver
- [kora_inventory](https://qbcore2.github.io/kora_inventory/) — headless inventory
- [kora_target](https://qbcore2.github.io/kora_target/) — targeting/interaction
- [kora_clothing](https://qbcore2.github.io/kora_clothing/) — clothing/wardrobe
- [kora_admin](https://qbcore2.github.io/kora_admin/) — admin menu
- [full resource list ↗](https://github.com/orgs/qbcore2/repositories)

## qb-core parity behaviour

- `QBCore:Server:PlayerLoaded` carries the stock Player wrapper (`.PlayerData`, `.Functions`), the same object as `QBCore.Players[src]`.
- `QBCore:Client:OnPlayerLoaded` fires at login by default. `Config.compat.deferClientPlayerLoaded = true` moves it to the stock
  point (the client's `QBCore:Server:OnPlayerLoaded` after spawn, once per login; kora_multichar and stock qb-spawn send it).
  Do not enable it if any login path skips that event: kora_loading and other consumers wait for the client event.
- `GetPlayerByLicense` falls back to the offline lookup (`GetOfflinePlayerByLicense`, read-only via kora_sql) like stock.
- Compat PlayerData view only (nothing extra persisted): root `optin` (default true; `ToggleOptin`/`IsOptin` use it, admin only),
  `position.w` beside `h`, `items` always a table, `charinfo.account` and `metadata.bloodtype/fingerprint/walletid/phonedata.SerialNumber`
  derived deterministically from the citizenid when absent.
- `QBCore.PlayerData` on the client is updated in place. `QBCore:Client:OnPlayerUpdated` still ignores the pushed value and
  `QBCore:Client:SharedUpdate` stays a no-op by design (server-authoritative mirror). `QBCore:ToggleDuty` notifies on/off duty.
- Vehicle spawn callbacks: see `vehicle-spawn.md`.
- Identifier lookups (`GetPlayer`, `GetSource`, `GetPlayerByLicense`, `IsLicenseInUse`, `GetOfflinePlayerByLicense`) accept `license:xxx` or the bare form; `GetIdentifier` still returns its stored form. `IsPlayerBanned` treats a NULL `expire` as permanent.
  `GetDatabaseInfo` also parses `server=..;database=..` strings (the connection string is never logged).
- Player drop fires `QBCore:Server:PlayerDropped` / `OnPlayerUnload` before the player is evicted (`GetPlayer(src)` works in handlers); `kora_core:server:playerDropped` follows eviction.
- `Player.Functions.AddMoney/RemoveMoney` accept amount 0 and lower-case the account; `AddPermission` refreshes commands; `SetPlayerBucket` sets `Player(src).state.instance`;
  `SetJobDuty` also fires `OnJobUpdate` / `OnPlayerUpdated`; `Shared.Round(v)` returns an integer; `QBCore.ServerCallbacks` / `ClientCallbacks` exist.
- `Locale` supports `extend/clear/replace/locale/has/delete`, the flat `phrases` field, `fallbackLang`, and `warnOnMissing` defaults to true.
- `hud:server:GainStress` / `RelieveStress` (number 1-100, clamped 0-100, per-source cooldown, `Config.compat.stress` for `disabled`/`whitelistedJobs`/`cooldownMs`; ignored while a real qb-hud runs).
- `qb-log:server:CreateLog` is a server-local handler forwarding to `Core.logging.logEvent`; it is deliberately not a net event and never reads webhooks.
- Legacy `police:client:policeAlert` now receives the stock `(coords, text)` order (kora_police accepts both).
