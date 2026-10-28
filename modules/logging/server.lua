-- Core.logging (server realm) -- thin pass-through to kora_lib's generic
-- QB.logging (ring-buffered event log + optional Discord webhook). The
-- mechanics live in kora_lib now, since none of them ever touched kora_core's
-- player/job model; this module exists only to keep exports.kora_core:logEvent /
-- exports.kora_core:getLogStats working for existing consumers.

---Log a gameplay/admin event. category groups them (e.g. 'money', 'job',
---'admin'). data is any table; src is the acting player (0 for system).
---@param category string
---@param src integer
---@param data table|nil
function Core.logging.logEvent(category, src, data)
    QB.logging.event(category, src, data)
end

---@return table  -- { counts = {category=n}, ringSize = n }
function Core.logging.getLogStats()
    return QB.logging.getStats()
end
