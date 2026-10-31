-- Core.users -- one row per identity (license), separate from a character (a
-- single license owns several `players` rows via Core.multichar). Currently
-- the only thing tracked here is an optional per-user override for how many
-- character slots that license gets, on top of the global
-- Config.identity.maxCharacters default -- e.g. a VIP allowance.

---Returns this license's character-slot cap: its own `users.max_characters`
---override if one is set, Config.identity.maxCharacters otherwise. Ensures a
---`users` row exists for the license along the way (idempotent -- INSERT
---IGNORE, so a concurrent first-call race just no-ops on the loser). Yields.
---@param license string
---@return integer
function Core.users.getMaxCharacters(license)
    local row = Kora.sql.single('SELECT `max_characters` FROM `users` WHERE `license` = ?', { license })
    if not row then
        Kora.sql.execute('INSERT IGNORE INTO `users` (`license`) VALUES (?)', { license })
        return Config.identity.maxCharacters
    end
    return row.max_characters or Config.identity.maxCharacters
end

---Sets (or clears, with nil) a per-user character-slot override. Yields.
---@param license string
---@param maxCharacters integer|nil
function Core.users.setMaxCharacters(license, maxCharacters)
    Kora.sql.execute(
        'INSERT INTO `users` (`license`, `max_characters`) VALUES (?, ?) '
            .. 'ON DUPLICATE KEY UPDATE `max_characters` = VALUES(`max_characters`)',
        -- maxCharacters is nil when clearing the override; a trailing nil
        -- would truncate this array to one element for two placeholders.
        { license, maxCharacters or Kora.sql.NULL }
    )
end
