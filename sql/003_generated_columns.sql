-- Optional (Config.persistence.generatedColumns). VIRTUAL columns cost nothing
-- on write; the indexes on them DO cost on write, so they are added together and
-- gated as one migration you opt into.
ALTER TABLE `players`
  ADD COLUMN `cash`     INT         AS (CAST(JSON_EXTRACT(`money`, '$.cash') AS SIGNED)) VIRTUAL,
  ADD COLUMN `bank`     INT         AS (CAST(JSON_EXTRACT(`money`, '$.bank') AS SIGNED)) VIRTUAL,
  ADD COLUMN `job_name` VARCHAR(50) AS (JSON_UNQUOTE(JSON_EXTRACT(`job`, '$.name')))     VIRTUAL,
  ADD KEY `idx_players_bank`     (`bank`),
  ADD KEY `idx_players_job_name` (`job_name`);
