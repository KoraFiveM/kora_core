-- Core.money (server realm) -- thin wrappers over the funnel. Every balance
-- change is Core.player.setPath(src, {'money', account}, newValue), so money
-- gets dirty-tracking + delta replication for free. Emits the legacy
-- QBCore:Server:OnMoneyChange event for compat.
--
-- Also owns the optional transaction tax (Config.money.tax): a percentage of
-- every taxable transaction is diverted to a banking account. See the "Transaction
-- tax" block below for the model.

local PI = CoreInternal.player
-- account -> kora_inventory resource. A registration survives an unexpected
-- provider stop so cash mutations fail closed instead of silently falling back
-- to a second ledger balance.
local physicalAccounts = {}
local MONEY_STATE_PREFIX = 'qbcore:money:'

local function validAccount(account)
    for _, a in ipairs(Config.money.types) do if a == account then return true end end
    return false
end

-- tonumber() alone lets NaN and +/-inf through ('1e999' parses to inf), and both
-- slip past every `<= 0` / floor comparison below (F#171).
local function finiteAmount(value)
    value = tonumber(value)
    if Kora.util.isFiniteNumber(value) then return value end
    return nil
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

-- Transaction tax
-- A slice of every taxable transaction is deposited into the banking account
-- named by Config.money.tax.account (the "government"), held by whatever
-- resource Config.money.tax.provider names -- qb-banking by default, but the
-- three export names it is reached through are configurable so any bank works.
--
-- The tax is always carved OUT of the transaction amount, never added on top:
--   remove    the player pays exactly `amount`, as they would untaxed, and the
--             government takes its cut off the top instead of the whole sum
--             simply vanishing;
--   add       the player receives `amount - tax`;
--   transfer  the sender pays `amount`, the recipient receives `amount - tax`.
-- Charging on top could make an existing call fail for insufficient funds; carving out
-- keeps the payer's side of every call site identical.
--
-- setMoney is NEVER taxed: it is an absolute assignment (admin edits, resets,
-- migrations), not a transaction.
--
-- Availability is failure-open by design. If the banking resource is down the
-- transaction goes through UNTAXED rather than failing or quietly destroying the
-- slice -- a bank outage must never cost a player money or block the economy.
local TAX_ACTIONS = { add = true, remove = true, transfer = true }
local TAX_REFUND_REASON = 'tax-refund'
-- Set once the government account is known to exist; cleared whenever a deposit
-- is rejected or the provider stops, so a restarted bank is re-checked.
local taxAccountReady = false
local taxWarnedAt = 0

-- Rate-limited: a bank that is down would otherwise print once per transaction.
local function taxWarn(message)
    local now = os.time()
    if now - taxWarnedAt < 60 then return end
    taxWarnedAt = now
    print(('^3[qbcore:money]^7 transaction tax skipped: %s'):format(message))
end

local function taxConfig()
    local cfg = Config.money.tax
    if type(cfg) ~= 'table' or not cfg.enabled then return nil end
    return cfg
end

-- An `accounts`/`actions` table is an explicit allow-list: a key that is absent
-- (or not `true`) is not taxed. Omitting the table entirely means "everything".
local function taxableAccount(cfg, account)
    if type(cfg.accounts) ~= 'table' then return true end
    return cfg.accounts[account] == true
end

local function taxableAction(cfg, action)
    if not TAX_ACTIONS[action] then return false end
    if type(cfg.actions) ~= 'table' then return true end
    return cfg.actions[action] == true
end

local function taxExportNames(cfg)
    local names = type(cfg.exports) == 'table' and cfg.exports or {}
    return names.add or 'AddMoney', names.get or 'GetAccount', names.create or 'CreateJobAccount'
end

---Banking resource to deposit into, or nil + why not. Never yields, so the
---money path can consult it inline before mutating a balance.
local function taxProvider(cfg)
    local resource = cfg.provider
    if type(resource) ~= 'string' or resource == '' then return nil, 'no banking provider configured' end
    if GetResourceState(resource) ~= 'started' then return nil, ('banking provider %s is not running'):format(resource) end
    return resource
end

---Configured tax rate for an account/action pair, as a 0..1 fraction. Returns 0
---when tax is off, the account is not taxable, or the action is not taxed. This
---reads config only -- it does not consult the banking resource's live state.
---@param account string|nil
---@param action string|nil -- 'add' | 'remove' | 'transfer'; nil skips the action check
---@return number
function Core.money.getTaxRate(account, action)
    local cfg = taxConfig()
    if not cfg then return 0 end
    if account ~= nil and not taxableAccount(cfg, account) then return 0 end
    if action ~= nil and not taxableAction(cfg, action) then return 0 end
    local rate = tonumber(cfg.rate) or 0
    if rate <= 0 then return 0 end
    return rate > 1 and 1 or rate
end

---Tax that would be carved out of `amount`. Pure -- safe to call from a shop UI
---to show a tax-inclusive breakdown. Floored, so the government never takes more
---than its strict share and a whole-number amount stays whole.
---@return number
function Core.money.calculateTax(amount, account, action)
    amount = tonumber(amount)
    if not amount or amount <= 0 then return 0 end
    local rate = Core.money.getTaxRate(account, action)
    if rate <= 0 then return 0 end
    local tax = math.floor(amount * rate)
    if tax <= 0 then return 0 end
    return tax > amount and math.floor(amount) or tax
end

---Banking account collected tax is deposited into, or nil when tax is disabled.
---@return string|nil
function Core.money.getTaxAccount()
    local cfg = taxConfig()
    return cfg and cfg.account or nil
end

---Deposit `amount` into the government banking account, creating that account
---through the provider if it does not exist yet.
---
---YIELDS -- the provider's deposit export writes to the database. Call it from a
---thread; the internal tax path already wraps it in one.
---@param amount number
---@param reason string|nil
---@return boolean, string|nil
function Core.money.collectTax(amount, reason)
    local cfg = taxConfig()
    if not cfg then return false, 'transaction tax is disabled' end
    amount = finiteAmount(amount)
    if not amount or amount <= 0 then return false, 'amount must be positive' end
    local resource, unavailable = taxProvider(cfg)
    if not resource then return false, unavailable end

    local addFn, getFn, createFn = taxExportNames(cfg)
    if not taxAccountReady then
        local ok, account = pcall(function() return exports[resource][getFn](exports[resource], cfg.account) end)
        if ok and account then
            taxAccountReady = true
        elseif cfg.autoCreateAccount == false then
            return false, ('banking account %s does not exist'):format(tostring(cfg.account))
        else
            local created, result = pcall(function() return exports[resource][createFn](exports[resource], cfg.account, 0) end)
            if not created or not result then return false, ('could not create banking account %s'):format(tostring(cfg.account)) end
            taxAccountReady = true
        end
    end

    local ok, deposited = pcall(function() return exports[resource][addFn](exports[resource], cfg.account, amount, reason or 'tax') end)
    if not ok or not deposited then
        -- A restarted or mid-failure bank invalidates the cached account marker.
        taxAccountReady = false
        return false, ('banking provider %s rejected the tax deposit'):format(resource)
    end
    TriggerEvent('qbcore:server:taxCollected', cfg.account, amount, reason)
    return true
end

---Bank `tax` off the critical path. The deposit hits the database, so it must
---not run inline on a money mutation. `refund` is the compensation applied when
---the deposit fails: withheld money goes back to the player it was withheld
---from rather than disappearing into a failed bank call.
local function dispatchTax(tax, reason, refund)
    if tax <= 0 then return end
    CreateThread(function()
        local ok, err = Core.money.collectTax(tax, reason)
        if ok then return end
        print(('^1[qbcore:money]^7 tax deposit of %s failed: %s'):format(tax, tostring(err)))
        if refund then refund() end
    end)
end

---Tax to withhold from this transaction, after the live provider check. Returns
---0 whenever the transaction must go through untaxed.
local function taxFor(account, amount, action, ignoreTax)
    if ignoreTax then return 0 end
    local cfg = taxConfig()
    if not cfg then return 0 end
    local tax = Core.money.calculateTax(amount, account, action)
    if tax <= 0 then return 0 end
    local resource, unavailable = taxProvider(cfg)
    if not resource then taxWarn(unavailable); return 0 end
    return tax
end

---Preview the tax actually applied while the banking provider is available.
---Unlike calculateTax, this follows the money APIs' untaxed outage behavior.
function Core.money.getTransactionTax(amount, account, action)
    return taxFor(account, amount, action)
end

AddEventHandler('onResourceStop', function(resource)
    local cfg = Config.money.tax
    if type(cfg) == 'table' and resource == cfg.provider then taxAccountReady = false end
end)

-- Physical-cash mirror
-- While kora_inventory owns an account, the PlayerData.money ledger for it is a
-- constant 0 and the real balance is the item stack. Stock qb-* scripts read
-- PlayerData.money.cash directly, so the REAL balance is mirrored into the
-- legacy-shaped server view and into the replicated client PlayerData. The
-- ledger (and therefore persistence) is never touched: the mirror is overlaid
-- onto the compat view and onto the outgoing replication ops/snapshot only.
-- Refreshes are event-driven (every Core.money change and every
-- qbcore:server:inventoryChanged); nothing polls.
local mirrors = setmetatable({}, { __mode = 'k' })   -- player -> { real = {account=n}, sent = {account=n} }

local function mirrorState(player)
    local st = mirrors[player]
    if not st then st = { real = {}, sent = {} }; mirrors[player] = st end
    return st
end

---Recompute the real balance of every physical account for one player. Returns
---the state table, or nil when no account is physical.
local function refreshMirror(player)
    if next(physicalAccounts) == nil then mirrors[player] = nil; return nil end
    local st = mirrorState(player)
    local changed = false
    for account in pairs(physicalAccounts) do
        local balance = Core.money.getMoney(player.source, account)
        if balance ~= nil and st.real[account] ~= balance then
            st.real[account] = balance
            changed = true
            if Core.compat.onPlayerDataChanged then
                Core.compat.onPlayerDataChanged(player.source, { 'money', account }, balance)
            end
        end
    end
    if changed then Core.replication._touch(player) end
    return st
end

---Overlay the mirrored real balances onto a legacy money table (in place).
---@param src integer
---@param money table|nil
---@return table|nil
function Core.money._mirrorOverlay(src, money)
    local player = PI.handle(src)
    if type(money) ~= 'table' or not player then return money end
    local st = mirrors[player] or refreshMirror(player)
    if st then
        for account, balance in pairs(st.real) do
            if physicalAccounts[account] then money[account] = balance end
        end
    end
    return money
end

---The balance the mirror last published for an account (what a script reading
---PlayerData.money saw), without querying the inventory. nil when not mirrored.
---@param src integer
---@param account string
---@return number|nil
function Core.money._mirroredBalance(src, account)
    local player = PI.handle(src)
    if not player or not physicalAccounts[account] then return nil end
    local st = mirrors[player] or refreshMirror(player)
    return st and st.real[account] or nil
end

---Called by replication at flush: make every outgoing op carry the real balance
---and append one for an account whose real balance has not been sent yet.
function PI.mirrorOps(player, ops)
    local st = mirrors[player]
    if not st then return end
    for account, balance in pairs(st.real) do
        if not physicalAccounts[account] then goto continue end
        local covered = false
        for _, op in ipairs(ops) do
            if op.p[1] == 'money' and not op.d then
                if #op.p == 1 and type(op.v) == 'table' then
                    local copy = {}
                    for k, v in pairs(op.v) do copy[k] = v end
                    copy[account] = balance
                    op.v, covered = copy, true
                elseif #op.p == 2 and op.p[2] == account then
                    op.v, covered = balance, true
                end
            end
        end
        if not covered and st.sent[account] ~= balance then
            ops[#ops + 1] = { p = { 'money', account }, v = balance }
        end
        st.sent[account] = balance
        ::continue::
    end
end

---Snapshot payload for a (re)syncing client: PlayerData with real balances.
function PI.mirrorSnapshot(player)
    local st = refreshMirror(player)
    if not st or next(st.real) == nil then return player.PlayerData end
    local data = {}
    for k, v in pairs(player.PlayerData) do data[k] = v end
    data.money = Core.money._mirrorOverlay(player.source, Core.util.deepClone(player.PlayerData.money or {}))
    for account, balance in pairs(st.real) do st.sent[account] = balance end
    return data
end

AddEventHandler('qbcore:server:inventoryChanged', function(src)
    if next(physicalAccounts) == nil then return end
    local player = PI.handle(src)
    if player then refreshMirror(player) end
end)

local function emitMoneyChange(src, account, amount, action, reason)
    local balance = Core.money.getMoney(src, account)
    if physicalAccounts[account] then
        local player = PI.handle(src)
        if player then refreshMirror(player) end
    end
    if balance ~= nil then Player(src).state:set(MONEY_STATE_PREFIX .. account, balance, true) end
    TriggerEvent('QBCore:Server:OnMoneyChange', src, account, amount, action, reason)
    TriggerClientEvent('QBCore:Client:OnMoneyChange', src, account, amount, action, reason)
    -- Legacy hook: stock qb-hud's money popup listens ONLY to this event (kora_hud uses the statebag).
    local isRemove = action == 'remove'
    TriggerClientEvent('hud:client:OnMoneyChange', src, account, amount, isRemove)
    -- Legacy qb-phone hook: fired specifically on a bank-account removal.
    if account == 'bank' and isRemove then
        TriggerClientEvent('qb-phone:client:RemoveBankMoney', src, amount)
    end
end

---Publish authoritative balances for state-bag consumers such as kora_hud.
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
    for _, player in pairs(PI.bySource) do refreshMirror(player) end
    return true
end

function Core.money.unregisterPhysicalCash(account)
    local caller = GetInvokingResource()
    if physicalAccounts[account] ~= caller then return false, 'physical cash provider mismatch' end
    physicalAccounts[account] = nil
    -- Hand the legacy view and the client mirror back to the ledger value.
    for src, player in pairs(PI.bySource) do
        mirrors[player] = nil
        local ledger = (player.PlayerData.money or {})[account]
        if Core.compat.onPlayerDataChanged then Core.compat.onPlayerDataChanged(src, { 'money', account }, ledger) end
        Core.replication._queueOp(player, { 'money', account }, ledger)
    end
    return true
end

function Core.money.isPhysicalCash(account)
    return physicalAccounts[account] ~= nil
end

-- Called during provider activation and before a newly adopted player's first
-- snapshot. It converts a legacy money-column balance exactly once by setting
-- that column to zero only after kora_inventory has accepted the matching item
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

---Credits a stored balance atomically; offline credits retain the untaxed legacy behavior.
---@param citizenid string
---@param account string
---@param amount number
---@return boolean, string|nil
function Core.money.addOfflineMoney(citizenid, account, amount)
    if type(citizenid) ~= 'string' or citizenid == '' then return false, 'invalid citizenid' end
    if not validAccount(account) then return false, 'invalid account' end
    amount = tonumber(amount)
    if not amount or amount ~= amount or amount <= 0 or amount == math.huge then return false, 'amount must be positive and finite' end
    if PI.byCitizenId[citizenid] then return false, 'player is online' end
    if Core.persistence._hasColumnOperation and Core.persistence._hasColumnOperation(citizenid) then return false, 'player data is busy' end
    if Core.persistence._persistentColumnsAvailable then
        local available, err = Core.persistence._persistentColumnsAvailable(citizenid)
        if not available then return false, err end
    end
    if PI.byCitizenId[citizenid] then return false, 'player is online' end
    local path = '$.' .. json.encode(account)
    if Core.persistence._beginOfflineWrite and not Core.persistence._beginOfflineWrite(citizenid) then return false, 'player data is busy' end
    local called, result, err = pcall(Kora.sql.update,
        'UPDATE `players` SET `money` = JSON_SET(`money`, ?, '
            .. 'COALESCE(JSON_EXTRACT(`money`, ?), 0) + ?) '
            .. 'WHERE `citizenid` = ? AND `deleted_at` IS NULL',
        { path, path, amount, citizenid }
    )
    if Core.persistence._endOfflineWrite then Core.persistence._endOfflineWrite(citizenid) end
    if not called then return false, 'offline money provider failed' end
    if result == nil or result == 0 then return false, err or 'player not found' end
    return true
end

---Adds a positive amount. `amount` is the GROSS figure: when the transaction
---tax applies the player receives `amount - tax` and the tax is banked.
---@param src integer
---@param account string
---@param amount number
---@param reason string|nil
---@param ignoreTax boolean|nil -- true exempts this call from the transaction tax
---@return boolean, string|nil
function Core.money.addMoney(src, account, amount, reason, ignoreTax)
    if not validAccount(account) then return false, 'invalid account' end
    amount = finiteAmount(amount)
    if not amount or amount <= 0 then return false, 'amount must be positive' end
    local provider, providerErr = providerFor(account)
    if provider == false then return false, providerErr end

    local tax = taxFor(account, amount, 'add', ignoreTax)
    local net = amount - tax
    -- The tax was withheld from THIS player, so a failed deposit goes back here.
    local refund = tax > 0 and function() Core.money.addMoney(src, account, tax, TAX_REFUND_REASON, true) end or nil

    if provider then
        if amount ~= math.floor(amount) then return false, 'physical cash amount must be whole' end
        -- net is 0 only at a 100% rate: nothing reaches the player, tax takes it all.
        if net > 0 then
            local ok, added, err = pcall(function() return exports[provider]:physicalCashAdd(src, account, net, reason) end)
            if not ok then return false, 'physical cash provider failed' end
            if not added then return false, err end
            emitMoneyChange(src, account, net, 'add', reason)
        end
        dispatchTax(tax, reason, refund)
        return true
    end
    local player = PI.handle(src)
    if not player then return false, 'no such player' end
    if net > 0 then
        local newValue = (player.PlayerData.money[account] or 0) + net
        local changed, err = Core.player.setPath(src, { 'money', account }, newValue)
        if not changed then return false, err end
        emitMoneyChange(src, account, net, 'add', reason)
    end
    dispatchTax(tax, reason, refund)
    return true
end

---Removes a positive amount. The player always pays exactly `amount`; when the
---transaction tax applies, its slice of that is banked instead of destroyed, so
---the player-facing cost is identical either way.
---@param src integer
---@param account string
---@param amount number
---@param reason string|nil
---@param ignoreTax boolean|nil -- true exempts this call from the transaction tax
---@return boolean, string|nil
function Core.money.removeMoney(src, account, amount, reason, ignoreTax)
    if not validAccount(account) then return false, 'invalid account' end
    amount = finiteAmount(amount)
    if not amount or amount <= 0 then return false, 'amount must be positive' end
    local provider, providerErr = providerFor(account)
    if provider == false then return false, providerErr end

    -- No refund closure on a removal: the money left the player either way, so a
    -- failed deposit just destroys the slice exactly as an untaxed remove would.
    local tax = taxFor(account, amount, 'remove', ignoreTax)

    if provider then
        if amount ~= math.floor(amount) then return false, 'physical cash amount must be whole' end
        local ok, removed, err = pcall(function() return exports[provider]:physicalCashRemove(src, account, amount, reason) end)
        if not ok then return false, 'physical cash provider failed' end
        if not removed then return false, err end
        emitMoneyChange(src, account, amount, 'remove', reason)
        dispatchTax(tax, reason, nil)
        return true
    end
    local player = PI.handle(src)
    if not player then return false, 'no such player' end
    local current = player.PlayerData.money[account] or 0
    local newValue = current - amount
    if newValue < floorFor(account) then
        return false, 'insufficient funds'
    end
    local changed, err = Core.player.setPath(src, { 'money', account }, newValue)
    if not changed then return false, err end
    emitMoneyChange(src, account, amount, 'remove', reason)
    dispatchTax(tax, reason, nil)
    return true
end

---Sets an exact balance. NEVER taxed -- this is an absolute assignment (admin
---edit, reset, migration), not a transaction, so there is no `ignoreTax` param.
---@param src integer
---@param account string
---@param amount number
---@param reason string|nil
---@return boolean, string|nil
function Core.money.setMoney(src, account, amount, reason)
    if not validAccount(account) then return false, 'invalid account' end
    amount = finiteAmount(amount)
    if not amount then return false, 'amount must be a finite number' end
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
    local changed, err = Core.player.setPath(src, { 'money', account }, amount)
    if not changed then return false, err end
    emitMoneyChange(src, account, amount, 'set', reason)
    return true
end

---Move money between two online players atomically-ish (remove then add; the
---remove failing aborts before any add). With the transaction tax on, the sender
---pays `amount` and the recipient receives `amount - tax`.
---@param fromSrc integer
---@param toSrc integer
---@param account string
---@param amount number
---@param reason string|nil
---@param ignoreTax boolean|nil -- true exempts this call from the transaction tax
---@return boolean, string|nil
local function transferMoney(fromSrc, toSrc, account, amount, reason, ignoreTax)
    amount = finiteAmount(amount)
    if not validAccount(account) or not amount or amount <= 0 then return false, 'invalid transfer' end
    local provider, providerErr = providerFor(account)
    if provider == false then return false, providerErr end

    local tax = taxFor(account, amount, 'transfer', ignoreTax)
    local net = amount - tax
    -- The tax is charged to the SENDER (they paid `amount` while the recipient
    -- received `net`), so a failed deposit refunds them -- leaving exactly an
    -- untaxed transfer of `net`, with no money created or destroyed.
    local refund = tax > 0 and function() Core.money.addMoney(fromSrc, account, tax, TAX_REFUND_REASON, true) end or nil

    if provider then
        if amount ~= math.floor(amount) then return false, 'physical cash amount must be whole' end
        -- Tax off the sender first, then move the net: costs the sender what an untaxed
        -- transfer of `amount` would, and a failed move has one thing to compensate.
        if tax > 0 then
            local ok, removed, err = pcall(function() return exports[provider]:physicalCashRemove(fromSrc, account, tax, reason) end)
            if not ok then return false, 'physical cash provider failed' end
            if not removed then return false, err end
        end
        if net > 0 then
            local ok, transferred, err = pcall(function() return exports[provider]:physicalCashTransfer(fromSrc, toSrc, account, net, reason) end)
            if not ok or not transferred then
                if tax > 0 then pcall(function() return exports[provider]:physicalCashAdd(fromSrc, account, tax, TAX_REFUND_REASON) end) end
                return false, ok and err or 'physical cash provider failed'
            end
        end
        emitMoneyChange(fromSrc, account, amount, 'remove', reason)
        if net > 0 then emitMoneyChange(toSrc, account, net, 'add', reason) end
        dispatchTax(tax, reason, refund)
        return true
    end
    -- Tax is settled once here, so both legs run exempt.
    local ok, err = Core.money.removeMoney(fromSrc, account, amount, reason, true)
    if not ok then return false, err end
    if net > 0 then
        local ok2, err2 = Core.money.addMoney(toSrc, account, net, reason, true)
        if not ok2 then
            -- Refund on failure to add -- the full amount, tax included, since
            -- nothing has been banked yet.
            Core.money.addMoney(fromSrc, account, amount, 'transfer-refund', true)
            return false, err2
        end
    end
    dispatchTax(tax, reason, refund)
    return true
end

function Core.money.transferMoney(fromSrc, toSrc, account, amount, reason, ignoreTax)
    if not Core.persistence._beginMoneyTransfer then return transferMoney(fromSrc, toSrc, account, amount, reason, ignoreTax) end
    local from, to = PI.handle(fromSrc), PI.handle(toSrc)
    if not from or not to then return false, 'no such player' end
    local citizenids = { from.citizenid, to.citizenid }
    if not Core.persistence._beginMoneyTransfer(citizenids) then return false, 'player data is busy' end
    local result = table.pack(pcall(transferMoney, fromSrc, toSrc, account, amount, reason, ignoreTax))
    Core.persistence._endMoneyTransfer(citizenids)
    if not result[1] then error(result[2], 0) end
    return table.unpack(result, 2, result.n)
end
