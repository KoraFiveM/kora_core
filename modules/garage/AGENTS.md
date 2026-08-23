# garage module guide

## Purpose
SQL-persisted vehicle ownership: civilian garage (store/retrieve) and job duty-fleet vehicles share one `player_vehicles` table (see `sql/005_vehicles.sql`), distinguished by whether `citizenid` or `job` is set on a row (by convention, not enforced at the SQL level — a row is expected to have exactly one of the two). Server only.

## Public API
- `Core.garage.createVehicle(citizenid, model, plate, job, extra)` — inserts a row. Exactly one of `citizenid`/`job`. `extra = {fuel?, engineHealth?, bodyHealth?}`.
- `Core.garage.getByPlate(plate)` — one row, hydrated (`mods`/`last_position` JSON-decoded), or `nil`.
- `Core.garage.getByOwner(citizenid)` — all non-deleted rows for a citizen, hydrated.
- `Core.garage.storeVehicle(plate, snapshot)` — marks `garaged`, updates condition columns present in `snapshot`. Refuses an impounded vehicle.
- `Core.garage.spawnVehicle(src, plate, coords, heading)` — spawns a real, networked entity, marks `out`. Refuses an impounded vehicle. Returns a network id.
- `Core.garage.impound(plate, fee, impoundLot)` — marks `impounded`.
- `Core.garage.retrieveImpound(src, plate)` — clears the impound flag. Ownership-checked for civilian rows.
- `Core.garage.updateState(plate, patch)` — partial condition update, for periodic autosave of a vehicle that's currently `out`. Unlike `storeVehicle`, does not change `state` or refuse an impounded vehicle.
- `Core.garage.deleteVehicle(plate)` — soft-delete (`deleted_at`).

## Implementation notes
- **`spawnVehicle` uses the raw `CreateVehicle` native, never `QB.entities`** — qblib's entity spawner is explicitly local/non-networked, but a duty or owned vehicle must be visible to every player, not just the one who spawned it.
- **`mods` are opaque JSON, not auto-applied.** Stored/returned as-is; applying them to a spawned vehicle is ~50 `SetVehicleMod` calls of presentation-layer work belonging to whichever job/garage UI wants a tuning system, not to a generic persistence primitive. `fuel`/`engine`/`body` health ARE applied on spawn, since that's cheap and universally wanted.
- **`storeVehicle`/`updateState` both `COALESCE` against the existing column** — an omitted `snapshot`/`patch` field leaves the stored value unchanged rather than nulling it.
- **Payment is the caller's responsibility.** `retrieveImpound` clears the impound flag but does not charge the fee — call `Core.money.removeMoney` before calling this, same reasoning `Core.jobs` leaves payment amounts to `Core.money` rather than moving cash itself.
- **Ownership check only applies to civilian rows.** A job-fleet row (`citizenid` unset) has no per-player ownership to check in `retrieveImpound` — any on-duty member retrieving it is a job-resource-level policy decision, not this module's.
- **Soft delete**, same convention `players`/character rows use (`deleted_at`, filtered out of `getByPlate`/`getByOwner`).

## Best practices
- Call `updateState` for periodic autosave of an out vehicle's condition; reserve `storeVehicle` for the actual store action (it also flips `state` to `garaged`).
- Charge/refund money before calling `impound`/`retrieveImpound` — this module never touches `Core.money` itself.
