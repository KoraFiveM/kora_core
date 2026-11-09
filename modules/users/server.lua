-- Core.users -- one row per identity (license), separate from a character (a
-- single license owns several `players` rows via Core.multichar). Currently
-- character slots that license gets, on top of the global

local savedDiscord = {}

---Saves the source's Discord id on its `users` row (license is the key).
---No-op when Config.identity.saveDiscord is off, the player has no Discord
---identifier, or the id is unchanged since last saved. Yields.
---@param src integer
function Core.users.recordDiscord(src)
    if not Config.identity.saveDiscord then return end
    local ids = Core.identity.getIdentifiers(src)
    local license, discord = ids[Config.identity.primaryIdentifier], ids.discord
    if not license or not discord or savedDiscord[license] == discord then return end
    Kora.sql.execute(
        'INSERT INTO `users` (`license`, `discord`) VALUES (?, ?) '
            .. 'ON DUPLICATE KEY UPDATE `discord` = VALUES(`discord`)',
        { license, discord }
    )
    savedDiscord[license] = discord
end

---The Discord id stored for a license, or nil. Yields.
---@param license string
---@return string|nil
function Core.users.getDiscord(license)
    local row = Kora.sql.single('SELECT `discord` FROM `users` WHERE `license` = ?', { license })
    return row and row.discord or nil
end

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
        { license, maxCharacters or Kora.sql.NULL }
    )
end
