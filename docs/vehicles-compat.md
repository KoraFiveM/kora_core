---
title: player_vehicles compatibility
sidebar_position: 10
---

# Stock `player_vehicles` compatibility

kora_core's `player_vehicles` table (declared in `modules/persistence/schema.lua`)
stays authoritative and also declares the stock qb-garages / qb-vehicleshop
columns. Two `BEFORE INSERT`/`BEFORE UPDATE` triggers,
`kora_core_player_vehicles_compat_insert` and
`kora_core_player_vehicles_compat_update`, keep the column pairs in sync.

| Kora column | Stock column | Notes |
| --- | --- | --- |
| `model` | `vehicle` | Both nullable, so an insert naming only one works. |
| `garage_id` | `garage` | `NULL` is preserved both ways. |
| `engine_health` (smallint 0 to 65535) | `engine` (float) | Stock to Kora is rounded and clamped to 0..65535. |
| `body_health` | `body` | Same as engine. |
| `fuel`, `mods`, `plate`, `citizenid` | same | Shared as-is. |
| none | `license`, `hash`, `fakeplate`, `depotprice`, `drivingdistance`, `status` | Plain pass-through columns, not synced (`license` is not filled automatically). |
| `balance`, `paymentamount`, `paymentsleft`, `financetime` | same | Shared as-is. |

Conflict rule: when one statement changes both sides of a pair, the Kora column
wins. An update that touches neither side leaves the values (and float precision)
alone.

## How it is applied

The columns are created by `Kora.sql.ensureTables`. The boot code then checks
`information_schema.TRIGGERS` and creates only missing triggers, so every later
boot is a no-op. Nothing is converted or backfilled: a `player_vehicles` table
imported from stock qb-core is not reshaped (no nullability changes, no value
copies, no `state` conversion). A trigger setup failure is printed and does not
stop the rest of the boot.

## state

Kora uses `state ENUM('out','garaged','impounded')`, and every Kora reader and
writer (kora_garages, kora_dealership, `Core.garage`) uses the strings. Stock uses
an integer (0 out, 1 garaged, 2 impounded). One column cannot be both: an integer
written to an ENUM is its one-based index, so it is not translated by a trigger.
Stock scripts that write integer states are therefore not supported.

## Database support

The triggers and generated columns assume MariaDB 10.2 or later.

## Testing

`bash test/run.sh` runs `test/smoke/vehicle_compat_sql.lua` (schema declaration,
trigger text, no migration at boot).
