-- Core.util -- the QBCore.Shared.* primitives (round/Trim/SplitStr/RandomStr/
-- RandomInt) plus the small helpers the player funnel needs (pathGet/pathSet,
-- deepClone). Shared realm: identical on client and server.
--

local charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
local digits = '0123456789'

---@param value number
---@param places integer|nil
---@return number
function Core.util.round(value, places)
    if type(value) ~= 'number' then return 0 end
    places = places or 0
    local mult = 10 ^ places
    return math.floor(value * mult + 0.5) / mult
end

---@param value string
---@return string
function Core.util.trim(value)
    if type(value) ~= 'string' then return value end
    return (value:gsub('^%s*(.-)%s*$', '%1'))
end

---Split a string on a single-character delimiter.
---@param str string
---@param delimiter string
---@return string[]
function Core.util.splitStr(str, delimiter)
    local out = {}
    for part in (str .. delimiter):gmatch('(.-)' .. (delimiter:gsub('%W', '%%%1'))) do
        out[#out + 1] = part
    end
    return out
end

---Random uppercase-letter string (legacy QBCore.Shared.RandomStr).
---@param length integer
---@return string
function Core.util.randomStr(length)
    local out = {}
    for i = 1, (length or 0) do
        local idx = math.random(1, #charset)
        out[i] = charset:sub(idx, idx)
    end
    return table.concat(out)
end

---Random digit string (legacy QBCore.Shared.RandomInt -- returns a STRING,
---matching legacy behaviour, not a number).
---@param length integer
---@return string
function Core.util.randomInt(length)
    local out = {}
    for i = 1, (length or 0) do
        local idx = math.random(1, #digits)
        out[i] = digits:sub(idx, idx)
    end
    return table.concat(out)
end

---An alphanumeric id used for citizenids and stash ids.
---@param length integer
---@return string
function Core.util.randomAlnum(length)
    local pool = charset .. digits
    local out = {}
    for i = 1, (length or 0) do
        local idx = math.random(1, #pool)
        out[i] = pool:sub(idx, idx)
    end
    return table.concat(out)
end

---Deep-clone a table (arrays and maps; no metatables, no cycles). Used to hand
---a caller an isolated copy of PlayerData rather than a live internal reference.
---@generic T
---@param t T
---@return T
function Core.util.deepClone(t)
    if type(t) ~= 'table' then return t end
    local out = {}
    for k, v in pairs(t) do
        out[k] = (type(v) == 'table') and Core.util.deepClone(v) or v
    end
    return out
end

---Read a nested value by an array path. `path` is an array of keys, e.g.
---{'money','cash'}. Returns nil if any segment is missing.
---@param t table
---@param path (string|integer)[]
---@return any
function Core.util.pathGet(t, path)
    local node = t
    for i = 1, #path do
        if type(node) ~= 'table' then return nil end
        node = node[path[i]]
    end
    return node
end

---Write a nested value by an array path, creating intermediate tables. Returns
---the PREVIOUS value at that path (so callers can detect no-op writes).
---@param t table
---@param path (string|integer)[]
---@param value any
---@return any previous
function Core.util.pathSet(t, path, value)
    local node = t
    for i = 1, #path - 1 do
        local key = path[i]
        if type(node[key]) ~= 'table' then node[key] = {} end
        node = node[key]
    end
    local last = path[#path]
    local prev = node[last]
    node[last] = value
    return prev
end
