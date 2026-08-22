-- Core.logging (server realm) -- thin pass-through to qblib's generic
-- QB.logging (ring-buffered event log + optional Discord webhook). The
-- mechanics live in qblib now, since none of them ever touched qbcore's
-- player/job model; this module exists only to keep exports.qbcore:logEvent /
-- exports.qbcore:getLogStats working for existing consumers.

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
