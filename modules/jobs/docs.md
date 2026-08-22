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

## Notes
- **The index is maintained on the lifecycle, not via `onChange`.** Subscribing to the `job` prefix would double-handle `setJob`'s own write, so the index is seeded on `qbcore:server:playerLoaded` and swept on `qbcore:server:playerDropped` (defensively removing the source from every set), while `setJob`/`setJobDuty` update it inline.
- **`setJob` replaces the whole `job` sub-table** — composed from the registry definition + grade by `CoreInternal.player.buildJob` — so it's one dirty column and one delta op carrying the whole sub-table, not a write per field.
- **Unknown job/gang is refused.** The name must exist in the `jobs`/`gangs` registry.
