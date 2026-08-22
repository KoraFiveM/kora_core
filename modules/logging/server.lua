-- Core.logging (server realm) -- a lightweight ring-buffered event log with an
-- optional Discord webhook, plus aggregate counters other tooling can read. Kept
-- deliberately small; loaded last among modules so it can observe the others.

local RING = 500
local ring = {}
local head = 0
local counts = {}   -- category -> count

---Log a gameplay/admin event. category groups them (e.g. 'money', 'job',
---'admin'). data is any table; src is the acting player (0 for system).
---@param category string
---@param src integer
---@param data table|nil
function Core.logging.logEvent(category, src, data)
    local entry = {
        category = category, source = src, data = data,
        at = os.time(),
    }
    if #ring < RING then ring[#ring + 1] = entry else ring[head + 1] = entry; head = (head + 1) % RING end
    counts[category] = (counts[category] or 0) + 1

    local url = GetConvar('qbcore_log_webhook', '')
    if url ~= '' then
        -- Fire-and-forget webhook; never blocks the caller.
        PerformHttpRequest(url, function() end, 'POST', json.encode({
            username = 'qbcore',
            content = ('[%s] src=%s %s'):format(category, tostring(src), json.encode(data or {})),
        }), { ['Content-Type'] = 'application/json' })
    end
end

---@return table  -- { counts = {category=n}, ringSize = n }
function Core.logging.getLogStats()
    return { counts = counts, ringSize = #ring }
end
