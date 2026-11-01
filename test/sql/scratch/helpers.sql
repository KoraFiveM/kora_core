-- Assertion helpers (scratch databases only). Any failure aborts the mariadb
-- client with an error naming the assertion; a clean file ends with "OK ...".
SET SESSION sql_mode = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';
DROP PROCEDURE IF EXISTS assert_true;
DROP PROCEDURE IF EXISTS assert_fails;
DELIMITER //
CREATE PROCEDURE assert_true(IN ok TINYINT, IN msg VARCHAR(200))
BEGIN
  IF ok IS NULL OR ok = 0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg; END IF;
END//
-- The statement MUST raise an SQL error (used to pin down what does NOT work).
CREATE PROCEDURE assert_fails(IN stmt TEXT, IN msg VARCHAR(200))
BEGIN
  DECLARE failed TINYINT DEFAULT 0;
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET failed = 1;
  DECLARE CONTINUE HANDLER FOR SQLWARNING SET failed = 1; -- strict-mode truncation is SQLSTATE 01000
  SET @assert_fails_sql = stmt;
  PREPARE s FROM @assert_fails_sql;
  EXECUTE s;
  DEALLOCATE PREPARE s;
  IF failed = 0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg; END IF;
END//
DELIMITER ;
