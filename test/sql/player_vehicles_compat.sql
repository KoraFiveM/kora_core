-- Behavioural test for sql/011_legacy_vehicle_compat.sql + the compat triggers.
-- Runs against a database that kora's migration chain has ALREADY been applied to
-- (including the boot-time steps in modules/persistence/migrate.lua); use
-- test/sql/scratch/run.sh, which prepares compat_scratch_* databases for every
-- scenario and runs this file plus the scenario-specific ones. State-agnostic:
-- nothing here names `state` (see player_vehicles_state_*.sql).
SOURCE test/sql/scratch/helpers.sql

CALL assert_true((SELECT COUNT(*) FROM information_schema.TRIGGERS
  WHERE TRIGGER_SCHEMA = DATABASE() AND EVENT_OBJECT_TABLE = 'player_vehicles'
    AND TRIGGER_NAME IN ('qbcore_player_vehicles_compat_insert','qbcore_player_vehicles_compat_update')) = 2,
  'compat triggers not installed');
CALL assert_true((SELECT COUNT(*) FROM information_schema.TRIGGERS
  WHERE TRIGGER_SCHEMA = DATABASE() AND TRIGGER_NAME LIKE 'qbcore_player_vehicles_model_sync%') = 0,
  'superseded triggers still present');
CALL assert_true((SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'player_vehicles'
    AND COLUMN_NAME IN ('license','hash','fakeplate','garage','engine','body','depotprice','drivingdistance','status',
      'job','state','garage_id','engine_health','body_health','last_position','impound_fee','impound_lot',
      'impounded_at','created_at','last_updated','deleted_at','model','vehicle','mods','fuel','plate','citizenid',
      'balance','paymentamount','paymentsleft','financetime')) = 31, 'missing columns');

-- stock qb-garages-style INSERT (no state)
INSERT INTO player_vehicles (citizenid, license, vehicle, hash, mods, plate, garage)
VALUES ('ABC', 'license:x', 'sultan', '123', '{}', 'STK1', 'pillbox');
CALL assert_true((SELECT model = 'sultan' AND vehicle = 'sultan' AND garage_id = 'pillbox' AND garage = 'pillbox'
  AND engine_health = 1000 AND body_health = 1000 AND engine = 1000 AND body = 1000
  FROM player_vehicles WHERE plate = 'STK1'), 'stock insert -> kora cols');

-- stock INSERT that also sets engine/body/fuel
INSERT INTO player_vehicles (citizenid, license, vehicle, hash, mods, plate, garage, fuel, engine, body)
VALUES ('ABC', 'license:x', 'comet', '1', '{}', 'STK2', 'legion', 90, 650.6, 400.2);
CALL assert_true((SELECT engine_health = 651 AND body_health = 400 AND engine > 650.5 FROM player_vehicles WHERE plate = 'STK2'),
  'stock insert with health');

-- stock qb-garages UPDATE ... SET garage=? WHERE plate=?
UPDATE player_vehicles SET garage = 'mirror' WHERE plate = 'STK1';
CALL assert_true((SELECT garage_id = 'mirror' AND model = 'sultan' FROM player_vehicles WHERE plate = 'STK1'), 'stock garage update');

-- stock UPDATE ... SET engine=?, body=?, fuel=? WHERE plate=?
UPDATE player_vehicles SET engine = 123.6, body = -50, fuel = 33 WHERE plate = 'STK1';
CALL assert_true((SELECT engine_health = 124 AND body_health = 0 AND fuel = 33 AND engine > 123.5 FROM player_vehicles WHERE plate = 'STK1'),
  'stock health update (rounds, clamps below 0)');
UPDATE player_vehicles SET engine = 999999 WHERE plate = 'STK1';
CALL assert_true((SELECT engine_health = 65535 FROM player_vehicles WHERE plate = 'STK1'), 'stock health clamps above 65535');
UPDATE player_vehicles SET vehicle = 'comet' WHERE plate = 'STK1';
CALL assert_true((SELECT model = 'comet' FROM player_vehicles WHERE plate = 'STK1'), 'stock vehicle update -> model');

-- kora_core Core.garage.createVehicle-style insert
INSERT INTO player_vehicles (plate, model, vehicle, citizenid, job, fuel, engine_health, body_health)
VALUES ('KOR1', 'kuruma', 'kuruma', 'ABC', NULL, 70, 900, 850);
CALL assert_true((SELECT engine = 900 AND body = 850 AND engine_health = 900 AND body_health = 850 AND garage IS NULL
  AND vehicle = 'kuruma' FROM player_vehicles WHERE plate = 'KOR1'), 'kora insert -> stock cols (health not overwritten)');

-- kora-style insert naming ONLY the kora columns (no vehicle, no engine/body)
INSERT INTO player_vehicles (plate, model, citizenid, garage_id, engine_health, body_health)
VALUES ('KOR2', 'zentorno', 'ABC', 'legion', 777, 555);
CALL assert_true((SELECT vehicle = 'zentorno' AND garage = 'legion' AND engine = 777 AND body = 555
  AND engine_health = 777 AND body_health = 555 FROM player_vehicles WHERE plate = 'KOR2'), 'kora-only insert');

-- kora_dealership-style insert names only `vehicle` (no model) and float health
INSERT INTO player_vehicles (plate, vehicle, citizenid, fuel, engine_health, body_health, balance, paymentamount, paymentsleft, financetime)
VALUES ('KOR3', 'adder', 'ABC', 100.0, 1000.0, 1000.0, 0, 0, 0, 0);
CALL assert_true((SELECT model = 'adder' AND vehicle = 'adder' AND engine = 1000 FROM player_vehicles WHERE plate = 'KOR3'),
  'dealership-style insert');

-- kora_core garage updates: COALESCE(?, col) health/fuel/mods
UPDATE player_vehicles SET fuel = COALESCE(55, fuel), engine_health = COALESCE(321, engine_health),
  body_health = COALESCE(NULL, body_health), mods = COALESCE('{"a":1}', mods) WHERE plate = 'KOR2';
CALL assert_true((SELECT engine = 321 AND engine_health = 321 AND body = 555 AND body_health = 555 AND fuel = 55
  FROM player_vehicles WHERE plate = 'KOR2'), 'kora health update -> stock cols');

-- kora update clearing garage_id / changing model
UPDATE player_vehicles SET garage_id = NULL, model = 'zentorno2' WHERE plate = 'KOR2';
CALL assert_true((SELECT garage IS NULL AND vehicle = 'zentorno2' FROM player_vehicles WHERE plate = 'KOR2'), 'kora update -> stock cols');

-- unrelated update must not disturb float precision
UPDATE player_vehicles SET engine = 650.25 WHERE plate = 'STK2';
UPDATE player_vehicles SET fuel = 10 WHERE plate = 'STK2';
CALL assert_true((SELECT engine = 650.25 AND engine_health = 650 FROM player_vehicles WHERE plate = 'STK2'), 'unrelated update keeps values');

-- kora wins if both sides change at once
UPDATE player_vehicles SET engine_health = 100, engine = 999 WHERE plate = 'KOR1';
CALL assert_true((SELECT engine_health = 100 AND engine = 100 FROM player_vehicles WHERE plate = 'KOR1'), 'kora wins on conflict');

-- deleted_at soft delete (kora_core) still works
UPDATE player_vehicles SET deleted_at = NOW() WHERE plate = 'KOR3';
CALL assert_true((SELECT deleted_at IS NOT NULL FROM player_vehicles WHERE plate = 'KOR3'), 'soft delete');

SELECT 'OK player_vehicles_compat' AS result;
