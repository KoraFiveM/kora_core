-- Core.metadata (server realm) -- metadata get/set/increment via the funnel.
-- These are the highest-churn writes (hunger/thirst/stress ticks), which is why
-- the funnel's per-column dirty tracking + byte-identical gate matter most here:
-- a hunger tick that lands on the same value writes nothing.

local PI = CoreInternal.player

---@param src integer
---@param key string
---@return any
function Core.metadata.getMetaData(src, key)
    local p = PI.handle(src)
    if not p then return nil end
    if key == nil then return p.PlayerData.metadata end
    return p.PlayerData.metadata[key]
end

---@param src integer
---@param key string
---@param value any
---@return boolean, string|nil
function Core.metadata.setMetaData(src, key, value)
    local p = PI.handle(src)
    if not p then return false, 'no such player' end
    if type(key) ~= 'string' then return false, 'metadata key must be a string' end
    Core.player.setPath(src, { 'metadata', key }, value)
    TriggerEvent('QBCore:Server:OnMetaDataChange', src, key, value)
    return true
end

---Increment a numeric metadata key, clamped to [min, max] when given. Returns
---the new value.
---@param src integer
---@param key string
---@param delta number
---@param min number|nil
---@param max number|nil
---@return number|nil, string|nil
function Core.metadata.incrementMetaData(src, key, delta, min, max)
    local p = PI.handle(src)
    if not p then return nil, 'no such player' end
    delta = tonumber(delta) or 0
    local current = tonumber(p.PlayerData.metadata[key]) or 0
    local newValue = current + delta
    if min and newValue < min then newValue = min end
    if max and newValue > max then newValue = max end
    Core.player.setPath(src, { 'metadata', key }, newValue)
    return newValue
end
