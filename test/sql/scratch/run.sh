#!/usr/bin/env bash
# Applies kora_core's migration chain exactly as kora_sql's runner does (its
# splitStatements + retry-safety check are reused from the sibling kora_sql repo)
# and runs the REAL modules/persistence/migrate.lua boot steps against scratch
# MariaDB databases, then the assertion files. Creates and drops only databases
# named compat_scratch_*. Needs: node, lua, a MariaDB reachable as `$MARIADB`
# (default `sudo mariadb`, unix socket) and ../kora_sql next to kora_core.
# Run from the kora_core directory:  bash test/sql/scratch/run.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
export MARIADB="${MARIADB:-sudo mariadb}"
export KORA_SQL_DIR="${KORA_SQL_DIR:-$PWD/../kora_sql}"
S=test/sql/scratch; T=test/sql
db() { echo "compat_scratch_$1"; }
newdb() { $MARIADB -e "DROP DATABASE IF EXISTS $(db "$1"); CREATE DATABASE $(db "$1")"; }
sql() { local d; d=$(db "$1"); shift; $MARIADB "$d" "$@"; }
run() { local d; d=$(db "$1"); shift; for f in "$@"; do echo "-- $d: $f"; $MARIADB "$d" < "$f"; done; }
boot() { lua "$S/boot.lua" "$(db "$1")" "${2:-}"; }
cleanup() { for s in a a2 b b2 c; do $MARIADB -e "DROP DATABASE IF EXISTS $(db $s)"; done; }
trap cleanup EXIT

echo "== (a) fresh install, default config"
newdb a
MAX_VERSION=10 node "$S/apply.js" "$(db a)" sql >/dev/null
sql a -e "INSERT INTO player_vehicles (plate, model, vehicle, citizenid, garage_id, engine_health, body_health, state)
  VALUES ('OLD1', 'adder', 'adder', 'ABC', 'legion', 800, 700, 'out')"
boot a
boot a   # second boot must be a no-op
run a $T/player_vehicles_compat.sql $T/player_vehicles_seed_kora.sql $T/player_vehicles_state_kora_enum.sql

echo "== (a2) fresh install, legacyVehicleState = true"
newdb a2
MAX_VERSION=10 node "$S/apply.js" "$(db a2)" sql >/dev/null
sql a2 -e "INSERT INTO player_vehicles (plate, model, vehicle, citizenid, garage_id, engine_health, body_health, state)
  VALUES ('OLD1', 'adder', 'adder', 'ABC', 'legion', 800, 700, 'out')"
boot a2 legacyState
boot a2 legacyState
run a2 $T/player_vehicles_compat.sql $T/player_vehicles_seed_kora.sql $T/player_vehicles_state_converted.sql
sql a2 -e "SELECT 1/(state = 'out') FROM player_vehicles WHERE plate = 'OLD1'" >/dev/null   # pre-existing 'out' survived the reorder

echo "== (b) stock qb-core table imported first, default config"
newdb b
sql b < $S/stock_qbcore_player_vehicles.sql
boot b
boot b
run b $T/player_vehicles_compat.sql $T/player_vehicles_seed_stock.sql $T/player_vehicles_state_stock_int.sql

echo "== (b2) stock table with NOT NULL vehicle/engine/body (older dumps)"
newdb b2
sql b2 < $S/stock_qbcore_player_vehicles.sql
sql b2 -e "ALTER TABLE player_vehicles MODIFY vehicle varchar(50) NOT NULL, MODIFY engine float NOT NULL DEFAULT 1000, MODIFY body float NOT NULL DEFAULT 1000"
boot b2
run b2 $T/player_vehicles_compat.sql $T/player_vehicles_seed_stock.sql $T/player_vehicles_state_stock_int.sql

echo "== (c) stock table, legacyVehicleState = true"
newdb c
sql c < $S/stock_qbcore_player_vehicles.sql
boot c legacyState
boot c legacyState
run c $T/player_vehicles_compat.sql $T/player_vehicles_seed_stock.sql $T/player_vehicles_state_converted.sql
sql c -N -e "SELECT plate, state FROM player_vehicles WHERE plate IN ('LEG1','LEG2','LEG3') ORDER BY plate" | tr '\n' ' '
echo
sql c -e "SELECT 1/(SUM(plate='LEG1' AND state='garaged') = 1 AND SUM(plate='LEG2' AND state='out') = 1 AND SUM(plate='LEG3' AND state='impounded') = 1) FROM player_vehicles" >/dev/null
echo "ALL SCENARIOS OK"
