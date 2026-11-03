# kora_core API reference

Two ways to use qbcore: the modern flat exports (`exports.kora_core:getPlayer(src)`)
for new code, and the legacy `exports['qb-core']:GetCoreObject()` object for
existing QBCore resources (works unmodified).

## Setup

`server.cfg`, in order:
```
set mysql_connection_string "mysql://user:pass@localhost/qbcore?charset=utf8mb4"
ensure kora_sql
ensure kora_lib
ensure kora_core
```
kora_core creates its own tables on first boot via kora_sql's migration runner.

## Modern API (`exports.kora_core:*`)

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
exports.kora_core:addMoney(src, account, amount, reason)     -- true | false, err
exports.kora_core:removeMoney(src, account, amount, reason)
exports.kora_core:setMoney(src, account, amount, reason)
exports.kora_core:getMoney(src, account)
exports.kora_core:transferMoney(fromSrc, toSrc, account, amount, reason)
```
Accounts: `cash`, `bank`, `crypto` (Config.money.types). `bank` may go negative
to `Config.money.minusLimit`.

### Jobs / gangs
```lua
exports.kora_core:setJob(src, name, grade)
exports.kora_core:setGang(src, name, grade)
exports.kora_core:setJobDuty(src, onDuty)
exports.kora_core:getJob(src)  exports.kora_core:getGang(src)
exports.kora_core:getPlayersByJob(name, onDutyOnly)   -- O(1), maintained index
exports.kora_core:getDutyCount(name)
exports.kora_core:getPlayersByJobType(jobType, onDutyOnly)  -- every job of a type ('leo', 'ems', ...)
exports.kora_core:getDutyCountByType(jobType)         -- on-duty count across every job of a type
exports.kora_core:checkJob(src, rule)                 -- true | false, reason; reads the live job, no copy
```
`rule = { name?, type?, minGrade?, onDuty? (default true), boss? }`; reasons are
`no_player`, `wrong_job`, `off_duty`, `grade_too_low`, `not_boss`. See
[modules/jobs/docs.md](modules/jobs/docs.md).

### Metadata
```lua
exports.kora_core:getMetaData(src, key)
exports.kora_core:setMetaData(src, key, value)
exports.kora_core:incrementMetaData(src, key, delta, min, max)
```

### Development mode
```lua
exports.kora_core:setDevMode(src, true)   -- server: god mode, frozen passive needs, fast walk
exports.kora_core:isDevMode(src)          -- server: one player's current state
exports.kora_core:isDevMode()             -- client: local state
```
Development mode is per-player, ephemeral, and disabled again with
`setDevMode(src, false)`. Permission-gate the server export in the calling
resource.

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
shipped. kora_inventory is the headless inventory authority and separately owns the
`qb-inventory` compatibility identity; its optional companion resource owns any UI.

### Transactions
```lua
exports.kora_core:transaction(src, {
    reason = 'shop purchase',
    money = { remove = { { account = 'cash', amount = 500 } } },
    items = { add = { { item = 'sandwich', amount = 2, info = {} } } }
}) -- true | false, errorString
```

All money balances, item quantities, and carry capacity are checked before
mutation. Amounts must be positive whole numbers. Item entries require `item`
and `amount`, with optional `slot` and `info`; money entries require `account`
and `amount`. A later failure triggers best-effort compensation. This is not
crash-proof atomicity: callers must authorize the operation and validate price,
ownership, permissions, and distance. `coords` is metadata only.

An optional `random` list adds independently rolled bonus items using
`Kora.rewards.generate` in percent mode with `allowNone = true`. Entries use
`item`, optional `chance` (percentage), optional `amount` (defaults to `1`, or
a positive integer `{ min, max }` range), and optional `slot`/`info`. Entries
without a chance split 100% equally among themselves. Winning bonuses share
the existing validation and rollback path; missing or empty lists do nothing.
See [random reward examples](modules/transaction/docs.md).

`exports.kora_core:sellItem(src, spec)` / `buyItem(src, spec)` handle the usual
vendor case in one transaction:
`spec = { item, amount, unitPrice, account?, reason, maxAmount?, metadata?, at?, maxDistance? }`.
The untrusted `amount` is checked with `Kora.util.toAmount`, and they return
`true, { amount, total }` or `false, reason`. See
[modules/transaction/docs.md](modules/transaction/docs.md#buying-and-selling-sellitem--buyitem).

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
`shared_script '@kora_core/init.lua'` (after `@kora_lib/init.lua`) and use:
```lua
Kora.shared.get(name, key)      -- local hash lookup, zero boundary crossing
Kora.shared.all(name)
Kora.shared.register(name, key, record)
Kora.shared.onChange(name, function(action, key, record, previous) ... end)
```
A registration in ANY resource fires every subscriber's `onChange` in every
resource that uses the list — the `/ideas` requirement. Always use `get` for an
individual record, and call `all` again whenever a UI/admin list is built. Do
not cache or index `QBCore.Shared.Jobs` (or its sibling compatibility maps) in
new code.

### Local player copy on the client: `Kora.player`
The `@kora_core/init.lua` include (after `@kora_lib/init.lua`) also installs
`Kora.player` on the **client**. It keeps a local copy of the player's `job`,
`gang`, `metadata` and `charinfo`, so per-tick code such as target
`canInteract` checks, HUDs and draw loops reads a plain table instead of calling
an export and copying data every frame.
```lua
Kora.player.get(path)          -- 'job' or { 'metadata', 'hunger' }; nil = whole local copy
Kora.player.job()  Kora.player.gang()  Kora.player.metadata(key)  Kora.player.isLoaded()
Kora.player.checkJob(rule)     -- same rule and reasons as the server checkJob; UI only
Kora.player.onChange(prefix, fn) -> id   -- fn(path, value)
Kora.player.offChange(id)
```
Each watched root costs one `getPlayerData` call when the copy is seeded and one
`onPlayerDataChange` subscription. Reading any other root (`money`, `items`, ...)
starts watching it on the first read. The copy is refreshed from kora_core's
login snapshot, cleared on logout, and re-attached when kora_core or kora_lib
restarts. `onChange` handlers also fire with the current value after each of
those. Values are live: read them, don't modify them. The server must still
re-check anything this copy is used to show (`exports.kora_core:checkJob`).
```lua
-- client, inside a target option
canInteract = function() return Kora.player.checkJob({ type = 'leo' }) end
```

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

Current upstream behavior also includes the complete `QBCore.Config` shape,
`PlayersByCitizenId`, phone/account generators, runtime player method/field
extensions, and full offline player lookup/create/check/save objects. The
legacy draw-text events (`qb-core:client:drawText`, `changeText`, and
`hideText`) forward to kora_lib's text UI.

For client UI visibility, prefer the server-owned replicated player state bag
`LocalPlayer.state['qbcore:loggedIn']` and `AddStateBagChangeHandler` over
legacy load/unload events. kora_core sets it true only after the initial PlayerData
snapshot and clears it before logout teardown; legacy lifecycle events remain
for compatibility. A bare `LocalPlayer.state['isLoggedIn']` is mirrored
alongside it for legacy consumers — real qb-core uses that unnamespaced key and
untouchable scripts (real qb-doorlock's client loop) read it directly. New code
should use the namespaced key.

Domain resources can add a client-visible read model to PlayerData without
placing it in `metadata`: register a non-core root with
`registerPlayerDataField(key, provider)`, then publish changes with
`setPlayerDataField(source, key, value)`. The provider hydrates the field before
the initial snapshot. The registering resource exclusively owns writes to the
field, and kora_core never persists it; authorization must use the owner's server
database/cache rather than the replicated client copy.

### Known compat caveats
- A `Player` object returned to ANOTHER resource carries a `PlayerData` SNAPSHOT
  frozen at call time (it crossed the export boundary as a copy). The function
  refs stay live; for fresh data call `Player.Functions.GetPlayerData()`. (Legacy
  qb-core has the same footgun.)
- `SetPlayerData(key, value)` to a root key with no DB column mapping is refused
  with a warning rather than silently not persisting.
- `QBCore.Functions.ExecuteSql` is deprecated (its `wait` arg is ignored) —
  forwarded to `Kora.sql.query`, warned once per calling resource.
- `QBCore.Shared.Items/Jobs/...` are legacy-only live views. Writing them
  bypasses the registry, so subscribers won't fire. New code must use
  `getShared`/`allShared` for reads and `registerShared` (or the legacy
  `AddItem`/`AddJob` wrappers) for writes.
- `QBCore.Commands.List` is a table keyed by command name (matching upstream), but
  it reflects commands registered THROUGH the compat (`QBCore.Commands.Add`) or
  present at the last `Refresh`; commands added by another resource straight
  through `Kora.commands` appear only after the next `Add`/`Refresh`.
- `QBCore:UpdatePlayer` does NOT decrement hunger/thirst here (the `needs` module
  owns decay on its own timer); the handler refreshes the stock HUD and persists,
  so a stock qb-hud keeps working without double-ticking.
- Client `QBCore.Functions.Progressbar` translates legacy `prop`/`propTwo`
  descriptors into kora_lib's networked progress props. `IsWearingGloves` uses
  upstream's freemode no-glove tables and returns `true` for unknown indices.

## Character selection
No NUI ships. A bare server auto-selects character slot 1 (creating a default
character if none exist). A character-select UI calls
`exports.kora_core:claimUI()` and drives
`exports.kora_core:getCharacters/selectCharacter/deleteCharacter` (or the
`qbcore:server:*` / legacy `qb-multicharacter:*` events).

The character-slot cap is `Config.identity.maxCharacters` by default, but a
`users` row can override it per license (`exports.kora_core:setMaxCharacters`) --
see `modules/users/docs.md`. `Core.player.createCharacter` enforces the cap
and assigns the slot itself; a client-supplied `cid` is only honoured if it's
free and in bounds, never trusted to gate the limit.

## Config highlights (`config.lua`)
`Config.persistence.interval` (60s save window), `Config.money.types/default`,
`Config.inventory.maxWeight/slots`, `Config.compat.fireLegacyPlayerDataEvent`
(default true), `Config.persistence.generatedColumns` (opt into SQL-queryable
cash/bank/job virtual columns), and `Config.development.walkSpeed` (`1.75` by
default while per-player development mode is active).

## Portability (reuse beyond GTA5/FiveM)

kora_core/kora_lib target FiveM today; this section is a status snapshot for anyone
weighing whether the "core" (permissions, player data/callback plumbing,
money, jobs/gangs, commands, registry) could realistically be reused on
RedM — Cfx.re's other platform, same Lua/`fxmanifest`/`exports`/`TriggerEvent`
runtime, different game natives. **This is an assessment, not a promise or a
plan in progress** — nothing here has been built toward RedM, and none of it
should be, until RedM support is an actual, scoped ask with a real second
platform to validate an abstraction against. Recorded here so the answer
doesn't have to be re-derived from scratch if that ask ever comes.

**Bottom line: almost the entire "core" cluster is already platform-agnostic.**
Every module in it — `commands`, `permissions`, `player`, `money`, `jobs`,
`metadata`, `replication`, `identity`, `registry`, `users`, `multichar` — uses
only Cfx-generic runtime primitives (`TriggerEvent`/`RegisterNetEvent`,
`RegisterCommand`, `IsPlayerAceAllowed`, `GetPlayerIdentifier`, `GetGameTimer`,
SQL) that are byte-identical on RedM, or no natives at all. That wasn't a
deliberate RedM-readiness effort — it's a side effect of the funnel/event
architecture keeping game-world state out of the core's own bookkeeping.

The one place in that cluster that touches a game native directly:
**`modules/persistence`**'s `samplePosition` reads `GetPlayerPed`/
`GetEntityCoords`/`GetEntityHeading` to sample a player's position at save
time. Those three natives exist with the same signature on RedM, so this
isn't even a hard port — it's flagged only because it's the sole native call
in an otherwise-native-free module.

Modules genuinely coupled to GTA5-specific game content, not just FiveM-vs-RedM
API differences: `garage` (fuel/engine/body-health natives model a car's
damage system that has no RedM equivalent — horses/wagons work completely
differently) and the external `kora_inventory` resource's weapon/item models
(not audited here, but almost certainly where GTA5-specific content actually
concentrates, since kora_core's own `inventory` module is a thin gateway with no
item logic of its own). `kora_lib`'s `zones`/`world`/`stream`/etc. modules use
natives that exist on RedM but weren't audited for this specific question —
see `kora_lib`'s own docs for its module-by-module native surface.

Native consumers call `exports.kora_core:<method>`. For existing public callbacks that must retain the QBCore wire, `exports.kora_core:createCallback(name, handler)` registers the same `handler(source, reply, ...)` on both transports. Native clients use `Kora.callback.trigger(name, ...)`; new callbacks can use `Kora.callback.register` directly.
