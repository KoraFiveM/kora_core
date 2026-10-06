-- Server-side player transaction: validate every leg before changing state.

local function entries(value)
    return type(value) == 'table' and value or {}
end

local function amount(value)
    value = tonumber(value)
    return value and math.floor(value) == value and value > 0 and value or nil
end

local function aggregateItems(list)
    local result = {}
    for _, entry in ipairs(entries(list)) do
        if type(entry) ~= 'table' or type(entry.item) ~= 'string' then return nil, 'invalid item entry' end
        local count = amount(entry.amount)
        if not count then return nil, 'item amount must be a positive whole number' end
        result[entry.item] = (result[entry.item] or 0) + count
    end
    return result
end

local function rollback(src, removedMoney, removedItems, addedItems, addedMoney, reason)
    for _, item in ipairs(addedItems) do Core.inventory.removeItem(src, item.item, item.amount, item.slot, reason) end
    for _, item in ipairs(removedItems) do Core.inventory.addItem(src, item.item, item.amount, item.slot, item.info, reason) end
    for _, money in ipairs(addedMoney) do Core.money.removeMoney(src, money.account, money.amount, reason, true) end
    for _, money in ipairs(removedMoney) do Core.money.addMoney(src, money.account, money.amount, reason, true) end
end

---@param src integer
---@param transaction table
---@return boolean, string|nil
function Core.transaction(src, transaction)
    if type(transaction) ~= 'table' then return false, 'transaction must be a table' end

    local itemAdds = transaction.items and transaction.items.add or {}
    local random = transaction.random
    if random ~= nil then
        if type(random) ~= 'table' then return false, 'random must be a table' end
        for _, entry in pairs(random) do
            if type(entry) ~= 'table' or type(entry.item) ~= 'string' then return false, 'invalid random item entry' end
            local minimum, maximum = entry.amount, entry.amount
            if minimum == nil then
                minimum, maximum = 1, 1
            elseif type(minimum) == 'table' then
                minimum, maximum = minimum.min, minimum.max
            end
            if not QB.util.isInteger(minimum) or not QB.util.isInteger(maximum) or minimum <= 0 or maximum < minimum then
                return false, 'random item amount must be a positive whole number or an integer range'
            end
        end
        if next(random) ~= nil then
            -- Allow all bonuses to miss rather than forcing a fallback reward.
            local ok, rewards = pcall(QB.rewards.generate, random, { mode = 'percent', allowNone = true })
            if not ok then return false, tostring(rewards) end
            local combined = {}
            for index, entry in ipairs(entries(itemAdds)) do combined[index] = entry end
            for _, entry in ipairs(rewards) do combined[#combined + 1] = entry end
            itemAdds = combined
        end
    end

    local money = transaction.money or {}
    local removes, removeErr = aggregateItems(transaction.items and transaction.items.remove)
    local adds, addErr = aggregateItems(itemAdds)
    if not removes then return false, removeErr end
    if not adds then return false, addErr end

    local removeMoney, addMoney = {}, {}
    for action, target in pairs({ remove = money.remove, add = money.add }) do
        for _, entry in ipairs(entries(target)) do
            if type(entry) ~= 'table' or type(entry.account) ~= 'string' or not amount(entry.amount) then
                return false, 'invalid money entry'
            end
            local list = action == 'remove' and removeMoney or addMoney
            list[#list + 1] = { account = entry.account, amount = amount(entry.amount) }
        end
    end

    for _, entry in ipairs(removeMoney) do
        local balance = Core.money.getMoney(src, entry.account)
        if balance == nil or balance < entry.amount then return false, 'insufficient funds' end
    end
    for _, entry in ipairs(addMoney) do
        if Core.money.getMoney(src, entry.account) == nil then return false, 'invalid account' end
    end
    for item, count in pairs(removes) do
        if Core.inventory.getItemCount(src, item) < count then return false, 'not enough of item: ' .. item end
    end
    for item, count in pairs(adds) do
        local canCarry, err = Core.inventory.canCarry(src, item, count)
        if not canCarry then return false, err end
    end

    local removedMoney, removedItems, addedItems, addedMoney = {}, {}, {}, {}
    local function fail(err)
        rollback(src, removedMoney, removedItems, addedItems, addedMoney, 'transaction rollback')
        return false, err
    end
    for _, entry in ipairs(removeMoney) do
        local ok, err = Core.money.removeMoney(src, entry.account, entry.amount, transaction.reason, true)
        if not ok then return fail(err) end
        removedMoney[#removedMoney + 1] = entry
    end
    for _, entry in ipairs(transaction.items and transaction.items.remove or {}) do
        local ok, err = Core.inventory.removeItem(src, entry.item, entry.amount, entry.slot, transaction.reason)
        if not ok then return fail(err) end
        removedItems[#removedItems + 1] = entry
    end
    for _, entry in ipairs(itemAdds) do
        local ok, err = Core.inventory.addItem(src, entry.item, entry.amount, entry.slot, entry.info, transaction.reason)
        if not ok then return fail(err) end
        addedItems[#addedItems + 1] = entry
    end
    for _, entry in ipairs(addMoney) do
        local ok, err = Core.money.addMoney(src, entry.account, entry.amount, transaction.reason, true)
        if not ok then return fail(err) end
        addedMoney[#addedMoney + 1] = entry
    end
    return true
end
