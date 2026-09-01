-- Migration v1 intentionally uses CREATE TABLE IF NOT EXISTS, which cannot
-- evolve a players table imported from legacy qb-core. Add the columns used by
-- this rebuild without rewriting or deleting any existing character row.
ALTER TABLE `players`
  ADD COLUMN IF NOT EXISTS `phone_number` VARCHAR(20) NULL DEFAULT NULL;

ALTER TABLE `players`
  ADD COLUMN IF NOT EXISTS `deleted_at` TIMESTAMP NULL DEFAULT NULL;

ALTER TABLE `players`
  ADD INDEX IF NOT EXISTS `idx_players_license_deleted` (`license`,`deleted_at`);
