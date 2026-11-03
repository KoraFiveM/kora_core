CREATE TABLE IF NOT EXISTS `qbcore_player_column_operations` (
  `citizenid` VARCHAR(50) NOT NULL,
  `column_name` VARCHAR(16) NOT NULL,
  `resource` VARCHAR(64) NOT NULL,
  `operation_key` VARCHAR(240) NOT NULL,
  `fingerprint` LONGTEXT NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`citizenid`, `column_name`),
  KEY `idx_player_operation_owner` (`resource`, `operation_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
