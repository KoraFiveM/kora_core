-- Rows that exist BEFORE migration 011 on a kora install (inserted by run.sh).
SOURCE test/sql/scratch/helpers.sql
CALL assert_true((SELECT garage = 'legion' AND engine = 800 AND body = 700 AND vehicle = 'adder' AND garage_id = 'legion'
  FROM player_vehicles WHERE plate = 'OLD1'), 'backfill of pre-existing kora row');
SELECT 'OK seed_kora' AS result;
