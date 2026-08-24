-- Core.money (server realm) -- thin wrappers over the funnel. Every balance
-- change is Core.player.setPath(src, {'money', account}, newValue), so money
-- gets dirty-tracking + delta replication for free. Emits the legacy
-- QBCore:Server:OnMoneyChange event for compat.

local PI = CoreInternal.player
-- account -> qbinventory resource. A registration survives an unexpected
-- provider stop so cash mutations fail closed instead of silently falling back
-- to a second ledger balance.
local physicalAccounts = {}
local MONEY_STATE_PREFIX = 'qbcore:money:'

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

local function providerFor(account)
    local provider = physicalAccounts[account]
    if not provider then return nil end
    if GetResourceState(provider) ~= 'started' then return false, 'physical cash provider unavailable' end
    return provider
end

local function emitMoneyChange(src, account, amount, action, reason)
    local balance = Core.money.getMoney(src, account)
    if balance ~= nil then Player(src).state:set(MONEY_STATE_PREFIX .. account, balance, true) end
    TriggerEvent('QBCore:Server:OnMoneyChange', src, account, amount, action, reason)
    TriggerClientEvent('QBCore:Client:OnMoneyChange', src, account, amount, action, reason)
    -- Legacy third-party hook: stock qb-hud's money popup (and other old
    -- resources) listen ONLY to this event, not the two above. Our own qbhud
    -- uses the statebag mirror above instead (see qbhud/client/bridge/qbcore.lua),
    -- so this emission is purely for drop-in legacy resources.
    local isRemove = action == 'remove'
    TriggerClientEvent('hud:client:OnMoneyChange', src, account, amount, isRemove)
    -- Legacy qb-phone hook: fired specifically on a bank-account removal.
    if account == 'bank' and isRemove then
        TriggerClientEvent('qb-phone:client:RemoveBankMoney', src, amount)
    end
end

---Publish authoritative balances for state-bag consumers such as qbhud.
---Physical accounts are read from their registered provider, never the
---legacy PlayerData ledger.
function Core.money.syncState(src)
    for _, account in ipairs(Config.money.types) do
        local balance = Core.money.getMoney(src, account)
        if balance ~= nil then Player(src).state:set(MONEY_STATE_PREFIX .. account, balance, true) end
    end
end

---Register the configured inventory authority for a physical money account.
---Only Config.inventory.provider may register it; any provider outage then
---fails closed instead of restoring a parallel PlayerData.money balance.
function Core.money.registerPhysicalCash(account)
    local caller = GetInvokingResource()
    if caller ~= Config.inventory.provider then return false, 'only the configured inventory provider may register physical cash' end
    if not validAccount(account) or account ~= Config.money.cashType then return false, 'only the configured cash account may be physical' end
    if physicalAccounts[account] and physicalAccounts[account] ~= caller then return false, 'physical cash provider already registered' end

    -- Preflight every online legacy balance before activation. A full
    -- inventory therefore refuses the switch rather than losing, duplicating,
    -- or silently hiding money.
    for src, player in pairs(PI.bySource) do
        local balance = math.floor(tonumber((player.PlayerData.money or {})[account]) or 0)
        if balance < 0 then return false, 'cash account cannot be negative' end
        if balance > 0 then
            local ok, canImport, err = pcall(function() return exports[caller]:physicalCashCanImport(src, account, balance) end)
            if not ok or not canImport then return false, err or 'could not reserve space for legacy cash' end
        end
    end

    physicalAccounts[account] = caller
    for src in pairs(PI.bySource) do
        local imported, err = Core.money.migratePhysicalCash(src)
        if not imported then
            -- This should be unreachable after preflight; retain the provider
            -- marker to fail closed and make intervention visible.
            print(('^1[qbcore:money]^7 physical cash import failed for %s: %s'):format(src, tostring(err)))
            return false, err or 'physical cash import failed'
        end
    end
    return true
end

function Core.money.unregisterPhysicalCash(account)
    local caller = GetInvokingResource()
    if physicalAccounts[account] ~= caller then return false, 'physical cash provider mismatch' end
    physicalAccounts[account] = nil
    return true
end

function Core.money.isPhysicalCash(account)
    return physicalAccounts[account] ~= nil
end

-- Called during provider activation and before a newly adopted player's first
-- snapshot. It converts a legacy money-column balance exactly once by setting
-- that column to zero only after qbinventory has accepted the matching item
-- stack. A full inventory rejects login/activation rather than losing money.
function Core.money.migratePhysicalCash(src)
    local player = PI.handle(src)
    if not player then return false, 'no such player' end
    for account, provider in pairs(physicalAccounts) do
        if GetResourceState(provider) ~= 'started' then return false, 'physical cash provider unavailable' end
        local balance = math.floor(tonumber((player.PlayerData.money or {})[account]) or 0)
        if balance < 0 then return false, 'cash account cannot be negative' end
        if balance > 0 then
            local ok, imported, err = pcall(function() return exports[provider]:physicalCashImport(src, account, balance) end)
            if not ok or not imported then return false, err or 'could not import legacy cash' end
            local set, setErr = PI._setPhysicalCashLedger(src, account, 0)
            if not set then return false, setErr end
        end
    end
    return true
end

---@param src integer
---@param account string
---@return number|nil
function Core.money.getMoney(src, account)
    local provider, providerErr = providerFor(account)
    if provider == false then return nil, providerErr end
    if provider then
        local ok, value = pcall(function() return exports[provider]:physicalCashGet(src, account) end)
        return ok and value or nil
    end
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
    local provider, providerErr = providerFor(account)
    if provider == false then return false, providerErr end
    if provider then
        if amount ~= math.floor(amount) then return false, 'physical cash amount must be whole' end
        local ok, added, err = pcall(function() return exports[provider]:physicalCashAdd(src, account, amount, reason) end)
        if not ok then return false, 'physical cash provider failed' end
        if not added then return false, err end
        emitMoneyChange(src, account, amount, 'add', reason)
        return true
    end
    local player = PI.handle(src)
    if not player then return false, 'no such player' end
    local newValue = (player.PlayerData.money[account] or 0) + amount
    Core.player.setPath(src, { 'money', account }, newValue)
    emitMoneyChange(src, account, amount, 'add', reason)
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
    local provider, providerErr = providerFor(account)
    if provider == false then return false, providerErr end
    if provider then
        if amount ~= math.floor(amount) then return false, 'physical cash amount must be whole' end
        local ok, removed, err = pcall(function() return exports[provider]:physicalCashRemove(src, account, amount, reason) end)
        if not ok then return false, 'physical cash provider failed' end
        if not removed then return false, err end
        emitMoneyChange(src, account, amount, 'remove', reason)
        return true
    end
    local player = PI.handle(src)
    if not player then return false, 'no such player' end
    local current = player.PlayerData.money[account] or 0
    local newValue = current - amount
    if newValue < floorFor(account) then
        return false, 'insufficient funds'
    end
    Core.player.setPath(src, { 'money', account }, newValue)
    emitMoneyChange(src, account, amount, 'remove', reason)
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
    local provider, providerErr = providerFor(account)
    if provider == false then return false, providerErr end
    if provider then
        if amount ~= math.floor(amount) then return false, 'physical cash amount must be whole' end
        if amount < 0 then return false, 'below account floor' end
        local current = Core.money.getMoney(src, account)
        if current == nil then return false, 'physical cash balance unavailable' end
        local ok, set, err = pcall(function() return exports[provider]:physicalCashSet(src, account, amount, reason) end)
        if not ok then return false, 'physical cash provider failed' end
        if not set then return false, err end
        emitMoneyChange(src, account, math.abs(amount - current), 'set', reason)
        return true
    end
    if amount < floorFor(account) then return false, 'below account floor' end
    local player = PI.handle(src)
    if not player then return false, 'no such player' end
    Core.player.setPath(src, { 'money', account }, amount)
    emitMoneyChange(src, account, amount, 'set', reason)
    return true
end

---Move money between two online players atomically-ish (remove then add; the
---remove failing aborts before any add).
---@return boolean, string|nil
function Core.money.transferMoney(fromSrc, toSrc, account, amount, reason)
    amount = tonumber(amount)
    if not validAccount(account) or not amount or amount <= 0 then return false, 'invalid transfer' end
    local provider, providerErr = providerFor(account)
    if provider == false then return false, providerErr end
    if provider then
        if amount ~= math.floor(amount) then return false, 'physical cash amount must be whole' end
        local ok, transferred, err = pcall(function() return exports[provider]:physicalCashTransfer(fromSrc, toSrc, account, amount, reason) end)
        if not ok then return false, 'physical cash provider failed' end
        if not transferred then return false, err end
        emitMoneyChange(fromSrc, account, amount, 'remove', reason)
        emitMoneyChange(toSrc, account, amount, 'add', reason)
        return true
    end
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
