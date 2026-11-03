-- Keep stock QB's `vehicle` name and this rebuild's `model` name available
-- together so imported player_vehicles tables work with both consumers.
ALTER TABLE `player_vehicles`
  ADD COLUMN IF NOT EXISTS `model` VARCHAR(60) NULL AFTER `plate`;

ALTER TABLE `player_vehicles`
  ADD COLUMN IF NOT EXISTS `vehicle` VARCHAR(60) NULL AFTER `model`;
