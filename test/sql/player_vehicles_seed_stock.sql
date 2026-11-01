-- Rows imported from stock qb-core (test/sql/scratch/stock_qbcore_player_vehicles.sql).
SOURCE test/sql/scratch/helpers.sql
CALL assert_true((SELECT model = 'adder' AND garage_id = 'legion' AND ABS(engine_health - 812.5) <= 0.5
  AND ABS(body_health - 640.25) <= 0.5 AND engine = 812.5 AND body = 640.25 FROM player_vehicles WHERE plate = 'LEG1'),
  'stock row LEG1 backfilled into kora columns');
CALL assert_true((SELECT model = 'sultan' AND garage_id = 'pillbox' AND engine_health = 1000 FROM player_vehicles WHERE plate = 'LEG2'), 'LEG2');
CALL assert_true((SELECT model = 'comet2' AND garage_id IS NULL AND engine_health = 300 AND body_health = 0 FROM player_vehicles WHERE plate = 'LEG3'), 'LEG3');
CALL assert_true((SELECT COUNT(*) FROM player_vehicles WHERE plate IN ('LEG1','LEG2','LEG3') AND deleted_at IS NULL) = 3, 'deleted_at NULL');
SELECT 'OK seed_stock' AS result;
