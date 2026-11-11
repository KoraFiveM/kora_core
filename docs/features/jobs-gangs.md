---
title: Jobs, gangs, duty and dispatch
sidebar_position: 3
---

# Jobs, gangs, duty and dispatch

Jobs and gangs are records in the `jobs` and `gangs` [shared registries](./shared-registries.md).
A player's `job` and `gang` roots are built from the registry record and the grade,
and every change goes through the player funnel.

## Job and gang records

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

## Player job and gang shape

```lua
-- PlayerData.job
{ name = 'police', label = 'Law Enforcement', type = 'leo', payment = 75,
  onduty = false, isboss = false, grade = { name = 'Officer', level = 2 } }

-- PlayerData.gang
{ name = 'ballas', label = 'Ballas', isboss = false, grade = { name = 'Associate', level = 1 } }
```

## Server API

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

### Events

`setJob` and `setJobDuty` fire `QBCore:Server:OnJobUpdate(src, job)` and
`QBCore:Server:OnPlayerUpdated(src, 'job', job)`; `setGang` fires
`QBCore:Server:OnGangUpdate` and `OnPlayerUpdated(src, 'gang', gang)`. The payload is
the legacy view (zero-based `grade.level`, `grade.payment`, `grade.isboss`).
`setJobDuty` also fires `QBCore:Server:SetDuty(src, onDuty)` and the client event
`QBCore:Client:SetDuty(onDuty)`. Client-side job/gang events follow
`Config.compat.jobUpdateEventSource`.

### Duty index and GlobalState

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

### Duty toggle from clients

The legacy client event `QBCore:ToggleDuty` (when `Config.compat.toggleDutyEvent`
is on) flips duty for the sender, with a 2 s cooldown, and is refused for the
default job. It notifies `You are now on duty!` or `You are now off duty!`.

## Paychecks

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

## Dispatch alerts

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
