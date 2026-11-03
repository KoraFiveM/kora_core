-- qb-vehicleshop owns these financing fields, but legacy servers commonly
-- import player_vehicles before starting the rebuilt core. Keep the shared
-- table usable without requiring an operator to manually re-run vehshop.sql.
ALTER TABLE `player_vehicles`
  ADD COLUMN IF NOT EXISTS `balance` INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `paymentamount` INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `paymentsleft` INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `financetime` INT NOT NULL DEFAULT 0;
