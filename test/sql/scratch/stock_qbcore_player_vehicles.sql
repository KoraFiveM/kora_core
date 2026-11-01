-- Stock qb-core player_vehicles (+ qb-vehicleshop finance columns) as imported
-- from a legacy server, with a few rows. Scratch databases only.
CREATE TABLE `player_vehicles` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `license` varchar(50) DEFAULT NULL,
  `citizenid` varchar(50) DEFAULT NULL,
  `vehicle` varchar(50) DEFAULT NULL,
  `hash` varchar(50) DEFAULT NULL,
  `mods` longtext DEFAULT NULL,
  `plate` varchar(50) NOT NULL,
  `fakeplate` varchar(50) DEFAULT NULL,
  `garage` varchar(50) DEFAULT NULL,
  `fuel` int(11) DEFAULT 100,
  `engine` float DEFAULT 1000,
  `body` float DEFAULT 1000,
  `state` int(11) DEFAULT 1,
  `depotprice` int(11) NOT NULL DEFAULT 0,
  `drivingdistance` int(11) DEFAULT NULL,
  `status` text DEFAULT NULL,
  `balance` int(11) NOT NULL DEFAULT 0,
  `paymentamount` int(11) NOT NULL DEFAULT 0,
  `paymentsleft` int(11) NOT NULL DEFAULT 0,
  `financetime` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `plate` (`plate`),
  KEY `citizenid` (`citizenid`),
  KEY `license` (`license`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `player_vehicles` (license, citizenid, vehicle, hash, mods, plate, garage, fuel, engine, body, state) VALUES
 ('license:s1', 'STK00001', 'adder',  '-1216765807', '{}', 'LEG1', 'legion',  80, 812.5, 640.25, 1),
 ('license:s1', 'STK00001', 'sultan', '970598228',   '{}', 'LEG2', 'pillbox', 100, 1000, 1000, 0),
 ('license:s2', 'STK00002', 'comet2', '-1045541610', '{}', 'LEG3', NULL,      55, 300, 0, 2);
