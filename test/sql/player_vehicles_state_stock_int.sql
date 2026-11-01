-- `state` still the imported stock INT (legacyVehicleState OFF, the default).
SOURCE test/sql/scratch/helpers.sql
CALL assert_true((SELECT DATA_TYPE = 'int' FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'player_vehicles' AND COLUMN_NAME = 'state'), 'state left as int');

-- stock qb-garages: works
INSERT INTO player_vehicles (citizenid, license, vehicle, hash, mods, plate, garage, state)
VALUES ('ABC', 'license:x', 'sultan', '123', '{}', 'STK9', 'pillbox', 1);
CALL assert_true((SELECT state = 1 AND model = 'sultan' AND garage_id = 'pillbox' FROM player_vehicles WHERE plate = 'STK9'), 'stock insert');
UPDATE player_vehicles SET garage = 'mirror', state = 0 WHERE plate = 'STK9';
CALL assert_true((SELECT state = 0 AND garage_id = 'mirror' FROM player_vehicles WHERE plate = 'STK9'), 'stock garage/state update');
UPDATE player_vehicles SET engine = 400.5, body = 300.5, fuel = 20 WHERE plate = 'STK9';
CALL assert_true((SELECT engine_health IN (400, 401) AND body_health IN (300, 301) AND fuel = 20 FROM player_vehicles WHERE plate = 'STK9'), 'stock health update');
CALL assert_true((SELECT COUNT(*) FROM player_vehicles WHERE state = 1 AND plate IN ('LEG1')) = 1, 'stock read state=1');

-- kora statements: DO NOT work (strings into an INT column; strict mode rejects them)
CALL assert_fails('UPDATE player_vehicles SET state = ''out'' WHERE plate = ''STK9''', 'kora state string must fail');
CALL assert_fails('INSERT INTO player_vehicles (plate, vehicle, citizenid, state, fuel, engine_health, body_health) VALUES (''DLR1'', ''adder'', ''ABC'', ''garaged'', 100, 1000, 1000)', 'dealership insert must fail');
SELECT 'OK state_stock_int' AS result;
