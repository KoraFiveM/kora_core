-- NOT REGISTERED in modules/persistence/migrate.lua and never auto-run.
-- Optional pre-provisioning for the qbx facade (compat/server/qbx.lua): stock
-- ox_inventory keys vehicle trunk/glovebox storage on player_vehicles.id and
-- ALTERs these two columns in itself on first boot when they are missing
-- (modules/mysql db.setup). Run this by hand only if you prefer the DDL to
-- happen before ox_inventory starts, or if its database user cannot ALTER.
ALTER TABLE `player_vehicles`
  ADD COLUMN IF NOT EXISTS `trunk` LONGTEXT NULL,
  ADD COLUMN IF NOT EXISTS `glovebox` LONGTEXT NULL;
