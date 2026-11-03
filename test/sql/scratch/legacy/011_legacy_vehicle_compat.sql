-- Stock qb-garages / qb-vehicleshop columns on `player_vehicles`, plus kora's own
-- columns for a table that was imported from stock qb-core BEFORE kora ran (005 is
-- CREATE TABLE IF NOT EXISTS and cannot evolve such a table). Every statement is an
-- ALTER ... ADD COLUMN IF NOT EXISTS because kora_sql's runner accepts nothing else;
-- the non-additive parts (nullability relaxation, backfills, the optional `state`
-- conversion, the sync triggers) are done by modules/persistence/migrate.lua.
-- Mapping (kora <-> stock):
--   model <-> vehicle, garage_id <-> garage,
--   engine_health (0-65535 int) <-> engine (float), body_health <-> body.
-- `license`, `hash`, `fakeplate`, `depotprice`, `drivingdistance`, `status` have
-- no kora counterpart and are plain pass-through columns.
-- `state` is NOT mapped: see docs/vehicles-compat.md.
ALTER TABLE `player_vehicles`
  ADD COLUMN IF NOT EXISTS `license` VARCHAR(50) NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `hash` VARCHAR(50) NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `fakeplate` VARCHAR(50) NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `garage` VARCHAR(50) NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `engine` FLOAT NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `body` FLOAT NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `depotprice` INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `drivingdistance` INT NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `status` TEXT NULL DEFAULT NULL;

-- kora's own columns, absent on a stock-imported table.
ALTER TABLE `player_vehicles`
  ADD COLUMN IF NOT EXISTS `job` VARCHAR(50) NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `state` ENUM('out','garaged','impounded') NOT NULL DEFAULT 'garaged',
  ADD COLUMN IF NOT EXISTS `garage_id` VARCHAR(50) NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `engine_health` SMALLINT UNSIGNED NOT NULL DEFAULT 1000,
  ADD COLUMN IF NOT EXISTS `body_health` SMALLINT UNSIGNED NOT NULL DEFAULT 1000,
  ADD COLUMN IF NOT EXISTS `last_position` LONGTEXT NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `impound_fee` INT UNSIGNED NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `impound_lot` VARCHAR(50) NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `impounded_at` TIMESTAMP NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ADD COLUMN IF NOT EXISTS `last_updated` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  ADD COLUMN IF NOT EXISTS `deleted_at` TIMESTAMP NULL DEFAULT NULL;
