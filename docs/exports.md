---
title: Exports
sidebar_position: 5
---

# Exports

`build/finalise.lua` publishes every public function of every module as a flat
export: `exports.kora_core:<name>(...)`. Names are unique per realm (a collision
aborts the boot). Functions whose name starts with `_` are internal and not
exported.

Conventions:

- Fallible functions return `true` (or a value) on success and `false` or `nil`
  plus an error string on failure.
- "Yields" means the function waits on the database or another resource; call it
  from a thread or an event handler, not from a tight loop.
- Paths are key arrays such as `{ 'metadata', 'hunger' }`.
- Grades are one-based in all native exports.

The legacy `qb-core` and `qbx_core` exports are listed on the
[Compatibility](./compatibility.md#exports) page.

## Server exports

### Player and characters

| Export | Returns | Notes |
| --- | --- | --- |
| `setPath(src, path, value, opts)` | `true` or `false, err` | The mutation funnel. `opts.silent` skips replication. [Details](./features/player.md#writing-the-funnel) |
| `getPlayer(src)` | table or `nil` | Deep copy of PlayerData. |
| `getPlayerByCitizenId(citizenid)` | table or `nil` | Deep copy for an online character. |
| `getPlayerData(src, path)` | any | Value at `path` (tables copied), whole copy when `path` is `nil`. |
| `getPlayers()` | integer array | Sources with a loaded character. |
| `getAllPlayers()` | table array | Copies of every loaded character. |
| `onChange(prefix, handler)` | id or `nil, err` | `handler(src, path, value)`. Owner-tracked. |
| `offChange(id)` | none | |
| `registerPlayerDataField(key, provider)` | `true` or `false, err` | Resource-owned, replicated, unsaved root field. `provider(src, citizenid)`. |
| `setPlayerDataField(src, key, value)` | `true` or `false, err` | Only the owning resource. |
| `login(src, citizenid, data)` | `true` or `false, err` | Adopts already-loaded data. |
| `createCharacter(src, charinfo, cid)` | citizenid or `nil, err` | Yields. |
| `logout(src, options)` | `true` or `false, err` | Yields until the save is confirmed. `options.position` only from `kora_housing`. |
| `dropPlayer(src, reason)` | none | Called automatically on `playerDropped`. |
| `savePlayer(src, requiredField)` | `true` or `false, err` | Immediate save. |
| `setPlayerBucket(src, bucket)` | boolean | Routing bucket plus `instance` state bag. |
| `getStarterItems()` | table | Copy of `QBCore.Shared.StarterItems`. |
| `isCoreReady()` | boolean | |
| `getCharacters(src)` | table array | Yields. |
| `ownsCharacter(src, citizenid)` | boolean | Yields. |
| `selectCharacter(src, citizenid)` | `true` or `false, err` | Yields. |
| `deleteCharacter(src, citizenid)` | boolean, or `false, err` | Yields. Soft delete. |

```lua
local data = exports.kora_core:getPlayer(source)
if data then print(data.citizenid, data.job.name) end
```

### Persistence

| Export | Returns | Notes |
| --- | --- | --- |
| `flushAll()` | integer | Players enqueued. |
| `saveNow(player)` | none | Takes the internal handle; use `savePlayer(src)` from other resources. |
| `awaitSchema()` | `true` or `false, err` | Yields up to 60 s. |
| `getOfflinePlayerData(citizenid)` | table or `nil, err` | Yields. |
| `saveOfflinePlayer(data, fields)` | `true` or `false, err` | Yields. Only named roots, offline characters only. |
| `beginPlayerColumnOperation(key, citizenids, columns)` | token, or `nil, code, message` | Yields. `kora_banking` and the inventory provider only. |
| `finishPlayerColumnOperation(token, values)` | `true` or `false, err` | Yields. |
| `abortPlayerColumnOperation(token)` | `true` or `false, err` | Yields. |
| `getPlayerColumnOperations()` | table array | Yields. Raises when storage is unavailable. |

### Money

| Export | Returns | Notes |
| --- | --- | --- |
| `getMoney(src, account)` | number or `nil` | |
| `addMoney(src, account, amount, reason, ignoreTax)` | `true` or `false, err` | Positive gross amount. |
| `removeMoney(src, account, amount, reason, ignoreTax)` | `true` or `false, err` | |
| `setMoney(src, account, amount, reason)` | `true` or `false, err` | Never taxed. |
| `transferMoney(fromSrc, toSrc, account, amount, reason, ignoreTax)` | `true` or `false, err` | |
| `addOfflineMoney(citizenid, account, amount)` | `true` or `false, err` | Yields. |
| `getTaxRate(account, action)` | number | |
| `calculateTax(amount, account, action)` | number | Configuration only. |
| `getTransactionTax(amount, account, action)` | number | 0 while the tax provider is stopped. |
| `getTaxAccount()` | string or `nil` | |
| `collectTax(amount, reason)` | `true` or `false, err` | Yields. |
| `registerPhysicalCash(account)` | `true` or `false, err` | Inventory provider only. |
| `unregisterPhysicalCash(account)` | `true` or `false, err` | Registered provider only. |
| `isPhysicalCash(account)` | boolean | |
| `migratePhysicalCash(src)` | `true` or `false, err` | |
| `syncState(src)` | none | Republishes `kora_core:money:<account>` state bags. |
| `transaction(src, definition)` | `true` or `false, err` | [Details](./features/money.md#transactions) |

```lua
local ok, err = exports.kora_core:transferMoney(fromSrc, toSrc, 'bank', 100, 'trade')
```

### Jobs, gangs, paychecks and dispatch

| Export | Returns | Notes |
| --- | --- | --- |
| `getJob(src)` | table or `nil` | |
| `getGang(src)` | table or `nil` | |
| `setJob(src, name, grade)` | `true` or `false, err` | |
| `setGang(src, name, grade)` | `true` or `false, err` | |
| `setJobDuty(src, onDuty)` | `true` or `false, err` | |
| `setOfflineJob(citizenid, name, grade)` | `true` or `false, err` | Yields. |
| `setOfflineGang(citizenid, name, grade)` | `true` or `false, err` | Yields. |
| `getPlayersByJob(name, onDutyOnly)` | integer array | |
| `getPlayersByJobType(jobType, onDutyOnly)` | integer array | |
| `getDutyCount(name)` | integer | |
| `getDutyCountByType(jobType)` | integer | |
| `getJobTypeCounts(onDutyOnly)` | map | |
| `getOnDutyRoster(filter)` | table array | |
| `startPaycheck()` / `stopPaycheck()` | none | |
| `isPaycheckRunning()` | boolean | |
| `alert(payload)` | integer | Recipients. Asserts `payload.jobs` is a non-empty array. |

```lua
local onDutyLeo = exports.kora_core:getPlayersByJobType('leo', true)
```

### Metadata, needs, development, jail

| Export | Returns | Notes |
| --- | --- | --- |
| `getMetaData(src, key)` | any | |
| `setMetaData(src, key, value)` | `true` or `false, err` | |
| `incrementMetaData(src, key, delta, min, max)` | number or `nil, err` | |
| `startNeedsDecay()` / `stopNeedsDecay()` | none | |
| `reset(src)` | none | hunger/thirst 100, stress 0. |
| `setDevMode(src, enabled)` | `true` or `false, err` | |
| `isDevMode(src)` | boolean | |
| `jailPlayer(src, minutes, reason)` | `true` or `false, err` | |
| `release(src)` | boolean | |
| `getRemaining(src)` | integer | Seconds. |
| `isJailed(src)` | boolean | |

### Inventory

With the inventory provider started, these forward to its export of the same name.
[Details](./features/inventory.md)

| Export | Returns |
| --- | --- |
| `addItem(src, name, amount, slot, info, reason)` | `true` or `false, err` |
| `removeItem(src, name, amount, slot, reason)` | `true` or `false, err` |
| `getItemByName(src, name)` | item or `nil` |
| `getItemsByName(src, name)` | item array |
| `getItemBySlot(src, slot)` | item or `nil` |
| `getItemCount(src, name)` | integer |
| `hasItem(src, nameOrList, amount)` | boolean |
| `getFreeSlot(src)` | integer or `nil` |
| `canCarry(src, name, amount)` | `true` or `false, err` |
| `getWeight(src)` | weight, maxWeight |
| `moveItem(src, fromSlot, toSlot, amount)` | `true` or `false, err` |
| `clearInventory(src, keep)` | `true` or `false, err` |
| `setItems(src, items)` | boolean |
| `createUseable(name, handler)` | none |
| `getUseable(name)` | table or `nil` |
| `useItem(src, slotOrName)` | boolean |
| `stashGet(identifier)` | table (yields) |
| `stashSet(identifier, items)` | `true` |
| `stashOpen(src, identifier, opts)` | `true` |
| `dropCreate(coords, items)` | integer |
| `dropTake(src, dropId, slot, amount)` | `true` or `false, err` |
| `isRegistered()` | boolean (consumable effects hook) |

### Shared registries

| Export | Returns |
| --- | --- |
| `getShared(name, key)` | record or `nil` |
| `allShared(name)` | live array |
| `countShared(name)` | integer |
| `sharedSnapshotAll()` | table |
| `registerShared(name, key, record)` | `true` or `false, err` |
| `registerManyShared(name, records)` | integer |
| `unregisterShared(name, key)` | boolean |
| `onSharedChange(name, handler)` | id or `nil, err` |
| `offSharedChange(name, id)` | none |

### Garage

| Export | Returns |
| --- | --- |
| `createVehicle(citizenid, model, plate, job, extra)` | `true` or `false, err` |
| `getByPlate(plate)` | row or `nil` |
| `getByOwner(citizenid)` | row array |
| `storeVehicle(plate, snapshot)` | `true` or `false, err` |
| `spawnVehicle(src, plate, coords, heading, expectedOwner)` | network ID or `false, err` |
| `tagVehicle(entity, id)` | boolean |
| `impound(plate, fee, impoundLot)` | `true` or `false, err` |
| `retrieveImpound(src, plate)` | `true` or `false, err` |
| `updateState(plate, patch)` | boolean |
| `saveVehicleProperties(plate, properties)` | `true` or `false, err` |
| `deleteVehicle(plate)` | boolean |

### Identity, users, permissions, commands, logging, callbacks

| Export | Returns |
| --- | --- |
| `getIdentifiers(src)` | map |
| `primary(src)` | string or `nil` |
| `generateCitizenId()` | string |
| `recordIdentifiers(citizenid, ids)` | none |
| `findByIdentifier(kind, value)` | string array (yields) |
| `getMaxCharacters(license)` | integer (yields) |
| `setMaxCharacters(license, max)` | none (yields) |
| `recordDiscord(src)` | none (yields) |
| `getDiscord(license)` | string or `nil` (yields) |
| `getPermission(src)` | string |
| `hasPermission(src, permission)` | boolean |
| `addPermission(src, permission)` | boolean |
| `removePermission(src, permission)` | boolean |
| `isOptin(src)` | boolean |
| `addCommand(name, help, args, argsRequired, handler, permission)` | none |
| `removeCommand(name)` | none |
| `refreshCommands(src)` | none |
| `listCommands()` | table array |
| `logEvent(category, src, data)` | none |
| `getLogStats()` | table |
| `createCallback(name, handler)` | none; `handler(source, reply, ...)` on both callback transports |

### Utilities (also on the client)

`round`, `trim`, `splitStr`, `randomStr`, `randomInt`, `randomAlnum`, `deepClone`,
`pathGet`, `pathSet`. See [Identity and utilities](./features/identity-utilities.md#utilities-both-realms).

### Compatibility helpers

The compat layer's helpers are exported as a side effect of living on
`Core.compat`. They exist for kora_core's own legacy layer; other resources should
not depend on them: `buildOfflinePlayer`, `buildLoadedPlayer`,
`onPlayerDataChanged`, `toLegacyGradeLevel`, `fromLegacyGradeLevel`,
`toLegacyJobOrGang`, `toLegacyPlayerData`, `fromLegacyPlayerData`,
`fillMetadataDefaults`, `fillCharinfoDefaults`, `legacyPosition`,
`canonicalSharedNamespace`, `populateLegacyConfig` (the shared ones are also
exported on the client).

## Client exports

| Export | Returns | Notes |
| --- | --- | --- |
| `getPlayerData(path)` | any | Local mirror; the live table when `path` is `nil`. |
| `getData(path)` | any | Same as `getPlayerData`. |
| `onPlayerDataChange(prefix, handler)` | id or `nil, err` | `handler(path, value)`. |
| `offPlayerDataChange(id)` | none | |
| `onChange(prefix, handler)` | id or `nil, err` | Same as `onPlayerDataChange` (client realm). |
| `offChange(id)` | none | |
| `requestResync()` | none | |
| `getStats()` | table | `seq`, `resyncs`, `opsApplied`, `lastDeltaAt`. |
| `reannounceFull()` | boolean | Re-fire the legacy full PlayerData event. |
| `isWearingGloves()` | boolean | |
| `getJob()` / `getGang()` | table or `nil` | From the mirror. |
| `getInventory()` | table | Mirror `items`, or empty. |
| `isDevMode()` | boolean | |
| `claimUI()` | none | Disable the default character auto-select. |
| `request()` | none | Request the character list. |
| `select(citizenid)` | none | Select a character. |
| `create(charinfo, cid)` | none | Create a character. |
| `openSelector()` | none | Language selector. |
| `getShared(name, key)` / `allShared(name)` / `countShared(name)` / `sharedSnapshotAll()` | | Client registry copy. |
| `onSharedChange(name, handler)` / `offSharedChange(name, id)` | | Client registry subscriptions. |
| `registerShared(name, key)` | `false, err` | Always refused on the client. |

```lua
-- client
local id = exports.kora_core:onPlayerDataChange({ 'job' }, function(path, value)
    print('job changed', value and value.name)
end)
```
