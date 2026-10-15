# Jobs module

## Overview
Job, gang, and duty changes, plus fast reverse lookups of who holds a job. Every change routes through the player funnel (`Core.player.setPath(src, { 'job' }, …)`), so it inherits dirty-tracking and replication and emits the legacy job/gang/duty events. A **maintained O(1) index** (job name → source set, and an on-duty-only variant) makes `getPlayersByJob` a set read rather than the O(n) scan legacy qb-core does on every dispatch/paycheck tick. Server-side owns mutation and the index; client-side reads job/gang from the mirror. Functions are defined on `Core.jobs` and exported flat as `exports.qbcore:<fn>`.

## API

### `Core.jobs.getJob(src)` — server / `Core.jobs.getJob()` — client
Server: the job sub-table for a source (or `nil`). Client: the local player's job from the mirror.

#### Parameters (server)
- `src: integer`

#### Returns
- `table | nil` — `{ name, label, payment, onduty, isboss, grade = { name, level } }`.

### `Core.jobs.getGang(src)` — server / `Core.jobs.getGang()` — client
Server: the gang sub-table for a source (or `nil`). Client: the local player's gang from the mirror.

#### Returns
- `table | nil` — `{ name, label, isboss, grade = { name, level } }`.

### `Core.jobs.setJob(src, name, grade)` — server
Sets a player's job to a registered job at `grade`, replacing the whole `job` root in one funnel write, and updates the job index. Fires `QBCore:Server:OnJobUpdate` (and the client event unless `Config.compat.jobUpdateEventSource == 'client'`).

#### Parameters
- `src: integer`
- `name: string` — Must be a registered job.
- `grade: integer | nil` — Default `0`.

#### Returns
- `boolean` — `true` on success.
- `string | nil` — Failure reason (`'no such player'`, `'unknown job'`).

#### Example
```lua
local ok, err = exports.qbcore:setJob(src, 'police', 2)
```

### `Core.jobs.setGang(src, name, grade)` — server
Sets a player's gang to a registered gang at `grade`, in one funnel write. Fires `QBCore:Server:OnGangUpdate` (and the client event per `Config.compat`).

#### Parameters
- `src: integer`
- `name: string` — Must be a registered gang.
- `grade: integer | nil` — Default `0`.

#### Returns
- `boolean`, `string | nil` — Failure reason (`'no such player'`, `'unknown gang'`).

### `Core.jobs.setJobDuty(src, onDuty)` — server
Toggles on/off duty (writes `job.onduty` through the funnel) and updates the on-duty index. Fires `QBCore:Server:SetDuty` / `QBCore:Client:SetDuty`.

#### Parameters
- `src: integer`
- `onDuty: boolean`

#### Returns
- `boolean`

### `Core.jobs.getPlayersByJob(name, onDutyOnly)` — server
Returns the source ids holding a job — **O(1)** via the maintained index, not a scan. With `onDutyOnly`, only on-duty holders.

#### Parameters
- `name: string`
- `onDutyOnly: boolean | nil`

#### Returns
- `integer[]`

#### Example
```lua
local onDutyCops = exports.qbcore:getPlayersByJob('police', true)
```

### `Core.jobs.getDutyCount(name)` — server
Returns the number of on-duty holders of a job.

#### Parameters
- `name: string`

#### Returns
- `integer`

### `Core.jobs.getPlayersByJobType(jobType, onDutyOnly)` — server
Returns the source ids whose job carries a given **type** (`'leo'`, `'ems'`,
`'recovery'`, …), across every job that declares it — **O(1)** via a second
maintained index, not a scan.

This is what a dispatch system targets: one alert reaching police, sheriff and
state troopers without the caller needing to know which job names this server
happens to define.

#### Parameters
- `jobType: string`
- `onDutyOnly: boolean | nil`

#### Returns
- `integer[]`

#### Example
```lua
local onDutyLeo = exports.qbcore:getPlayersByJobType('leo', true)
```

### `Core.jobs.getDutyCountByType(jobType)` — server
Number of on-duty players whose job carries that type.

#### Returns
- `integer`

### `Core.jobs.getJobTypeCounts(onDutyOnly)` — server
Every job type currently held by an online player, mapped to how many hold it.
Lets a UI list the services that actually exist right now instead of hard-coding
them.

#### Returns
- `table<string, integer>` — types with a zero count are omitted.

### `Core.jobs.getOnDutyRoster(filter)` — server
On-duty players as **descriptive records** rather than bare source ids — the
roster a dispatch or MDT unit list needs, resolved once here instead of every
consumer looping `getPlayersByJob` and reaching back into `PlayerData`.

#### Parameters
- `filter: table | nil`
  - `job: string | nil` — narrow to one job name.
  - `jobType: string | nil` — narrow to one service type.
  - `onDutyOnly: boolean | nil` — defaults to **`true`**.

  Passing both `job` and `jobType` requires the player to match both. With no
  filter it returns every on-duty player of every job.

#### Returns
- `{ src, citizenid, name, callsign, job, jobLabel, jobType, grade, gradeLabel, onDuty }[]`

#### Example
```lua
local units = exports.qbcore:getOnDutyRoster({ jobType = 'leo' })
for _, unit in ipairs(units) do
    print(unit.callsign or unit.name, unit.jobLabel, unit.gradeLabel)
end
```

## Notes
- **`GlobalState.OnDuty` publishes on-duty counts to clients.** Updates are
  coalesced over 100 ms. Keys are job names and job types; a registered job name
  takes precedence over an identically named type, even when that job has zero
  on-duty players. Other zero counts can be absent, so read them with `or 0`.
  Use `getDutyCountByType` server-side when you need the type total despite a
  name collision. The index is rebuilt from connected players after two seconds
  and every five minutes thereafter, correcting and logging count drift.
- **`PlayerData.job.type` is the service grouping.** `CoreInternal.player.buildJob`
  copies `type` off the registry record (defaulting to `'none'`), and
  `Core.persistence._load` backfills it for characters saved before the field
  existed. `blip` and any other extra registry field stay registry-only.
- **The index is maintained inline, with an `onChange` reconciler as a backstop.**
  It is seeded on `qbcore:server:playerLoaded`, swept on
  `qbcore:server:playerDropped`, and updated inline by `setJob`/`setJobDuty`.
  A subscription on the `job` prefix additionally catches writes that bypass
  those functions — chiefly the legacy `SetJobData('onduty', …)`, which used to
  flip duty with the index none the wiser, silently cutting that player out of
  every dispatch alert. The reconciler compares the observed job/duty against
  what the index already believes and does nothing when they agree, so it never
  double-handles `setJob`'s own write. `SetJobData('onduty', …)` is *also*
  routed through `setJobDuty` now, so the duty events still fire — something the
  reconciler cannot retrofit.
- **`setJob` replaces the whole `job` sub-table** — composed from the registry definition + grade by `CoreInternal.player.buildJob` — so it's one dirty column and one delta op carrying the whole sub-table, not a write per field.
- **Unknown job/gang is refused.** The name must exist in the `jobs`/`gangs` registry.

## Offline roles

`exports.qbcore:setOfflineJob(citizenid, name, grade)` and `setOfflineGang(citizenid, name, grade)` validate the registry name and persist only the changed role column. Grades are one-based, matching the native online setters. Both yield and return `(true)` or `(false, reason)`.
