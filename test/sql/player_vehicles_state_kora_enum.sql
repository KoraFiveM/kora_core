-- `state` as kora creates it (ENUM('out','garaged','impounded')), legacyVehicleState OFF.
SOURCE test/sql/scratch/helpers.sql
CALL assert_true((SELECT COLUMN_TYPE = "enum('out','garaged','impounded')" FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'player_vehicles' AND COLUMN_NAME = 'state'), 'kora enum untouched');

-- kora_dealership insertOwnedVehicle
INSERT INTO player_vehicles (plate, vehicle, citizenid, state, fuel, engine_health, body_health, balance, paymentamount, paymentsleft, financetime)
VALUES ('DLR1', 'adder', 'ABC', 'garaged', 100.0, 1000.0, 1000.0, 0, 0, 0, 0);
CALL assert_true((SELECT model = 'adder' AND state = 'garaged' FROM player_vehicles WHERE plate = 'DLR1'), 'dealership insert');
-- kora_garages server.lua statements
UPDATE player_vehicles SET state = 'out' WHERE plate = 'DLR1';
CALL assert_true((SELECT state = 'out' FROM player_vehicles WHERE plate = 'DLR1'), 'garages take out');
UPDATE player_vehicles SET state = 'garaged', mods = '{}', engine_health = 640, body_health = 410, fuel = 61 WHERE plate = 'DLR1';
CALL assert_true((SELECT state = 'garaged' AND engine = 640 AND body = 410 FROM player_vehicles WHERE plate = 'DLR1'), 'garages store');
UPDATE player_vehicles SET state = 'garaged' WHERE state = 'out';
CALL assert_true((SELECT COUNT(*) FROM player_vehicles WHERE state = 'garaged' AND garage_id IS NULL AND plate = 'DLR1') = 1, 'garages boot reset');
-- kora_core Core.garage statements
UPDATE player_vehicles SET state = 'garaged', garage_id = 'legion', fuel = COALESCE(50, fuel), engine_health = COALESCE(500, engine_health),
  body_health = COALESCE(NULL, body_health), mods = COALESCE(NULL, mods) WHERE plate = 'DLR1' AND state = 'garaged' AND deleted_at IS NULL;
CALL assert_true((SELECT garage = 'legion' AND engine = 500 FROM player_vehicles WHERE plate = 'DLR1'), 'core garage store');
UPDATE player_vehicles SET state = 'impounded', impound_fee = 100, impound_lot = 'lot', impounded_at = NOW() WHERE plate = 'DLR1';
CALL assert_true((SELECT state = 'impounded' FROM player_vehicles WHERE plate = 'DLR1'), 'core impound');

-- WHAT DOES NOT WORK for stock integer-state scripts on kora's ENUM (documented):
-- integer 1 is the enum INDEX -> 'out' (stock meant garaged): silently inverted.
INSERT INTO player_vehicles (citizenid, license, vehicle, hash, mods, plate, garage, state)
VALUES ('ABC', 'license:x', 'sultan', '123', '{}', 'STK9', 'pillbox', 1);
CALL assert_true((SELECT state = 'out' AND model = 'sultan' AND garage_id = 'pillbox' FROM player_vehicles WHERE plate = 'STK9'),
  'stock state=1 insert lands on out (inverted)');
UPDATE player_vehicles SET garage = 'mirror', state = 1 WHERE plate = 'STK9';
CALL assert_true((SELECT state = 'out' AND garage_id = 'mirror' FROM player_vehicles WHERE plate = 'STK9'), 'stock update state=1 -> out (inverted)');
-- integer 0 (stock "out") is rejected under strict mode.
CALL assert_fails('UPDATE player_vehicles SET state = 0 WHERE plate = ''STK9''', 'state=0 must fail');
-- a stock read `state = 1` therefore returns kora\'s "out" rows.
CALL assert_true((SELECT COUNT(*) FROM player_vehicles WHERE state = 1 AND plate = 'STK9') = 1, 'stock read state=1 matches out');
SELECT 'OK state_kora_enum' AS result;
