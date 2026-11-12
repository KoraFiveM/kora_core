# jobs module guide

## Purpose
Job / gang / duty mutation over the funnel, plus a maintained reverse index (`jobName → {src set}`) so "who has this job" is O(1). Server owns mutation and the index; the client reads job/gang from the replicated mirror.

## Public API
Server:
- `Core.jobs.getJob(src)` / `getGang(src)` — the sub-table or `nil`.
- `Core.jobs.setJob(src, name, grade)` / `setGang(src, name, grade)` — set to a registered job/gang. `(true)` / `(false, err)`.
- `Core.jobs.setOfflineJob(citizenid, name, grade)` / `setOfflineGang(citizenid, name, grade)` — persist the one changed role column with native one-based grades.
- `Core.jobs.setJobDuty(src, onDuty)` — toggle duty.
- `Core.jobs.getPlayersByJob(name, onDutyOnly)` — source ids via the index (O(1)).
- `Core.jobs.getDutyCount(name)` — on-duty count.

Client:
- `Core.jobs.getJob()` / `getGang()` — read `{ 'job' }` / `{ 'gang' }` from the mirror.

## Implementation notes
- **The maintained O(1) index is the point.** `byJob[name] = {[src]=true}` and `byJobOnDuty[name] = {[src]=true}` are kept current so `getPlayersByJob` / `getDutyCount` are set reads. Legacy qb-core scans every player on each call (dispatch, paycheck ticks, boss menus hit this constantly) — the index turns that O(n) scan into O(1).
- **Index maintenance hooks the lifecycle, not `onChange`.** A `Core.player.onChange({'job'}, …)` subscriber would fire on `setJob`'s own funnel write and double-count. Instead: seed on `kora_core:server:playerLoaded` (`indexAdd`), sweep on `kora_core:server:playerDropped` (remove the src from every set, defensively, since the handle may already be gone), and update inline inside `setJob`/`setJobDuty` (remove old job set membership before adding new). `setGang` doesn't touch the index (no gang index is maintained).
- **Whole-root writes.** `setJob`/`setGang` compose the full sub-table via `CoreInternal.player.buildJob`/`buildGang` (registry definition + grade) and write `{'job'}`/`{'gang'}` in one funnel call — one dirty column, one delta op carrying the whole table, rather than a write per field.
- **Registry-gated.** `setJob`/`setGang` refuse a name not present in the `jobs`/`gangs` registry.
- **Compat event routing.** Server always fires `QBCore:Server:OnJobUpdate`/`OnGangUpdate`/`SetDuty`; whether the *client* event is emitted here is gated by `Config.compat.jobUpdateEventSource` (`'client'` suppresses the server-side client emit, letting the replication module's `fireLegacy` emit it from the mirror instead) to avoid double-fire.
- **Client is read-only** and trivial — two mirror reads. All authority is server-side.
- **Internals.** `byJob`/`byJobOnDuty`/`indexAdd`/`indexRemove` are file-local. Job/gang *composition* lives on `CoreInternal.player` (shared) so both player creation and jobs use it. Internals are never exported; `build/finalise.lua` walks only `Core.<module>` and skips `_`-prefixed functions.

## Best practices
- Use `getPlayersByJob`/`getDutyCount` instead of iterating players yourself — that's the whole reason the index exists.
- Change jobs only through `setJob`/`setGang`/`setJobDuty` so the index and the funnel stay consistent; writing `PlayerData.job` directly desyncs the index.
