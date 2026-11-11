# Stock `player_vehicles` compatibility

kora's `player_vehicles` (`modules/persistence/schema.lua`) stays authoritative and
declares the stock qb-garages / qb-vehicleshop columns too. Two `BEFORE INSERT/UPDATE`
triggers (installed at boot by `modules/persistence/boot.lua`,
`kora_core_player_vehicles_compat_insert` and `_update`) keep the pairs in sync.

| kora column | stock column | notes |
|---|---|---|
| `model` | `vehicle` | both nullable, so an insert naming only one works |
| `garage_id` | `garage` | `NULL` is preserved both ways |
| `engine_health` (int 0-65535) | `engine` (float) | stock -> kora is rounded (half-even for FLOAT) and clamped to 0..65535 |
| `body_health` | `body` | same |
| `fuel`, `mods`, `plate`, `citizenid` | same | shared as-is |
| - | `license`, `hash`, `fakeplate`, `depotprice`, `drivingdistance`, `status` | plain pass-through columns (not synced; `license` is not auto-filled) |
| `balance`, `paymentamount`, `paymentsleft`, `financetime` | same | shared as-is |

Conflict rule: when one statement changes both sides, kora's column wins. An
update that touches neither side leaves values (and float precision) alone.

## How it is applied
The columns are declared in `modules/persistence/schema.lua` and created by
`Kora.sql.ensureTables`. `boot.lua` then installs the two triggers (checked against
`information_schema` first, so every boot is a no-op once they exist). Nothing is
converted or backfilled: a `player_vehicles` table imported from stock qb-core is not
reshaped (no nullability changes, no value copies, no `state` conversion).

## `state`
kora uses `state ENUM('out','garaged','impounded')` and every kora writer and reader
(kora_garages, kora_dealership, `Core.garage`) uses the strings. Stock uses an integer
(0 out, 1 garaged, 2 impounded). One column cannot be both: an integer written to an
ENUM is its 1-based *index*, so it is not translated by a trigger. On a fresh kora
install stock integer-state scripts are therefore not supported.

## Database support
`ADD COLUMN IF NOT EXISTS` is not used by the schema handler, but the triggers and
generated columns assume **MariaDB (10.2+; tested on 11.8)**.

## Testing
`bash test/run.sh` runs `test/smoke/vehicle_compat_sql.lua` (schema declaration, trigger
text, no migration at boot).

# Legacy money / duty / metadata writes (compat)
- `Functions.SetPlayerData('money', t)` and `UpdateClient('money')` while
  kora_inventory owns cash: the cash entry is applied as a *delta against the
  PlayerData view the script saw* (the ledger value, always 0 under physical
  cash) through `Core.money.addMoney/removeMoney` (reason
  `qb-compat-setplayerdata`, untaxed). Writing the table back unchanged leaves
  cash alone. A removal larger than the real balance refuses the whole write and
  logs. `Functions.SetMoney('cash', x)` sets the item-backed balance.
- `QBCore:ToggleDuty` is registered when `Config.compat.toggleDutyEvent` (default
  true): needs a non-default job, 2 s per-player cooldown, fires SetDuty events.
- `Config.compat.clientMetadataKeys` defaults to hunger/thirst/stress, numeric and
  clamped to 0..100. Everything else stays server-only.
