-- Core.money (server realm) -- thin wrappers over the funnel. Every balance
-- change is Core.player.setPath(src, {'money', account}, newValue), so money
-- gets dirty-tracking + delta replication for free. Emits the legacy
-- QBCore:Server:OnMoneyChange event for compat.

local PI = CoreInternal.player

local function validAccount(account)
    for _, a in ipairs(Config.money.types) do if a == account then return true end end
    return false
end

local function floorFor(account)
    if Config.money.allowNegative and Config.money.allowNegative[account] then
        return Config.money.minusLimit or -math.huge
    end
    return 0
end

---@param src integer
---@param account string
---@return number|nil
function Core.money.getMoney(src, account)
    local player = PI.handle(src)
    if not player then return nil end
    return player.PlayerData.money[account]
end

---@param src integer
---@param account string
---@param amount number
---@param reason string|nil
---@return boolean, string|nil
function Core.money.addMoney(src, account, amount, reason)
    if not validAccount(account) then return false, 'invalid account' end
    amount = tonumber(amount)
    if not amount or amount <= 0 then return false, 'amount must be positive' end
    local player = PI.handle(src)
    if not player then return false, 'no such player' end
    local newValue = (player.PlayerData.money[account] or 0) + amount
    Core.player.setPath(src, { 'money', account }, newValue)
    TriggerEvent('QBCore:Server:OnMoneyChange', src, account, amount, 'add', reason)
    TriggerClientEvent('QBCore:Client:OnMoneyChange', src, account, amount, 'add', reason)
    return true
end

---@param src integer
---@param account string
---@param amount number
---@param reason string|nil
---@return boolean, string|nil
function Core.money.removeMoney(src, account, amount, reason)
    if not validAccount(account) then return false, 'invalid account' end
    amount = tonumber(amount)
    if not amount or amount <= 0 then return false, 'amount must be positive' end
    local player = PI.handle(src)
    if not player then return false, 'no such player' end
    local current = player.PlayerData.money[account] or 0
    local newValue = current - amount
    if newValue < floorFor(account) then
        return false, 'insufficient funds'
    end
    Core.player.setPath(src, { 'money', account }, newValue)
    TriggerEvent('QBCore:Server:OnMoneyChange', src, account, amount, 'remove', reason)
    TriggerClientEvent('QBCore:Client:OnMoneyChange', src, account, amount, 'remove', reason)
    return true
end

---@param src integer
---@param account string
---@param amount number
---@param reason string|nil
---@return boolean, string|nil
function Core.money.setMoney(src, account, amount, reason)
    if not validAccount(account) then return false, 'invalid account' end
    amount = tonumber(amount)
    if not amount then return false, 'amount must be a number' end
    if amount < floorFor(account) then return false, 'below account floor' end
    local player = PI.handle(src)
    if not player then return false, 'no such player' end
    Core.player.setPath(src, { 'money', account }, amount)
    TriggerEvent('QBCore:Server:OnMoneyChange', src, account, amount, 'set', reason)
    TriggerClientEvent('QBCore:Client:OnMoneyChange', src, account, amount, 'set', reason)
    return true
end

---Move money between two online players atomically-ish (remove then add; the
---remove failing aborts before any add).
---@return boolean, string|nil
function Core.money.transferMoney(fromSrc, toSrc, account, amount, reason)
    local ok, err = Core.money.removeMoney(fromSrc, account, amount, reason)
    if not ok then return false, err end
    local ok2, err2 = Core.money.addMoney(toSrc, account, amount, reason)
    if not ok2 then
        -- Refund on failure to add.
        Core.money.addMoney(fromSrc, account, amount, 'transfer-refund')
        return false, err2
    end
    return true
end
