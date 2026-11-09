---Log a gameplay/admin event. category groups them (e.g. 'money', 'job',
---'admin'). data is any table; src is the acting player (0 for system).
---@param category string
---@param src integer
---@param data table|nil
function Core.logging.logEvent(category, src, data)
    Kora.logging.event(category, src, data)
end

---@return table  -- { counts = {category=n}, ringSize = n }
function Core.logging.getLogStats()
    return Kora.logging.getStats()
end
