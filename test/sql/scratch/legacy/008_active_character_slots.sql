-- Keep deleted character rows for audit/history without reserving their slot.
-- MySQL unique indexes allow multiple NULLs, so only active rows get a value.
ALTER TABLE `players`
  ADD COLUMN IF NOT EXISTS `active_cid` TINYINT UNSIGNED
    GENERATED ALWAYS AS (IF(`deleted_at` IS NULL, `cid`, NULL)) STORED,
  DROP INDEX IF EXISTS `uk_players_license_cid`,
  ADD UNIQUE INDEX IF NOT EXISTS `uk_players_license_active_cid` (`license`,`active_cid`);
