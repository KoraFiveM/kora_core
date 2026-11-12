---
title: "How to use"
sidebar_position: 3
---


# How to use

Kora Core owns the player: who is logged in, their PlayerData (money, job, gang, metadata, items, position) and the shared registries that describe items, jobs, gangs, vehicles and weapons. Other resources read and change that data through flat exports. This page explains the model, shows complete examples, and lists what scripts rely on.

## What Kora Core owns and what it leaves to others

- Owns: character creation, login and logout; the PlayerData table and its single write funnel (`setPath`); accounts (`cash`, `bank`, `crypto`); jobs, gangs and duty; metadata; the six shared registries; autosave and the database schema; replication of PlayerData to the owning client; permission levels; owned vehicles (garage).
- Delegates: item storage to the inventory provider (`Config.inventory.provider`, default `kora_inventory`) through `modules/inventory/gateway.lua`; physical cash to that provider once it calls `registerPhysicalCash`; character-select and spawn UI to a UI resource; the tax account to a banking resource when `Config.money.tax.enabled` is on.
- Everything that changes a player goes through `setPath`. `setMoney`, `setJob`, `setMetaData` and the rest are wrappers over it, so ownership checks, the busy fence during offline writes, replication and autosave marking happen in one place.
- Any resource can call any export. Only a few functions check `GetInvokingResource()` (see Security below). Validate who may ask before you call, not after.

## Example 1: a shop that charges cash and hands out an item

The client only says what it wants. The server owns the price list, checks the result of every call and refunds if the item cannot be given. `removeMoney` and `addItem` return `false, reason` (or `nil, message` when the inventory provider call itself fails), so test the first value.

```lua title="server/shop.lua"
local prices = { bread = 5, water = 3 }

RegisterNetEvent('myshop:server:buy', function(itemName)
    local src = source
    local price = type(itemName) == 'string' and prices[itemName]
    if not price then return end

    local paid, payReason = exports.kora_core:removeMoney(src, 'cash', price, 'myshop-purchase')
    if not paid then
        return TriggerClientEvent('QBCore:Notify', src, payReason or 'payment failed', 'error')
    end

    local given, giveReason = exports.kora_core:addItem(src, itemName, 1)
    if not given then
        exports.kora_core:addMoney(src, 'cash', price, 'myshop-refund', true)
        return TriggerClientEvent('QBCore:Notify', src, giveReason or 'could not give item', 'error')
    end
end)
```

## Example 2: change a job and react to it

Grades are one-based in the native API (the default and minimum is 1). `getJob` returns the live job record: `{ name, label, type, payment, onduty, isboss, grade = { name, level } }`. Other resources hook the local events that fire after the change; the job passed to `QBCore:Server:OnJobUpdate` is the legacy-shaped record, whose `grade.level` is zero-based.

```lua title="server/promote.lua"
exports.kora_core:addCommand('promote', 'Promote a player one grade', {
    { name = 'id', help = 'Player server id' },
}, true, function(source, args)
    local targetId = tonumber(args[1])
    local job = targetId and exports.kora_core:getJob(targetId)
    if not job then return end

    local ok, reason = exports.kora_core:setJob(targetId, job.name, job.grade.level + 1)
    if not ok then
        print(('promote failed: %s'):format(reason))
    end
end, 'admin')

AddEventHandler('QBCore:Server:OnJobUpdate', function(src, job)
    print(('player %d is now %s (%s)'):format(src, job.label, job.grade.name))
end)
```

## Example 3: register your own records and read them anywhere

The shared registries (`items`, `vehicles`, `jobs`, `gangs`, `weapons`, `locations`) live on the server and are mirrored to every client. Register on the server with `registerShared`. Read from any realm, including your own client scripts, through `Kora.shared` after loading `@kora_core/init.lua`.

```lua title="server/registry.lua"
local ok, reason = exports.kora_core:registerShared('jobs', 'mechanic', {
    name = 'mechanic',
    label = 'Mechanic',
    type = 'civ',
    defaultDuty = true,
    offDutyPay = false,
    grades = {
        { name = 'Apprentice', payment = 50 },
        { name = 'Boss', payment = 150, isboss = true },
    },
})
if not ok then print(('could not register job: %s'):format(reason)) end
```

## Example 4: several changes that must succeed together

`transaction` validates every leg first, applies money removal, item removal, item additions and money additions in that order, and rolls back on failure. It is best effort, not a database transaction, so keep the legs few and use unique reasons.

```lua title="server/craft.lua"
local function craftBandage(src)
    local ok, reason = exports.kora_core:transaction(src, {
        reason = 'craft-bandage',
        money = { remove = { { account = 'cash', amount = 25 } } },
        items = {
            remove = { { item = 'cloth', amount = 2 } },
            add = { { item = 'bandage', amount = 1 } },
        },
    })
    return ok, reason
end
```

## Choosing the right call

- Read one value: `getPlayerData(src, { 'money', 'cash' })` (path array, returns a copy of tables). Read everything: `getPlayer(src)` (deep copy, safe to keep).
- Change money: `addMoney` / `removeMoney` (taxed unless `ignoreTax` is true), `setMoney` (never taxed), `transferMoney` (one fenced move). For an offline character use `addOfflineMoney`.
- Several money and item changes together: `transaction`. A single item: the inventory exports (`addItem`, `removeItem`).
- Change a job: `setJob` for an online player, `setOfflineJob` for a character that is not logged in. Duty only: `setJobDuty`.
- Count staff: `getDutyCount(jobName)` or `getDutyCountByType(jobType)`. Dispatch to them: `alert`. Read `GlobalState.OnDuty` on a client for the same counts.
- Permissions: `getPermission(src)` returns the highest level (`god`, `admin`, `mod`, `user`); `hasPermission(src, level)` is a flat ACE check and is not ranked, so test the exact principal you grant.
- Persist now: `savePlayer(src)` for one player, `flushAll()` for everyone. Autosave runs every `Config.persistence.interval` ms anyway.
- Registries: `getShared` and `allShared` return live records, so treat them as read-only. Change them only with `registerShared` / `unregisterShared`.

## Security: the client is not authoritative

Net events never carry a trusted player id: the handler reads `source`. Amounts, prices, item names and target ids from a client are input to validate, never values to apply. Kora Core itself validates the few events a client may send (character select checks ownership by license, legacy metadata writes use an allow-list, `QBCore:ToggleDuty` has a cooldown).

These exports are not restricted by caller: `login`, `createCharacter`, `setPath`, `registerShared`, `unregisterShared`, `saveOfflinePlayer`, `setMaxCharacters`, `addPermission`, `dropPlayer`, `setDevMode`, `collectTax`. Any server resource can call them. The `permission` text of `addPermission` is passed to `ExecuteCommand` unchanged, so never forward client text into it.

Restricted by caller: `registerPhysicalCash` (only `Config.inventory.provider`), `beginPlayerColumnOperation` / `finishPlayerColumnOperation` / `abortPlayerColumnOperation` / `getPlayerColumnOperations` (only `kora_banking` or the inventory provider), and the `position` option of `logout` (only `kora_housing`).

On the client, `QBCore:Player:SetPlayerData`, `QBCore:Client:OnPlayerUnload` and `kora_core:client:setDevMode` have no source check. Only server code you trust should trigger them for a player.

```lua title="server/admin.lua"
RegisterNetEvent('myadmin:server:giveMoney', function(targetId, amount)
    local src = source
    if not exports.kora_core:hasPermission(src, 'admin') then return end

    targetId = tonumber(targetId)
    amount = tonumber(amount)
    if not targetId or not amount or amount <= 0 or amount > 100000 then return end
    if not exports.kora_core:getPlayer(targetId) then return end

    local ok, reason = exports.kora_core:addMoney(targetId, 'bank', amount, 'admin-grant', true)
    if not ok then print(('grant failed: %s'):format(reason)) end
end)
```

## ConVars, ACEs and switches

- `mysql_connection_string` (read by Kora SQL, and by the qb-core compat `GetDatabaseInfo`).
- `kora:vehicleIdStateBag` (default `1`): set to `0` to stop `tagVehicle` writing the server-only `vehicleid` state bag.
- `kora:qbxFacade` (default `false`) or `Config.compat.qbxFacade`: turns on the `qbx_core` / `qbx_vehicles` facade. It refuses to start if a resource named `qbx_core` or `qbx_vehicles` exists.
- `sv_maxclients`, `kora_discord`: read into the legacy `QBCore.Config` (`MaxPlayers`, `Server.Discord`).
- `kora_lib_log_webhook` (fallbacks `kora_lib_log_webhook`, `kora_core_log_webhook`): Discord webhook used by `logEvent`, read by Kora Lib.
- ACE principals: `kora_core.god`, `kora_core.admin`, `kora_core.mod` (also `group.<level>` and `command.<name>`). `resource.kora_core` needs `command` for `addPermission` / `removePermission`.
- Config switches worth knowing: `Config.inventory.provider`, `Config.inventory.allowLegacyFallback`, `Config.money.tax.enabled`, `Config.compat.defaultCommands`, `Config.compat.vehicleSpawnCallbacks`, `Config.compat.jobUpdateEventSource`. See the Configuration module.

## Integration points other resources rely on

- Lifecycle events (server, local): `kora_core:server:playerLoaded (src, citizenid)`, `kora_core:server:playerDropped (src, citizenid, reason)`, `QBCore:Server:OnPlayerUnload (src)`, `QBCore:Server:OnMoneyChange`, `QBCore:Server:OnJobUpdate`, `QBCore:Server:OnGangUpdate`, `QBCore:Server:OnMetaDataChange`. Full list and payloads in Events, callbacks and state bags.
- State bags: `GlobalState.OnDuty` (counts per job name and job type), `Player(src).state['kora_core:loggedIn']`, `Player(src).state['isLoggedIn']`, `Player(src).state['kora_core:money:<account>']`, `Player(src).state.instance`, and the server-only `Entity(vehicle).state.vehicleid`.
- Inventory provider contract: the provider calls `registerPhysicalCash` and the column-operation fences, and receives every inventory export forwarded by the gateway. Kora Core calls `exports[provider]:<name>` with the same name and arguments.
- Character UI contract: a character-select resource calls `claimUI`, then `request`, `select`, `create` (client exports) and handles `kora_core:client:receiveCharacters` and `kora_core:client:characterSelected`.
- Client readers: `exports.kora_core:getPlayerData(path)` on the client reads the replicated mirror. `kora_target` also calls the client export `toLegacyPlayerData` for job, gang and citizenid filters.
- Consumer VM mirror: `shared_script '@kora_core/init.lua'` adds `Kora.shared.get / all / epoch / register / unregister / onChange / offChange` to your own script VM.
- qb-core scripts: keep calling `exports['qb-core']:GetCoreObject()`; see the Compatibility module for exactly what is converted.

## Common mistakes

- Passing a zero-based grade to `setJob`. Native grades start at 1 (zero or lower becomes 1); only the qb-core compat layer converts from zero-based.
- Mutating the table returned by `getShared` or `allShared`. Those are live registry records. Copy them first (`exports.kora_core:deepClone`).
- Assuming `hasPermission` honours rank. It checks the exact ACE objects `kora_core.<p>`, `group.<p>` and `command.<p>`; grant the inheritance lines in `server.cfg` yourself.
- Calling `login`, `createCharacter` or `setPath` with client-supplied data. They trust their caller.
- Ignoring return values. Most wrappers return `false, reason`; the inventory gateway returns `nil, message` when the provider call fails.
- Treating `transaction` as atomic. Rollback is best effort and `canCarry` is checked per item, not cumulatively.
- Expecting `getMoney` to match the legacy cash field while the inventory provider is down: it returns `nil` and `'physical cash provider unavailable'`.
- Calling a client export on the server (or the reverse). `getJob`, `getGang`, `getPlayerData`, `onChange`, `isDevMode` and `getInventory` exist in both realms with different arguments.

## Quick examples (code-derived)

```lua
-- server: give a starting kit
exports.kora_core:addMoney(source, 'cash', 500, 'starting-kit')
exports.kora_core:addItem(source, 'water_bottle', 2)

-- server: react to bank balance changes
exports.kora_core:onChange({ 'money', 'bank' }, function(src, path, value)
    print(('player %d bank is now %s'):format(src, value))
end)

-- client: read the local mirror (no network round trip)
local job = exports.kora_core:getPlayerData({ 'job' })
print(job.label, job.grade.level)
```

```lua
-- legacy resource, unmodified
local QBCore = exports['qb-core']:GetCoreObject()
local Player = QBCore.Functions.GetPlayer(source)
Player.Functions.AddMoney('cash', 500, 'reason')
Player.Functions.SetJob('police', 2) -- zero-based grade, like stock qb-core
```
