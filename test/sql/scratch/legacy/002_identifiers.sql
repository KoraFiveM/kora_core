CREATE TABLE IF NOT EXISTS `player_identifiers` (
  `citizenid`  VARCHAR(50)  NOT NULL,
  `kind`       VARCHAR(20)  NOT NULL,
  `value`      VARCHAR(128) NOT NULL,
  `first_seen` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_seen`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`citizenid`,`kind`),
  KEY `idx_ident_lookup` (`kind`,`value`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `inventories` (
  `identifier` VARCHAR(64)       NOT NULL,
  `kind`       VARCHAR(20)       NOT NULL DEFAULT 'stash',
  `items`      LONGTEXT          NOT NULL,
  `slots`      SMALLINT UNSIGNED NOT NULL DEFAULT 50,
  `maxweight`  INT UNSIGNED      NOT NULL DEFAULT 100000,
  `updated_at` TIMESTAMP         NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`identifier`),
  KEY `idx_inventories_kind_updated` (`kind`,`updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bans` (
  `id`       INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name`     VARCHAR(50)           DEFAULT NULL,
  `license`  VARCHAR(60)           DEFAULT NULL,
  `discord`  VARCHAR(50)           DEFAULT NULL,
  `ip`       VARCHAR(50)           DEFAULT NULL,
  `reason`   TEXT                  DEFAULT NULL,
  `expire`   INT UNSIGNED          DEFAULT NULL,
  `bannedby` VARCHAR(255) NOT NULL DEFAULT 'LeBanhammer',
  PRIMARY KEY (`id`),
  KEY `idx_bans_license` (`license`),
  KEY `idx_bans_discord` (`discord`),
  KEY `idx_bans_ip`      (`ip`),
  KEY `idx_bans_expire`  (`expire`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
