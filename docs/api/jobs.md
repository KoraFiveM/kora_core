---
title: "Jobs, gangs, duty, paycheck and dispatch"
sidebar_position: 4
---


# Jobs, gangs, duty, paycheck and dispatch

## Server

Sets and reads each player's job and gang, tracks on-duty state, maintains an in-memory index so job lookups are O(1), publishes live on-duty counts as `GlobalState.OnDuty`, runs the paycheck loop and fans dispatch alerts out to on-duty members. Writes go through `Core.player.setPath`, so they persist and replicate to the client like any other PlayerData change.

Namespace: `exports.kora_core` · Source: `modules/jobs/server.lua, modules/dispatch/server.lua, modules/paycheck/server.lua, shared/jobs.lua, shared/gangs.lua`

### Legacy dispatch events

Fired after the fan-out, once per legacy job name present in `payload.jobs`, when `Config.dispatch.legacyEvents` is true. Every recipient of the alert (the union over all listed jobs) receives the client event. Listing both `ambulance` and `ems` therefore sends `hospital:client:ambulanceAlert` twice. `text` is `payload.message or payload.title or ''`.

| Job name in payload.jobs | Local server event (args) | Client event to each recipient (args) |
| --- | --- | --- |
| police | police:server:policeAlert (text) | police:client:policeAlert (payload.coords, text) |
| ambulance | none | hospital:client:ambulanceAlert (payload.coords, text) |
| ems | none | hospital:client:ambulanceAlert (payload.coords, text) |

### How it works

All exports are server-side and callable by any resource (no `GetInvokingResource()` check). Job and gang names must exist in the registry (`getShared('jobs'|'gangs', name)`); the defaults come from shared/jobs.lua (`unemployed`, `police`, `ambulance`, `mechanic`, `roadside`, `bodyshop`, `tow`) and shared/gangs.lua (`none`, `ballas`, `vagos`) and other resources can register more. Grades are one-based: the first grade is 1, and the default and minimum is 1. Legacy qb-core uses zero-based grades, so the legacy events and the legacy PlayerData view carry `grade.level` minus 1; modern exports always take and return the one-based value.

### Terms used on this page

| Term | Meaning |
| --- | --- |
| PlayerData.job | `{ name, label, type, payment, onduty, isboss, grade = { name, level } }`. `type` defaults to `none` (seeded: `civ`, `leo`, `ems`, `automotive`, `bodyshop`, `recovery`). `payment` and `isboss` are copied from the selected grade when the job is set. `onduty` starts as the registry job's `defaultDuty` (anything but `false` counts as on duty). `level` is the one-based grade number. |
| PlayerData.gang | `{ name, label, isboss, grade = { name, level } }`. Same grade rules as jobs; no payment or duty. |
| Registry job record | `{ name, label, type, defaultDuty, offDutyPay, blip?, grades = { { name, payment, isboss? }, ... } }`. `grades` is a one-based array (a legacy zero-keyed map is converted on registration). `blip` is not copied to PlayerData.job; read it from the registry. A grade number past the end of the list falls back to grade 1's name, payment and `isboss`, but `grade.level` keeps the requested number. |
| Registry gang record | `{ name, label, grades = { { name, isboss? }, ... } }`. |
| Job type | A service group copied from the job (`leo`, `ems`, ...). Indexed separately so one query reaches every job of that type. |

### GlobalState.OnDuty

A table mapping name to the number of on-duty players, for example `{ police = 1, leo = 2 }`. It holds both job names and job types. Entries with a count of 0 are absent, except that when a job type has the same name as a registered job, that name always reports the job's own count (including 0). Updates are coalesced: any burst of changes (`setJob` is a remove plus an add) publishes one new table 100 ms after the first change. Core always assigns a whole new table because mutating a GlobalState table in place does not replicate. Read it on either side as `GlobalState.OnDuty.police or 0`.

The index and counters are maintained inline by `setJob` and `setJobDuty`, seeded on `kora_core:server:playerLoaded`, cleared on `kora_core:server:playerDropped` and `QBCore:Server:OnPlayerUnload`, and reconciled by a subscriber on the `job` path for writes that bypass these exports (legacy `SetJobData`). Every 5 minutes (and once 2 seconds after the resource starts, to cover restarts with players online) the whole index and counters are discarded and rebuilt from PlayerData; if anything drifted the difference is printed as `[Core.jobs] on-duty counts drifted, corrected.`.

### Events fired by job, gang and duty changes

`setJob` fires local `QBCore:Server:OnJobUpdate(src, legacyJob)` and `QBCore:Server:OnPlayerUpdated(src, 'job', legacyJob)`; `setGang` fires `QBCore:Server:OnGangUpdate(src, legacyGang)` and `QBCore:Server:OnPlayerUpdated(src, 'gang', legacyGang)`. `setJobDuty` fires local `QBCore:Server:SetDuty(src, onDuty)`, sends `QBCore:Client:SetDuty(onDuty)` to the player, and then fires the same two job-update events as `setJob`. The legacy payload has a zero-based `grade.level` and gains `grade.payment` and `grade.isboss` where missing.

`Config.compat.jobUpdateEventSource` (default `client`) chooses who emits the client-side events. With `client` only the local replication layer fires `QBCore:Client:OnJobUpdate` and `QBCore:Client:OnGangUpdate`. With `server` or `both` the server also sends `QBCore:Client:OnJobUpdate(legacyJob)` / `QBCore:Client:OnGangUpdate(legacyGang)` and `QBCore:Client:OnPlayerUpdated('job'|'gang', legacy)` itself; use `both` only if listeners tolerate duplicates. The offline setters fire no events.

### Paycheck

The loop starts automatically when kora_core starts. Every `Config.jobs.paycheckInterval` ms (default 300000, 5 minutes; read before each wait, and the first payment comes one full interval after start) it pays each online player with a job, in a pcall so an error cannot kill the loop. On-duty players receive `PlayerData.job.payment` (the grade pay captured when the job was set) if it is a number above 0. Off-duty players receive the registry job's `offDutyPay` if it is a number above 0; `false` (the default for all seeded jobs) means no off-duty pay. Jobs missing from the registry are skipped. Payment is `addMoney(src, Config.money.cashType, amount, 'paycheck')`, so it is subject to the transaction tax and the physical-cash provider. `startPaycheck` while running is a no-op; `stopPaycheck` takes effect at the next wake-up (at most one interval of delay before the thread exits, and no further tick runs).

### Dispatch

`alert` collects the on-duty members of every job in `payload.jobs` (a player listed under several jobs is notified once), sends them the client event `kora_core:client:dispatchAlert(payload)`, then fires the local server event `kora_core:server:dispatchAlert(payload, count)` once so an MDT or dispatch resource can record the incident without logging once per recipient. kora_core registers no client handler for the alert; a dispatch resource consumes it. The send is per recipient, not a broadcast, so the alert contents only reach the intended roster.

When `Config.dispatch.legacyEvents` is true (default) the stock events are also fired for the listed legacy jobs:

### Functions

Job and gang records are described in the key terms below. `setJob`, `setGang` and `setJobDuty` act on online players. The offline variants write the database and yield.

#### `exports.kora_core:getJob(src)`

Reads the player's current job record (see PlayerData.job).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |

**Returns**

- **job** — table `{ name, label, type, payment, onduty, isboss, grade = { name, level } }`, one-based `grade.level`.
- **nil** — player not loaded.

**Example**

```lua
local job = exports.kora_core:getJob(src)
if not job or job.name ~= 'police' or not job.onduty then return end
```

**Representative console output**

```text
{ name = 'police', label = 'Law Enforcement', type = 'leo', payment = 75, onduty = true, isboss = false, grade = { name = 'Officer', level = 2 } }
```

#### `exports.kora_core:getGang(src)`

Reads the player's current gang record.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |

**Returns**

- **gang** — table `{ name, label, isboss, grade = { name, level } }`.
- **nil** — player not loaded.

**Example**

```lua
local gang = exports.kora_core:getGang(src)
if gang and gang.name == 'ballas' then print('member') end
```

**Representative console output**

```text
{ name = 'ballas', label = 'Ballas', isboss = false, grade = { name = 'Soldier', level = 2 } }
```

#### `exports.kora_core:setJob(src, name, grade?)`

Assigns a job to an online player. Replaces the whole `job` record in one write (grade pay, `isboss` and `type` come from the registry), resets duty to the job's `defaultDuty`, updates the job index and on-duty counters, and fires the job-update events.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `name` | string | Registry job name. |
| `grade?` | integer | One-based grade. Non-numbers become 1; values are floored and clamped to a minimum of 1. Default 1. |

**Returns**

- **true** — job set.
- **false** — second return value is the reason: 'no such player'.
- **false, 'unknown job'** — not in the registry.
- **false, &lt;setPath reason>** — e.g. 'player logout is in progress', 'player data is busy'.

**Example**

```lua
local ok, err = exports.kora_core:setJob(src, 'police', 2)
if not ok then print(('setJob failed: %s'):format(err)) end
```

**Representative console output**

```text
true  -- QBCore:Server:OnJobUpdate fired with grade.level = 1 (legacy zero-based)
```

#### `exports.kora_core:setGang(src, name, grade?)`

Assigns a gang to an online player and fires the gang-update events.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `name` | string | Registry gang name. |
| `grade?` | integer | One-based grade, same clamping as `setJob`. Default 1. |

**Returns**

- **true** — gang set.
- **false** — second return value is the reason: 'no such player'.
- **false** — second return value is the reason: 'unknown gang'.
- **false** — second return value is the reason: &lt;setPath reason>.

**Example**

```lua
local ok, err = exports.kora_core:setGang(src, 'vagos', 3)
if not ok then print(err) end
```

**Representative console output**

```text
true
```

#### `exports.kora_core:setJobDuty(src, onDuty)`

Sets only the `onduty` flag of the current job, updates the on-duty index and counters, and fires `QBCore:Server:SetDuty` / `QBCore:Client:SetDuty` plus the job-update events. The events fire even if the value did not change. It does not check that the job allows duty.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `onDuty` | boolean | Coerced to a boolean (any truthy value is on duty). |

**Returns**

- **true** — duty written.
- **false** — player not loaded (no reason string is returned in this case).
- **false, &lt;setPath reason>** — the write was refused.

**Example**

```lua
RegisterNetEvent('myjob:server:toggleDuty', function()
    local src = source
    local job = exports.kora_core:getJob(src)
    if not job or job.name ~= 'police' then return end
    exports.kora_core:setJobDuty(src, not job.onduty)
end)
```

**Representative console output**

```text
true
```

#### `exports.kora_core:setOfflineJob(citizenid, name, grade?)`

Writes a job to a stored character who is not online. Yields (database read then write). Only the `job` column is updated; no events fire and no indexes change. For an online player use `setJob` (this returns `player is online`).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `citizenid` | string | Citizen id. |
| `name` | string | Registry job name. |
| `grade?` | integer | One-based grade, clamped to a minimum of 1. Default 1. |

**Returns**

- **true** — saved.
- **false** — second return value is the reason: 'unknown job'.
- **false, &lt;load reason>** — 'invalid citizenid', 'player data is busy', 'not found', or another persistence reason.
- **false, &lt;save reason>** — 'player is online', 'player data is busy', 'could not save offline player', 'player not found'.

**Example**

```lua
CreateThread(function()
    local ok, err = exports.kora_core:setOfflineJob('AB12CD34', 'mechanic', 1)
    if not ok then print(('offline job failed: %s'):format(err)) end
end)
```

**Representative console output**

```text
true
```

#### `exports.kora_core:setOfflineGang(citizenid, name, grade?)`

Writes a gang to a stored character who is not online. Yields. Same behaviour and failure reasons as `setOfflineJob`, with the gang registry.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `citizenid` | string | Citizen id. |
| `name` | string | Registry gang name. |
| `grade?` | integer | One-based grade. Default 1. |

**Returns**

- **true** — saved.
- **false** — second return value is the reason: 'unknown gang'.
- **false, &lt;load reason> or &lt;save reason>** — as for `setOfflineJob`.

**Example**

```lua
CreateThread(function()
    local ok, err = exports.kora_core:setOfflineGang('AB12CD34', 'none')
    if not ok then print(err) end
end)
```

**Representative console output**

```text
true
```

#### `exports.kora_core:getPlayersByJob(name, onDutyOnly?)`

Source ids of online players holding a job, from the maintained index (no scan).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Job name. |
| `onDutyOnly?` | boolean | When true, only on-duty players. Default off (all holders). |

**Returns**

- **sources** — array of integers in no particular order; an empty array when none.

**Example**

```lua
local officers = exports.kora_core:getPlayersByJob('police', true)
print(('%d officers on duty'):format(#officers))
```

**Representative console output**

```text
2 officers on duty
```

#### `exports.kora_core:getPlayersByJobType(jobType, onDutyOnly?)`

Source ids of online players whose job carries a type (`leo`, `ems`, ...), across every job that declares it.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `jobType` | string | Job type. |
| `onDutyOnly?` | boolean | When true, only on-duty players. Default off. |

**Returns**

- **sources** — array of integers; empty when none.

**Example**

```lua
for _, src in ipairs(exports.kora_core:getPlayersByJobType('leo', true)) do
    TriggerClientEvent('myalert:client:notify', src, 'Bank alarm')
end
```

**Representative console output**

```text
{ 3, 7, 12 }
```

#### `exports.kora_core:getDutyCount(name)`

Live number of on-duty players for a job (the counter behind `GlobalState.OnDuty`).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Job name. |

**Returns**

- **count** — integer, 0 when none or unknown.

**Example**

```lua
if exports.kora_core:getDutyCount('police') < 2 then return end
```

**Representative console output**

```text
2
```

#### `exports.kora_core:getDutyCountByType(jobType)`

Live number of on-duty players whose job has the given type.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `jobType` | string | Job type. |

**Returns**

- **count** — integer, 0 when none or unknown.

**Example**

```lua
local medics = exports.kora_core:getDutyCountByType('ems')
```

**Representative console output**

```text
1
```

#### `exports.kora_core:getJobTypeCounts(onDutyOnly?)`

Every job type currently held by an online player with how many players hold it, so a UI can list the services that exist right now.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `onDutyOnly?` | boolean | When true, count on-duty players only. Default off (all holders). |

**Returns**

- **counts** — table `{ [jobType] = n }`; types with 0 players are omitted, so it can be empty.

**Example**

```lua
for jobType, n in pairs(exports.kora_core:getJobTypeCounts(true)) do
    print(('%s: %d on duty'):format(jobType, n))
end
```

**Representative console output**

```text
leo: 2 on duty
ems: 1 on duty
```

#### `exports.kora_core:getOnDutyRoster(filter?)`

On-duty players as descriptive records, resolved once instead of each consumer looping `getPlayersByJob` and reading PlayerData. Uses the narrowest index available (job, then job type, else all).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `filter?` | table | `{ job?: string, jobType?: string, onDutyOnly?: boolean }`. `onDutyOnly` defaults to true (pass `false` to include off-duty players). Giving both `job` and `jobType` requires both to match. No filter returns every on-duty player. |

**Returns**

- **roster** — array of `{ src, citizenid, name, callsign, job, jobLabel, jobType, grade, gradeLabel, onDuty }`. `name` is the trimmed `firstname lastname`, `callsign` is `metadata.callsign` or nil, `jobType` defaults to `none`, `grade` is the one-based level (1 if missing), `gradeLabel` is the grade name (`Grade` if missing). Empty array when nothing matches. A source whose handle has just gone is skipped.

**Example**

```lua
local roster = exports.kora_core:getOnDutyRoster({ jobType = 'leo' })
for _, unit in ipairs(roster) do
    print(('%s [%s] %s'):format(unit.name, unit.callsign or '-', unit.gradeLabel))
end
```

**Representative console output**

```text
Jane Doe [A-12] Sergeant
```

#### `exports.kora_core:alert(payload)`

Sends a job-aware alert to the on-duty members of the listed jobs, fires the server mirror event and, when enabled, the legacy police/ambulance events. Throws (assert) if the payload is invalid, so wrap it in pcall if the payload is not trusted.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `payload` | table | `{ jobs = string[] (required, non-empty array of job names), title?, message?, coords? ({x,y,z} or vector), code?, blip? ({ sprite, color, scale, duration }), sound?, radius?, data? }`. Only `jobs` is validated and only `message`, `title` and `coords` are read by core (for the legacy events); everything is passed through untouched to the client event. |

**Returns**

- **count** — integer number of distinct players notified (0 if no one is on duty).
- **error** — raised with the text 'Core.dispatch.alert requires payload.jobs as a non-empty array.' when `payload` is not a table or `payload.jobs` is not a non-empty array.

**Example**

```lua
local count = exports.kora_core:alert({
    jobs = { 'police', 'sheriff' },
    title = 'Robbery in progress',
    message = '10-90 at Fleeca Bank',
    coords = vec3(149.4, -1040.2, 29.4),
})
print(('alert reached %d units'):format(count))
```

**Representative console output**

```text
alert reached 3 units
```

#### `exports.kora_core:startPaycheck()`

Starts the paycheck loop (it already starts when kora_core starts). Calling it while running is a no-op.

**Parameters**



**Returns**

- **nil** — no return value.

**Example**

```lua
exports.kora_core:startPaycheck()
```

**Representative console output**

```text
nil
```

#### `exports.kora_core:stopPaycheck()`

Stops the paycheck loop. The sleeping thread exits when it next wakes and runs no further tick.

**Parameters**



**Returns**

- **nil** — no return value.

**Example**

```lua
-- pause wages during a server event
exports.kora_core:stopPaycheck()
```

**Representative console output**

```text
nil
```

#### `exports.kora_core:isPaycheckRunning()`

Whether the paycheck loop is active.

**Parameters**



**Returns**

- **running** — boolean.

**Example**

```lua
print(exports.kora_core:isPaycheckRunning())
```

**Representative console output**

```text
true
```

### Common use cases

- Gating a job action on `getJob(src).name` and `.onduty`.
- Letting a dispatch resource send one alert to every law-enforcement job with `alert` or `getPlayersByJobType`.
- Showing available services in a UI with `getJobTypeCounts(true)` or `GlobalState.OnDuty`.
- Promoting an offline employee with `setOfflineJob`.
- Pausing wages with `stopPaycheck` and resuming with `startPaycheck`.

### Limits and related APIs

The job index is exact for writes through these exports and is reconciled for direct PlayerData writes, but a source can linger for up to a frame during drops. `payment` on `PlayerData.job` is a snapshot of the grade at the time the job was set; changing the registry later does not retroactively change it. `setJobDuty` fires events even when the value is unchanged. The offline setters do not fire events or update the index. `alert` sends one network event per recipient.

### Related guides

- [PlayerData and setPath](./player.md)
- [Shared job and gang registry](./registry.md)
- [Paycheck uses addMoney](./money.md)
- [Client mirror of job and gang](./replication.md)
- [Zero-based legacy grades](./compatibility.md)
- [Job and duty events](./events.md)
- [Config.jobs, Config.dispatch, Config.compat](./configuration.md)

## Client

Reads the local player's job and gang from the replicated client mirror. No network call is made.

Namespace: `exports.kora_core` · Source: `modules/jobs/client.lua`

### How it works

Both exports return the live reference held by the replication mirror (read-only by convention). They return the modern one-based `grade.level`, not the legacy zero-based value that `QBCore:Client:OnJobUpdate` carries. The client cannot set a job; use the server exports.

### Functions

Functions exported by this realm.

#### `exports.kora_core:getJob()`

Local player's job record from the mirror.

**Parameters**



**Returns**

- **job** — table `{ name, label, type, payment, onduty, isboss, grade = { name, level } }`.
- **nil** — the mirror has not been received yet (before the player is loaded).

**Example**

```lua
local job = exports.kora_core:getJob()
if job and job.type == 'leo' and job.onduty then
    print('on duty as law enforcement')
end
```

**Representative console output**

```text
{ name = 'police', type = 'leo', onduty = true, grade = { name = 'Officer', level = 2 }, ... }
```

#### `exports.kora_core:getGang()`

Local player's gang record from the mirror.

**Parameters**



**Returns**

- **gang** — table `{ name, label, isboss, grade = { name, level } }`.
- **nil** — the mirror has not been received yet.

**Example**

```lua
local gang = exports.kora_core:getGang()
print(gang and gang.name or 'none')
```

**Representative console output**

```text
ballas
```

### Related guides

- [Client mirror](./replication.md)
- [Client PlayerData access](./player.md)

## Implementation notes and quick reference

Jobs and gangs are records in the `jobs` and `gangs` [shared registries](./registry.md).
A player's `job` and `gang` roots are built from the registry record and the grade,
and every change goes through the player funnel.

### Job and gang records

```lua
exports.kora_core:registerShared('jobs', 'security', {
    label = 'Security',
    type = 'security',       -- service grouping used by the type index (default 'none')
    defaultDuty = false,     -- onduty value given on setJob
    offDutyPay = false,      -- number pays while off duty; false pays nothing
    grades = {               -- array, index 1 is the lowest grade
        { name = 'Guard', payment = 40 },
        { name = 'Supervisor', payment = 70, isboss = true },
    },
})
```

- Grades are one-based in native APIs. Stock qb-core style tables keyed `'0'`,
  `'1'`, ... are converted to an ordered array when registered (the legacy
  `QBCore.Shared.Jobs`/`Gangs` views convert back to zero-based keys).
- Extra fields (for example `blip`) stay in the registry and are not copied to
  PlayerData.
- An unknown grade falls back to grade 1.

The built-in records are listed on the [Items](../items.md#jobs-and-gangs) page.

### Player job and gang shape

```lua
-- PlayerData.job
{ name = 'police', label = 'Law Enforcement', type = 'leo', payment = 75,
  onduty = false, isboss = false, grade = { name = 'Officer', level = 2 } }

-- PlayerData.gang
{ name = 'ballas', label = 'Ballas', isboss = false, grade = { name = 'Associate', level = 1 } }
```

### Server API

| Export | Returns | Description |
| --- | --- | --- |
| `getJob(src)` | table or `nil` | Live job table. Treat as read-only. |
| `getGang(src)` | table or `nil` | Live gang table. Treat as read-only. |
| `setJob(src, name, grade)` | `true` or `false, err` | Replaces the job (one-based grade, default 1); `onduty` comes from the job's `defaultDuty`. Errors: `no such player`, `unknown job`. |
| `setGang(src, name, grade)` | `true` or `false, err` | Replaces the gang. Errors: `no such player`, `unknown gang`. |
| `setJobDuty(src, onDuty)` | `true` or `false, err` | Sets `job.onduty`. |
| `setOfflineJob(citizenid, name, grade)` | `true` or `false, err` | Yields. Writes only the `job` column of an offline character. |
| `setOfflineGang(citizenid, name, grade)` | `true` or `false, err` | Yields. Writes only the `gang` column of an offline character. |
| `getPlayersByJob(name, onDutyOnly)` | integer array | Sources holding the job, from a maintained index. |
| `getPlayersByJobType(jobType, onDutyOnly)` | integer array | Sources whose job has this `type` (for example `leo`, `ems`). |
| `getDutyCount(name)` | integer | On-duty count for a job. |
| `getDutyCountByType(jobType)` | integer | On-duty count for a job type. |
| `getJobTypeCounts(onDutyOnly)` | map | `[jobType] = count`; zero counts omitted. |
| `getOnDutyRoster(filter)` | array | Descriptive records, see below. |

```lua
local units = exports.kora_core:getOnDutyRoster({ jobType = 'leo' })
for _, unit in ipairs(units) do
    print(unit.callsign or unit.name, unit.jobLabel, unit.gradeLabel)
end
```

`getOnDutyRoster(filter)` accepts `job`, `jobType` and `onDutyOnly` (default `true`);
with both `job` and `jobType` a player must match both. Each record has `src`,
`citizenid`, `name`, `callsign` (from `metadata.callsign`), `job`, `jobLabel`,
`jobType`, `grade` (one-based), `gradeLabel` and `onDuty`.

Client exports `getJob()` and `getGang()` read the local mirror.

#### Events

`setJob` and `setJobDuty` fire `QBCore:Server:OnJobUpdate(src, job)` and
`QBCore:Server:OnPlayerUpdated(src, 'job', job)`; `setGang` fires
`QBCore:Server:OnGangUpdate` and `OnPlayerUpdated(src, 'gang', gang)`. The payload is
the legacy view (zero-based `grade.level`, `grade.payment`, `grade.isboss`).
`setJobDuty` also fires `QBCore:Server:SetDuty(src, onDuty)` and the client event
`QBCore:Client:SetDuty(onDuty)`. Client-side job/gang events follow
`Config.compat.jobUpdateEventSource`.

#### Duty index and GlobalState

The job and job-type indexes are updated inline by `setJob`/`setJobDuty`, seeded at
login and cleared on unload and drop. A subscription on the `job` path catches
writes that bypass those functions. The indexes are rebuilt from connected players
two seconds after start and every five minutes, and drift is printed.

`GlobalState.OnDuty` publishes on-duty counts (updates coalesced over 100 ms).
Keys are job names and job types. A registered job name wins over a job type with
the same name. Missing keys mean zero:

```lua
local cops = (GlobalState.OnDuty or {}).police or 0
```

#### Duty toggle from clients

The legacy client event `QBCore:ToggleDuty` (when `Config.compat.toggleDutyEvent`
is on) flips duty for the sender, with a 2 s cooldown, and is refused for the
default job. It notifies `You are now on duty!` or `You are now off duty!`.

### Paychecks

A server loop started with the resource runs every `Config.jobs.paycheckInterval`:

- On duty: `job.payment` (the grade's payment) if it is a number above 0.
- Off duty: the job record's `offDutyPay` if it is a number above 0.
- Paid with `addMoney(src, Config.money.cashType, amount, 'paycheck')`.
- Errors in a tick are printed and do not stop the loop.

| Export | Description |
| --- | --- |
| `startPaycheck()` | Start the loop (no-op if running). Called automatically on start. |
| `stopPaycheck()` | Stop the loop. |
| `isPaycheckRunning()` | Whether the loop is running. |

### Dispatch alerts

```lua
local recipients = exports.kora_core:alert({
    jobs = { 'police' },
    title = '10-80',
    message = 'Robbery in progress',
    coords = coords,
    code = '10-80',
    blip = { sprite = 161, color = 1, scale = 1.0, duration = 60 },
    sound = 'alert',
    radius = 50.0,
    data = { store = 'ltd_grove' },
})
```

`alert(payload)` sends `kora_core:client:dispatchAlert(payload)` once to every
on-duty member of each job in `payload.jobs` (required, non-empty; the call asserts
otherwise) and returns the number of distinct recipients. It then fires the server
event `kora_core:server:dispatchAlert(payload, recipientCount)` once, which is the
hook for a resource that keeps a call log. kora_core does not render anything; the
fields other than `jobs` are passed through for the receiving resource.

With `Config.dispatch.legacyEvents`, a `police` alert also fires the server event
`police:server:policeAlert(message)` and the client event
`police:client:policeAlert(coords, message)` to each recipient; `ambulance` and
`ems` alerts send `hospital:client:ambulanceAlert(coords, message)`. `message` falls
back to `title`.
