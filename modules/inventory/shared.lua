CoreInternal = CoreInternal or {}
CoreInternal.inventory = CoreInternal.inventory or {}
local II = CoreInternal.inventory

---@param items table
---@return number
function II.totalWeight(items)
    local total = 0
    for _, item in pairs(items or {}) do
        if type(item) == 'table' and item.name then
            local def = Core.registry.getShared('items', item.name)
                or Core.registry.getShared('weapons', item.name)
            local w = (def and def.weight) or item.weight or 0
            total = total + w * (item.amount or 1)
        end
    end
    return total
end

---@param name string
---@return boolean
function II.isUnique(name)
    local def = Core.registry.getShared('items', name)
    if def and def.unique then return true end
    if Core.registry.getShared('weapons', name) then return true end
    return false
end

---@param items table
---@param name string
---@param info table|nil
---@return integer|nil
function II.findStackSlot(items, name, info)
    if II.isUnique(name) then return nil end
    local best = nil
    for slot, item in pairs(items) do
        if item.name == name then
            local match = true
            if Config.inventory.matchInfoOnStack then
                match = II.infoEquals(item.info, info)
            end
            if match and (best == nil or slot < best) then best = slot end
        end
    end
    return best
end

function II.infoEquals(a, b)
    if a == b then return true end
    if type(a) ~= 'table' or type(b) ~= 'table' then return false end
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    return true
end

---@param items table
---@return integer|nil
function II.firstFreeSlot(items)
    for slot = 1, Config.inventory.slots do
        if items[slot] == nil then return slot end
    end
    return nil
end
