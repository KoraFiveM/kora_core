-- Config.persistence.legacyVehicleState = true: `state` is kora's ENUM, ordered
-- ('garaged','impounded','out') so stock integer 1/2 land on the right meaning.
SOURCE test/sql/scratch/helpers.sql
CALL assert_true((SELECT COLUMN_TYPE = "enum('garaged','impounded','out')" AND IS_NULLABLE = 'NO' AND COLUMN_DEFAULT = "'garaged'"
  FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'player_vehicles' AND COLUMN_NAME = 'state'),
  'state converted to kora enum');

-- kora statements work
INSERT INTO player_vehicles (plate, vehicle, citizenid, state, fuel, engine_health, body_health, balance, paymentamount, paymentsleft, financetime)
VALUES ('DLR1', 'adder', 'ABC', 'garaged', 100.0, 1000.0, 1000.0, 0, 0, 0, 0);
UPDATE player_vehicles SET state = 'out' WHERE plate = 'DLR1';
CALL assert_true((SELECT state = 'out' FROM player_vehicles WHERE plate = 'DLR1'), 'kora string write');
UPDATE player_vehicles SET state = 'garaged' WHERE state = 'out' AND plate = 'DLR1';
CALL assert_true((SELECT state = 'garaged' FROM player_vehicles WHERE plate = 'DLR1'), 'kora string where');

-- stock qb-garages integer writes
INSERT INTO player_vehicles (citizenid, license, vehicle, hash, mods, plate, garage, state)
VALUES ('ABC', 'license:x', 'sultan', '123', '{}', 'STK9', 'pillbox', 1);
CALL assert_true((SELECT state = 'garaged' AND model = 'sultan' AND garage_id = 'pillbox' FROM player_vehicles WHERE plate = 'STK9'), 'stock insert state=1 -> garaged');
UPDATE player_vehicles SET garage = 'mirror', state = 2 WHERE plate = 'STK9';
CALL assert_true((SELECT state = 'impounded' AND garage_id = 'mirror' FROM player_vehicles WHERE plate = 'STK9'), 'stock state=2 -> impounded');
UPDATE player_vehicles SET state = 1 WHERE plate = 'STK9';
CALL assert_true((SELECT state = 'garaged' FROM player_vehicles WHERE plate = 'STK9'), 'stock state=1 update');
-- stock reads
CALL assert_true((SELECT COUNT(*) FROM player_vehicles WHERE state = 1 AND plate = 'STK9') = 1, 'stock read state=1');
CALL assert_true((SELECT COUNT(*) FROM player_vehicles WHERE state = 2 AND plate = 'STK9') = 0, 'stock read state=2 (not impounded)');
-- NOT supported: stock "out" = 0 has no enum index
CALL assert_fails('UPDATE player_vehicles SET state = 0 WHERE plate = ''STK9''', 'state=0 must fail');
CALL assert_true((SELECT COUNT(*) FROM player_vehicles WHERE state = 0) = 0, 'stock read state=0 never matches out rows');
SELECT 'OK state_converted' AS result;
