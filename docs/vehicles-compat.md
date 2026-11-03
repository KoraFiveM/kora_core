# Stock `player_vehicles` compatibility

kora's `player_vehicles` (`modules/persistence/schema.lua`) stays authoritative. Migration
`011_legacy_vehicle_compat.sql` adds the stock qb-garages / qb-vehicleshop
columns, plus kora's own columns when the table was imported from stock qb-core
first (005 is `CREATE TABLE IF NOT EXISTS` and cannot evolve such a table). Two
`BEFORE INSERT/UPDATE` triggers (installed at boot by
`modules/persistence/migrate.lua`, `qbcore_player_vehicles_compat_insert` and
`_update`, replacing the older `..._model_sync_*` pair) keep the pairs in sync.

| kora column | stock column | notes |
|---|---|---|
| `model` | `vehicle` | both nullable, so an insert naming only one works |
| `garage_id` | `garage` | `NULL` is preserved both ways |
| `engine_health` (int 0-65535) | `engine` (float) | stock -> kora is rounded (half-even for FLOAT) and clamped to 0..65535 |
| `body_health` | `body` | same |
| `fuel`, `mods`, `plate`, `citizenid` | same | shared as-is |
| - | `license`, `hash`, `fakeplate`, `depotprice`, `drivingdistance`, `status` | plain pass-through columns (not synced; `license` is not auto-filled) |
| `balance`, `paymentamount`, `paymentsleft`, `financetime` | same | migration 007 |

Conflict rule: when one statement changes both sides, kora's column wins. An
update that touches neither side leaves values (and float precision) alone.

## How it is applied
The columns are declared in `modules/persistence/schema.lua` (`player_vehicles`
spec, applied by `Kora.sql.ensureTables`; the retired `sql/011_*.sql` lives on as a
fixture under `test/sql/scratch/legacy`). Everything else runs from `migrate.lua`
after the schema, driven by
`information_schema` (idempotent, every boot):
- relax `model`/`vehicle` to nullable and `engine`/`body` to `NULL DEFAULT NULL`
  (stock has `vehicle NOT NULL` in some dumps and `engine/body DEFAULT 1000`; a
  kora-style insert naming only `engine_health` would otherwise be rejected or
  have its health overwritten by 1000). Charset/collation is preserved;
- backfill stock <-> kora values (a stock-imported row gets `garage_id`,
  `engine_health`, `body_health` from `garage`/`engine`/`body`), pinning
  `last_updated`. The health copy runs only on the boot that creates
  `engine_health`/`body_health`; a crash between migration 011 and that
  backfill leaves those rows at the 1000 default;
- install the triggers, then the optional `state` step below.

## `state`
kora uses `state ENUM('out','garaged','impounded')` and every kora writer and
reader (kora_garages, kora_dealership, `Core.garage`) uses the strings. Stock
uses an integer (0 out, 1 garaged, 2 impounded). One column cannot be both:
an integer written to an ENUM is its 1-based *index*. It is therefore not
translated by a trigger (a trigger sees the value after coercion and cannot tell
`1` from `'out'`). `Config.persistence.legacyVehicleState` (default `false`)
selects what happens; results below were run on MariaDB 11.8 (strict mode).

| scenario | what works | what does not |
|---|---|---|
| **(a)** fresh kora install, option off (default) | every kora statement (strings); stock column/health/garage/model sync | stock `state = 1` **write lands on `'out'`** (silently inverted); stock `state = 0` write is rejected (error 1265); stock `WHERE state = 1` returns kora's `out` rows |
| **(b)** stock table imported first, `state` still INT, option off | stock scripts as before (integer writes/reads); column/health/garage/model sync; kora's missing columns are added | kora_garages, kora_dealership and `Core.garage` writes of `'out'/'garaged'` are rejected (strings into INT) and `state = 'garaged'` reads match nothing. Boot prints a warning naming the option |
| **(c)** option on (either scenario) | the column becomes `ENUM('garaged','impounded','out') NOT NULL DEFAULT 'garaged'`: all kora statements; existing data kept (INT 0/1/2 mapped explicitly to out/garaged/impounded, never via the enum index; kora's existing strings kept); stock integer `state = 1` / `2` writes and `WHERE state = 1` reads mean garaged / impounded | stock `state = 0` ("out") writes are rejected (error 1265) and `WHERE state = 0` never matches; stock `WHERE state = 2` after a kora write of `'impounded'` works, but anything that compares against `0` or expects an integer back does not |

Choosing: the option is **opt-in** because converting a stock INT column
breaks stock integer-state scripts for 0/"out" and is one-way; keeping the INT
column breaks kora's garage resources. On a stock-imported server that runs
kora_garages, set it to `true`. If stock garage scripts must keep working fully,
keep the INT column and don't run kora's garage/dealership resources against
that table. The conversion is resumable (a boot that dies between its ALTERs
continues on the next boot); a custom `state` ENUM is left alone. The ENUM
reorder only changes sort order of `ORDER BY state`; no kora code relies on it.

## Database support
The schema handler and the v111 residual migration (kora_sql's runner retry-safety
gate) rely on `ADD COLUMN IF NOT EXISTS`, which is MariaDB-only;
MySQL 8 rejects it. kora_sql's docs say only "MySQL/MariaDB" with no version
statement, but in practice **MariaDB (10.2+; tested on 11.8) is required**. The boot-time
steps added here do not add any further MariaDB-only dependency (they check
`information_schema` first). Making the file migrations MySQL-portable would
need a kora_sql runner change (not made here).

## Testing
`bash test/run.sh` runs `test/smoke/vehicle_compat_sql.lua` (schema declaration,
trigger text, runner retry-safety gate)
and `test/smoke/vehicle_compat_boot.lua` (boot-step statement sequence).
`bash test/sql/scratch/run.sh` runs the real thing on scratch MariaDB databases
`compat_scratch_*` (created and dropped by the script; needs `node`, `lua`, a
`../kora_sql` checkout and `sudo mariadb` or `MARIADB=...`): (a) fresh,
(a2) fresh + option, (b) stock table, (b2) stock table with NOT NULL columns,
(c) stock table + option, each followed by `test/sql/player_vehicles_*.sql`.

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
