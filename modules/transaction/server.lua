-- Server-side player transaction: validate every leg before changing state.

local function entries(value)
    return type(value) == 'table' and value or {}
end

-- Positive whole numbers; numeric strings stay accepted as before. toAmount
-- also rejects NaN and infinity, which the old floor-equality test let through
-- (math.floor(math.huge) == math.huge).
local AMOUNT_OPTS = { allowString = true, max = 2 ^ 53 }
local function amount(value)
    return (Kora.util.toAmount(value, AMOUNT_OPTS))
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
            if not Kora.util.isInteger(minimum) or not Kora.util.isInteger(maximum) or minimum <= 0 or maximum < minimum then
                return false, 'random item amount must be a positive whole number or an integer range'
            end
        end
        if next(random) ~= nil then
            -- Allow all bonuses to miss rather than forcing a fallback reward.
            local ok, rewards = pcall(Kora.rewards.generate, random, { mode = 'percent', allowNone = true })
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

-- Core.commerce: the buy/sell shape almost every shop, vendor and job reward
-- hand-writes. Each call is ONE Core.transaction, so the item leg and the money
-- leg succeed or fail together, and every amount goes through Kora.util.toAmount.

local COMMERCE_ACCOUNTS = { cash = true, bank = true }
local DEFAULT_MAX_AMOUNT = 1000
local DEFAULT_MAX_DISTANCE = 5.0

---@class KoraCommerceSpec
---@field item string
---@field amount any                  untrusted client value; validated with Kora.util.toAmount
---@field unitPrice number            server-side price per unit, never from the client
---@field account? 'cash'|'bank'      default 'cash'
---@field reason string               required; flows into money events and the 'commerce' log
---@field maxAmount? integer          default 1000
---@field metadata? table             item info for a buy
---@field at? vector3                 optional proximity re-check point
---@field maxDistance? number         default 5.0 when `at` is set

---@param kind string
---@param spec KoraCommerceSpec
local function assertSpec(kind, spec)
    assert(type(spec) == 'table', kind .. ' spec must be a table')
    assert(type(spec.item) == 'string' and spec.item ~= '', kind .. ' spec.item must be a non-empty string')
    assert(type(spec.reason) == 'string' and spec.reason ~= '', kind .. ' spec.reason is required')
    assert(Kora.util.isFiniteNumber(spec.unitPrice) and spec.unitPrice >= 0,
        kind .. ' spec.unitPrice must be a finite number >= 0')
    assert(spec.maxAmount == nil or (Kora.util.isInteger(spec.maxAmount) and spec.maxAmount >= 1),
        kind .. ' spec.maxAmount must be a positive integer')
    assert(spec.metadata == nil or type(spec.metadata) == 'table', kind .. ' spec.metadata must be a table')
    assert(spec.maxDistance == nil or (Kora.util.isFiniteNumber(spec.maxDistance) and spec.maxDistance > 0),
        kind .. ' spec.maxDistance must be a positive number')
end

---@param src integer
---@param at table
---@param maxDistance number
---@return boolean
local function withinReach(src, at, maxDistance)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local coords = GetEntityCoords(ped)
    local dx, dy, dz = coords.x - at.x, coords.y - at.y, coords.z - at.z
    return dx * dx + dy * dy + dz * dz <= maxDistance * maxDistance
end

---Shared validation for buy/sell. Returns the validated amount and total.
---@return integer|nil amount, number|string total_or_reason, string|nil account
local function prepare(kind, src, spec)
    assertSpec(kind, spec)
    src = tonumber(src)
    if not src or not CoreInternal.player.handle(src) then return nil, 'no_player' end

    local account = spec.account
    if account == nil then account = 'cash' end
    if not COMMERCE_ACCOUNTS[account] then return nil, 'invalid_account' end

    local count, reason = Kora.util.toAmount(spec.amount, { max = spec.maxAmount or DEFAULT_MAX_AMOUNT })
    if not count then return nil, reason end

    if spec.at ~= nil then
        if not withinReach(src, spec.at, spec.maxDistance or DEFAULT_MAX_DISTANCE) then return nil, 'too_far' end
    end
    return count, math.floor(spec.unitPrice * count), account
end

---@param kind 'buy'|'sell'
local function logCommerce(kind, src, spec, count, total, account)
    Core.logging.logEvent('commerce', src, {
        action = kind, item = spec.item, amount = count, total = total, account = account, reason = spec.reason,
    })
end

---Sells `spec.amount` of `spec.item` from the player for `unitPrice` each:
---removes the items and pays the total in one transaction.
---@param src integer
---@param spec KoraCommerceSpec
---@return boolean ok
---@return table|string result `{ amount, total }` on success, else a reason: 'no_player', 'invalid_account',
---  'not_number', 'not_finite', 'not_integer', 'below_min', 'above_max', 'too_far', or a transaction error
function Core.commerce.sellItem(src, spec)
    local count, total, account = prepare('sellItem', src, spec)
    if not count then return false, total end
    src = tonumber(src)

    local definition = {
        reason = spec.reason,
        items = { remove = { { item = spec.item, amount = count } } },
    }
    -- A worthless item (total 0) is still removed; a zero money leg is invalid.
    if total > 0 then definition.money = { add = { { account = account, amount = total } } } end
    local ok, err = Core.transaction(src, definition)
    if not ok then return false, err end
    logCommerce('sell', src, spec, count, total, account)
    return true, { amount = count, total = total }
end

---Buys `spec.amount` of `spec.item` for `unitPrice` each: takes the total and
---gives the items (with `spec.metadata` as their info) in one transaction.
---@param src integer
---@param spec KoraCommerceSpec
---@return boolean ok
---@return table|string result `{ amount, total }` on success, else a reason (see sellItem)
function Core.commerce.buyItem(src, spec)
    local count, total, account = prepare('buyItem', src, spec)
    if not count then return false, total end
    src = tonumber(src)

    local definition = {
        reason = spec.reason,
        -- Cloned: a caller reusing one metadata table must not alias every bought stack.
        items = { add = { { item = spec.item, amount = count, info = spec.metadata and Core.util.deepClone(spec.metadata) } } },
    }
    if total > 0 then definition.money = { remove = { { account = account, amount = total } } } end
    local ok, err = Core.transaction(src, definition)
    if not ok then return false, err end
    logCommerce('buy', src, spec, count, total, account)
    return true, { amount = count, total = total }
end
