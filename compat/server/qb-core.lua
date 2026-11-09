local PI = CoreInternal.player

local isCallable = Kora.util.isCallable

local provideExport = Kora.compat.provideExport

local function exposePlayerMethods(player, handle)
    for name, fn in pairs(player.Functions) do
        if handle then
            local method = fn
            fn = function(...)
                if PI.handle(handle.source) ~= handle then return false, 'player is no longer loaded' end
                return method(...)
            end
            player.Functions[name] = fn
        end
        if player[name] == nil then
            player[name] = function(first, ...)
                if first == player or (type(first) == 'table' and type(first.PlayerData) == 'table'
                    and first.Functions and first.PlayerData.citizenid == player.PlayerData.citizenid
                    and first.PlayerData.source == player.PlayerData.source) then
                    return fn(...)
                end
                return fn(first, ...)
            end
        end
    end
end

local function sameValue(a, b)
    if a == b then return true end
    if type(a) ~= 'table' or type(b) ~= 'table' then return false end
    for key, value in pairs(a) do if not sameValue(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

local function legacyView(src, playerData)
    local view = Core.compat.toLegacyPlayerData(Core.util.deepClone(playerData))
    if view.items == nil then view.items = {} end
    if type(view.money) == 'table' and Core.money._mirrorOverlay then Core.money._mirrorOverlay(src, view.money) end
    return view
end

local immutableRoots = { source = true, citizenid = true, license = true, cid = true }

local SETPLAYERDATA_REASON = 'qb-compat-setplayerdata'

local function writeLegacyMoney(src, handle, value)
    if type(value) ~= 'table' then return false, 'money must be a table' end
    local ledger = handle.PlayerData.money or {}
    local nextMoney, deltas = {}, {}
    for account, amount in pairs(value) do
        if Core.money.isPhysicalCash(account) then
            local number = tonumber(amount)
            if not number or number ~= number or number == math.huge or number == -math.huge then
                return false, 'physical cash amount must be a number'
            end
            local seen = Core.money._mirroredBalance(src, account)
            if seen == nil then seen = Core.money.getMoney(src, account) end
            if seen == nil then return false, 'physical cash balance unavailable' end
            local delta = number - seen
            delta = delta >= 0 and math.floor(delta) or -math.floor(-delta)
            if delta ~= 0 then deltas[#deltas + 1] = { account = account, delta = delta } end
            nextMoney[account] = ledger[account]
        else
            nextMoney[account] = amount
        end
    end
    for account, amount in pairs(ledger) do
        if nextMoney[account] == nil and Core.money.isPhysicalCash(account) then nextMoney[account] = amount end
    end

    for _, change in ipairs(deltas) do
        local available = Core.money.getMoney(src, change.account)
        if available == nil then return false, 'physical cash balance unavailable' end
        if change.delta < 0 and -change.delta > available then
            print(('^3[qbcore:qb-core-bridge]^7 refused SetPlayerData money write for %s: removes %d %s but only %d is available'):format(
                tostring(src), -change.delta, change.account, available))
            return false, 'insufficient funds'
        end
    end
    local applied = {}
    local function rollback()
        for i = #applied, 1, -1 do
            local change = applied[i]
            if change.delta > 0 then
                Core.money.removeMoney(src, change.account, change.delta, SETPLAYERDATA_REASON .. '-rollback', true)
            else
                Core.money.addMoney(src, change.account, -change.delta, SETPLAYERDATA_REASON .. '-rollback', true)
            end
        end
    end
    for _, change in ipairs(deltas) do
        local ok, err
        if change.delta > 0 then
            ok, err = Core.money.addMoney(src, change.account, change.delta, SETPLAYERDATA_REASON, true)
        else
            ok, err = Core.money.removeMoney(src, change.account, -change.delta, SETPLAYERDATA_REASON, true)
        end
        if not ok then rollback(); return false, err end
        applied[#applied + 1] = change
    end

    if sameValue(nextMoney, ledger) then return true end
    local data = Core.compat.fromLegacyPlayerData({ money = nextMoney })
    local ok, err = Core.player.setPath(src, { 'money' }, data.money)
    if not ok then rollback() end
    return ok, err
end

local function writeLegacyRoot(src, key, value)
    if type(key) ~= 'string' then return false, 'player data key must be a string' end
    if immutableRoots[key] then return false, 'player identity is immutable' end
    local handle = PI.handle(src)
    if not handle then return false, 'no such player' end
    if key == 'money' then return writeLegacyMoney(src, handle, value) end
    local data = Core.compat.fromLegacyPlayerData({ [key] = value })
    return Core.player.setPath(src, { key }, data[key])
end

local function buildQBPlayer(src)
    local handle = PI.handle(src)
    if not handle then return nil end

    local self = { PlayerData = legacyView(src, handle.PlayerData), Offline = false }
    local F = {}
    self.Functions = F

    local function publishWrite(ok, err, key)
        if ok then F.UpdateClient(key) end
        return ok, err
    end

    function F.GetName()
        local charinfo = handle.PlayerData.charinfo
        if type(charinfo) == 'table' and charinfo.firstname and charinfo.lastname then
            return charinfo.firstname .. ' ' .. charinfo.lastname
        end
        return handle.PlayerData.name
    end
    function F.GetPlayerData() return legacyView(src, handle.PlayerData) end

    local function lowered(name) return type(name) == 'string' and name:lower() or name end
    function F.SetJob(name, grade) return Core.jobs.setJob(src, lowered(name), Core.compat.fromLegacyGradeLevel(grade)) end
    function F.SetGang(name, grade) return Core.jobs.setGang(src, lowered(name), Core.compat.fromLegacyGradeLevel(grade)) end
    function F.SetJobDuty(onDuty) return Core.jobs.setJobDuty(src, onDuty) end
    local function setRoleData(kind, key, value)
        if type(key) ~= 'string' then return false end
        local role = Core.compat.toLegacyJobOrGang(Core.util.deepClone(handle.PlayerData[kind]), kind == 'job' and 'jobs' or 'gangs')
        role[key] = value
        local ok, err = writeLegacyRoot(src, kind, role)
        return publishWrite(ok, err, kind)
    end
    function F.SetJobData(k, v)
        if k == 'onduty' then return Core.jobs.setJobDuty(src, v and true or false) end
        return setRoleData('job', k, v)
    end
    function F.SetGangData(k, v) return setRoleData('gang', k, v) end

    local function moneyOp(op, t, amount, reason, ignoreTax)
        t = lowered(t)
        local n = tonumber(amount)
        if not n or n < 0 then return false end
        if n == 0 then
            for _, account in ipairs(Config.money.types) do if account == t then return true end end
            return false
        end
        return Core.money[op](src, t, n, reason, ignoreTax)
    end
    function F.AddMoney(t, amount, reason, ignoreTax) return moneyOp('addMoney', t, amount, reason, ignoreTax) end
    function F.RemoveMoney(t, amount, reason, ignoreTax) return moneyOp('removeMoney', t, amount, reason, ignoreTax) end
    function F.SetMoney(t, amount, reason) return Core.money.setMoney(src, t, amount, reason or 'qb-compat-setmoney') end
    function F.GetMoney(t) return Core.money.getMoney(src, t) end

    function F.AddItem(name, amount, slot, info) return Core.inventory.addItem(src, name, amount, slot, info) end
    function F.RemoveItem(name, amount, slot) return Core.inventory.removeItem(src, name, amount, slot) end
    function F.GetItemByName(name) return Core.inventory.getItemByName(src, name) end
    function F.GetItemsByName(name) return Core.inventory.getItemsByName(src, name) end
    function F.GetItemBySlot(slot) return Core.inventory.getItemBySlot(src, slot) end
    F.GetItemInSlot = F.GetItemBySlot
    function F.ClearInventory(keep) return Core.inventory.clearInventory(src, keep) end
    function F.SetInventory(items) return Core.inventory.setItems(src, items) end

    function F.SetMetaData(k, v)
        if k == 'hunger' or k == 'thirst' then v = math.min(100, math.max(0, tonumber(v) or 0)) end
        local ok, err = Core.metadata.setMetaData(src, k, Core.util.deepClone(v))
        return publishWrite(ok, err, 'metadata')
    end
    function F.GetMetaData(k) return Core.metadata.getMetaData(src, k) end

    function F.SetCharInfo(k, v)
        local ok, err = Core.player.setPath(src, { 'charinfo', k }, Core.util.deepClone(v))
        return publishWrite(ok, err, 'charinfo')
    end
    function F.SetCreditCard(number) return F.SetCharInfo('card', number) end

    function F.SetPlayerData(key, value)
        local column = PI.COLUMN_FOR[key]
        if not column and key ~= 'optin' and Config.compat.warnOnUnknownRoot then
            print(("^3[qbcore:qb-core-bridge]^7 SetPlayerData('%s', ...) targets an unknown root key with no DB "
                .. "column mapping; it will not persist."):format(tostring(key)))
        end
        local ok, err = writeLegacyRoot(src, key, value)
        return publishWrite(ok, err, key)
    end

    local function reconcilePlayerData(key, ...)
        if PI.handle(src) ~= handle then return false, 'player is no longer loaded' end
        if key == 'all' then key = nil end
        if key ~= nil and type(key) ~= 'string' then return false, 'player data key must be a string' end
        if key and select('#', ...) > 0 then self.PlayerData[key] = Core.util.deepClone((...)) end
        local current = legacyView(src, handle.PlayerData)
        local roots = {}
        if key then roots[key] = true else
            for root in pairs(current) do roots[root] = true end
            for root in pairs(self.PlayerData) do roots[root] = true end
        end
        for root in pairs(roots) do
            if not sameValue(current[root], self.PlayerData[root]) then
                local ok, err = writeLegacyRoot(src, root, self.PlayerData[root])
                if not ok then
                    self.PlayerData[root] = Core.util.deepClone(current[root])
                    return false, err
                end
                if root == 'money' then
                    self.PlayerData.money = legacyView(src, handle.PlayerData).money
                end
            end
        end
        return true
    end

    function F.UpdateClient(key, ...)
        if key == 'all' then key = nil end
        local ok, err = reconcilePlayerData(key, ...)
        if not ok then return false, err end
        local data = legacyView(src, handle.PlayerData)
        local eventKey, value = key or 'all', data
        if key then value = data[key] end
        if not key then TriggerEvent('QBCore:Player:SetPlayerData', data) end
        TriggerEvent('QBCore:Server:OnPlayerUpdated', src, eventKey, value)
        local derivedFromDelta = false
        if (key == 'job' or key == 'gang') and Config.compat.jobUpdateEventSource ~= 'server' then
            for _, op in pairs(handle._pendingOps) do
                if op.p[1] == key then derivedFromDelta = true; break end
            end
        end
        if derivedFromDelta then return true end
        SetTimeout(0, function()
            if PI.handle(src) == handle then
                TriggerClientEvent('QBCore:Client:OnPlayerUpdated', src, eventKey, value)
            end
        end)
        return true
    end
    F.UpdatePlayerData = F.UpdateClient

    function F.Save()
        local ok, err = reconcilePlayerData()
        if not ok then return false, err end
        Core.persistence.saveNow(handle)
        return true
    end
    function F.Logout() return Core.player.logout(src) end

    function F.Notify(text, type_, length) TriggerClientEvent('QBCore:Notify', src, text, type_, length) end
    function F.HasItem(items, amount) return Core.inventory.hasItem(src, items, amount) end

    function F.AddJobReputation(amount)
        amount = tonumber(amount)
        if not amount or amount ~= amount or math.abs(amount) == math.huge then return end
        local job = handle.PlayerData.job.name
        local reps = Core.util.deepClone(Core.metadata.getMetaData(src, 'jobrep') or {})
        reps[job] = (tonumber(reps[job]) or 0) + amount
        local ok, err = Core.player.setPath(src, { 'metadata', 'jobrep' }, reps)
        if not ok then return false, err end
        F.UpdatePlayerData()
    end
    F.AddJobRep = F.AddJobReputation

    function F.GetRep(rep)
        local reps = Core.metadata.getMetaData(src, 'rep') or {}
        return reps[rep] or 0
    end
    function F.AddRep(rep, amount)
        amount = tonumber(amount)
        if not rep or not amount then return end
        local reps = Core.util.deepClone(Core.metadata.getMetaData(src, 'rep') or {})
        reps[rep] = math.max(0, (reps[rep] or 0) + amount)
        local ok, err = Core.metadata.setMetaData(src, 'rep', reps)
        if not ok then return false, err end
    end
    function F.RemoveRep(rep, amount)
        amount = tonumber(amount)
        if not rep or not amount then return end
        local reps = Core.util.deepClone(Core.metadata.getMetaData(src, 'rep') or {})
        reps[rep] = math.max(0, (reps[rep] or 0) - amount)
        local ok, err = Core.metadata.setMetaData(src, 'rep', reps)
        if not ok then return false, err end
    end

    function F.AddMethod(name, method)
        if type(name) ~= 'string' or not isCallable(method) then return false end
        self[name], F[name] = method, method
        return true
    end
    function F.AddField(name, data)
        if type(name) ~= 'string' or isCallable(data) then return false end
        self[name] = data
        return true
    end

    exposePlayerMethods(self, handle)

    return self
end

local function buildOfflinePlayer(data)
    local self = { PlayerData = Core.compat.toLegacyPlayerData(Core.util.deepClone(data)), Offline = true }
    local F = {}
    self.Functions = F

    function F.GetPlayerData() return self.PlayerData end
    function F.GetName()
        local ci = self.PlayerData.charinfo or {}
        return (ci.firstname or '') .. ' ' .. (ci.lastname or '')
    end
    function F.UpdateClient() end
    F.UpdatePlayerData = F.UpdateClient

    local function setRole(kind, name, grade)
        name = type(name) == 'string' and name:lower() or name
        local definition = Core.registry.getShared(kind == 'job' and 'jobs' or 'gangs', name)
        if not definition then return false end
        local level = math.max(math.floor(tonumber(grade) or 0), 0)
        local gradeInfo = definition.grades[level + 1]
        local role = {
            name = name, label = definition.label, isboss = gradeInfo and gradeInfo.isboss or false,
            grade = {
                name = gradeInfo and gradeInfo.name or 'No Grades', level = level,
                payment = gradeInfo and gradeInfo.payment or 0,
                isboss = gradeInfo and gradeInfo.isboss or false,
            },
        }
        if kind == 'job' then
            role.type = definition.type or 'none'
            role.onduty = definition.defaultDuty or false
        end
        self.PlayerData[kind] = role
        return true
    end

    function F.SetJob(name, grade) return setRole('job', name, grade) end
    function F.SetGang(name, grade) return setRole('gang', name, grade) end
    function F.SetJobDuty(onDuty)
        if self.PlayerData.job then self.PlayerData.job.onduty = not not onDuty end
    end
    function F.SetJobData(key, value) self.PlayerData.job[key] = value; return true end
    function F.SetGangData(key, value) self.PlayerData.gang[key] = value; return true end
    function F.SetPlayerData(key, value)
        if type(key) ~= 'string' then return false end
        self.PlayerData[key] = value
        return true
    end
    function F.SetMetaData(key, value)
        if type(key) ~= 'string' then return false end
        self.PlayerData.metadata = self.PlayerData.metadata or {}
        if key == 'hunger' or key == 'thirst' then value = math.min(100, math.max(0, tonumber(value) or 0)) end
        self.PlayerData.metadata[key] = value
        return true
    end
    function F.GetMetaData(key) return (self.PlayerData.metadata or {})[key] end
    function F.SetCharInfo(key, value)
        self.PlayerData.charinfo = self.PlayerData.charinfo or {}
        self.PlayerData.charinfo[key] = value
        return true
    end
    function F.SetCreditCard(number) return F.SetCharInfo('card', number) end

    function F.GetMoney(moneyType) return (self.PlayerData.money or {})[moneyType] end
    function F.SetMoney(moneyType, amount)
        amount = tonumber(amount)
        if not amount then return false end
        self.PlayerData.money = self.PlayerData.money or {}
        if self.PlayerData.money[moneyType] == nil then return false end
        self.PlayerData.money[moneyType] = amount
        return true
    end
    function F.AddMoney(moneyType, amount)
        amount = tonumber(amount)
        if not amount or amount < 0 then return false end
        return F.SetMoney(moneyType, (F.GetMoney(moneyType) or 0) + amount)
    end
    function F.RemoveMoney(moneyType, amount)
        amount = tonumber(amount)
        local current = F.GetMoney(moneyType)
        if not amount or amount < 0 or current == nil then return false end
        local nextValue = current - amount
        if not Config.money.allowNegative[moneyType] and nextValue < 0 then return false end
        if nextValue < Config.money.minusLimit then return false end
        return F.SetMoney(moneyType, nextValue)
    end

    local function itemMatches(item, name) return item and item.name == name end
    function F.GetItemBySlot(slot) return (self.PlayerData.items or {})[tonumber(slot)] end
    F.GetItemInSlot = F.GetItemBySlot
    function F.GetItemByName(name)
        for _, item in pairs(self.PlayerData.items or {}) do if itemMatches(item, name) then return item end end
    end
    function F.GetItemsByName(name)
        local out = {}
        for _, item in pairs(self.PlayerData.items or {}) do if itemMatches(item, name) then out[#out + 1] = item end end
        return out
    end
    function F.HasItem(items, amount)
        local names = type(items) == 'table' and items or { items }
        for _, name in ipairs(names) do
            local count = 0
            for _, item in pairs(self.PlayerData.items or {}) do
                if itemMatches(item, name) then count = count + (item.amount or 0) end
            end
            if count < (amount or 1) then return false end
        end
        return true
    end
    function F.SetInventory(items) self.PlayerData.items = items or {}; return true end
    function F.ClearInventory(keep)
        local wanted, kept = {}, {}
        for _, name in pairs(keep or {}) do wanted[name] = true end
        for slot, item in pairs(self.PlayerData.items or {}) do if wanted[item.name] then kept[slot] = item end end
        self.PlayerData.items = kept
        return true
    end
    function F.AddItem(name, amount, slot, info)
        self.PlayerData.items = self.PlayerData.items or {}
        slot = tonumber(slot) or (#self.PlayerData.items + 1)
        self.PlayerData.items[slot] = { name = name, amount = amount or 1, slot = slot, info = info or {} }
        return true
    end
    function F.RemoveItem(name, amount, slot)
        amount = amount or 1
        local item = slot and self.PlayerData.items[slot] or F.GetItemByName(name)
        if not item or item.amount < amount then return false end
        item.amount = item.amount - amount
        if item.amount == 0 then self.PlayerData.items[item.slot] = nil end
        return true
    end

    function F.AddJobReputation(amount)
        amount = tonumber(amount)
        if not amount or amount ~= amount or math.abs(amount) == math.huge then return end
        self.PlayerData.metadata = self.PlayerData.metadata or {}
        local reps = self.PlayerData.metadata.jobrep or {}
        local job = self.PlayerData.job.name
        reps[job] = (tonumber(reps[job]) or 0) + amount
        self.PlayerData.metadata.jobrep = reps
    end
    F.AddJobRep = F.AddJobReputation

    function F.GetRep(rep) return ((self.PlayerData.metadata or {}).rep or {})[rep] or 0 end
    function F.AddRep(rep, amount)
        self.PlayerData.metadata = self.PlayerData.metadata or {}
        self.PlayerData.metadata.rep = self.PlayerData.metadata.rep or {}
        self.PlayerData.metadata.rep[rep] = math.max(0, F.GetRep(rep) + (tonumber(amount) or 0))
    end
    function F.RemoveRep(rep, amount) return F.AddRep(rep, -(tonumber(amount) or 0)) end
    function F.Notify() end
    function F.Save() return QBCore.Player.SaveOffline(self.PlayerData) end
    function F.Logout() return false end
    function F.AddMethod(name, handler)
        if type(name) ~= 'string' or not isCallable(handler) then return false end
        self[name], F[name] = handler, handler
        return true
    end
    function F.AddField(name, value)
        if type(name) ~= 'string' or isCallable(value) then return false end
        self[name] = value
        return true
    end

    exposePlayerMethods(self)
    return self
end

Core.compat.buildOfflinePlayer = buildOfflinePlayer

local function forgetPlayer(src)
    local player = QBCore.Players[src]
    if player and player.PlayerData.citizenid then
        QBCore.PlayersByCitizenId[player.PlayerData.citizenid] = nil
    end
    QBCore.Players[src] = nil
end

function Core.compat.buildLoadedPlayer(src)
    forgetPlayer(src)
    local player = buildQBPlayer(src)
    QBCore.Players[src] = player
    if player and player.PlayerData.citizenid then
        QBCore.PlayersByCitizenId[player.PlayerData.citizenid] = player
    end
    return player
end
AddEventHandler('qbcore:server:playerLoaded', function(src)
    local existing, handle = QBCore.Players[src], PI.handle(src)
    if existing and handle and existing.PlayerData.citizenid == handle.citizenid then return end
    Core.compat.buildLoadedPlayer(src)
end)
AddEventHandler('qbcore:server:playerDropped', forgetPlayer)
AddEventHandler('QBCore:Server:OnPlayerUnload', forgetPlayer)

Core.compat.onPlayerDataChanged = function(src, path, value)
    local player = QBCore.Players[src]
    if not player then return end

    local root = path[1]
    value = Core.util.deepClone(value)
    if root == 'items' and #path == 1 and value == nil then
        value = {}
    elseif root == 'metadata' and #path == 1 then
        value = Core.compat.fillMetadataDefaults(value, player.PlayerData.citizenid)
    elseif root == 'charinfo' and #path == 1 then
        value = Core.compat.fillCharinfoDefaults(value, player.PlayerData.citizenid)
    elseif root == 'position' and #path == 1 then
        value = Core.compat.legacyPosition(value)
    end
    if root == 'job' or root == 'gang' then
        if #path == 1 then
            value = Core.compat.toLegacyJobOrGang(value, root == 'job' and 'jobs' or 'gangs')
        elseif path[2] == 'grade' and value ~= nil then
            if #path == 2 and type(value) == 'table' then
                value.level = Core.compat.toLegacyGradeLevel(value.level)
            elseif #path == 3 and path[3] == 'level' then
                value = Core.compat.toLegacyGradeLevel(value)
            end
        end
    end
    Core.util.pathSet(player.PlayerData, path, value)
    if root == 'money' and type(player.PlayerData.money) == 'table' and Core.money._mirrorOverlay then
        Core.money._mirrorOverlay(src, player.PlayerData.money)
    end
end

local F = QBCore.Functions

local function identifierMatches(candidate, value)
    if type(candidate) ~= 'string' or type(value) ~= 'string' then return false end
    if candidate == value then return true end
    local cBare, vBare = candidate:match('^%w+:(.+)$'), value:match('^%w+:(.+)$')
    return (cBare or candidate) == (vBare or value) and (cBare == nil or vBare == nil)
end

local function licenseForms(value)
    if type(value) ~= 'string' or value == '' then return nil end
    local bare = value:gsub('^license:', '')
    return 'license:' .. bare, bare
end

function F.GetPlayer(src)
    src = tonumber(src) or F.GetSource(src)
    local handle = PI.handle(src)
    if not handle then
        forgetPlayer(src)
        return nil
    end
    local player = QBCore.Players[src]
    if player and player.PlayerData.citizenid == handle.citizenid then return player end
    forgetPlayer(src)
    local p = buildQBPlayer(src)
    if p and Player(src).state.isLoggedIn ~= false then QBCore.Players[src] = p end
    return p
end

function F.GetPlayerByCitizenId(cid)
    local handle = PI.byCitizenId[cid]
    if not handle then
        if cid ~= nil then QBCore.PlayersByCitizenId[cid] = nil end
        return nil
    end
    local player = F.GetPlayer(handle.source)
    if player and Player(handle.source).state.isLoggedIn ~= false then QBCore.PlayersByCitizenId[cid] = player end
    return player
end

function F.GetPlayerByPhone(number)
    for src in pairs(PI.bySource) do
        local h = PI.handle(src)
        local charinfo = h and h.PlayerData.charinfo
        if charinfo and charinfo.phone == number then return F.GetPlayer(src) end
    end
    return nil
end

function F.GetPlayers() return Core.player.getPlayers() end
function F.GetQBPlayers()
    local out = {}
    for src in pairs(PI.bySource) do out[src] = F.GetPlayer(src) end
    return out
end

function F.GetOfflinePlayerByCitizenId(cid)
    local data = Core.persistence._load(cid)
    if not data then return nil end
    return QBCore.Player.CheckPlayerData(nil, Core.compat.toLegacyPlayerData(data))
end

function F.GetIdentifier(src, kind)
    local ids = Core.identity.getIdentifiers(src)
    return ids[kind or Config.identity.primaryIdentifier]
end

function F.GetSource(identifier)
    for src in pairs(PI.bySource) do
        local ids = Core.identity.getIdentifiers(src)
        for _, v in pairs(ids) do if identifierMatches(v, identifier) then return src end end
    end
    return 0
end

local legacyCallbacks = {}

function F.CreateCallback(name, handler)
    legacyCallbacks[name] = handler
    Kora.callback.register(name, function(src, ...)
        local p = promise.new()
        local settled = false

        local function respond(...)
            if settled then return end
            settled = true
            p:resolve(table.pack(...))
        end

        legacyCallbacks[name](src, respond, ...)

        CreateThread(function()
            Wait(Config.compat.callbackTimeoutMs or 5000)
            respond()
        end)

        local results = Citizen.Await(p)
        return table.unpack(results, 1, results.n)
    end)
end
Core.compat.createCallback = F.CreateCallback

function F.TriggerCallback(name, src, cb, ...)
    local args = { ... }
    CreateThread(function()
        local results = table.pack(Kora.callback.trigger(src, name, table.unpack(args)))
        cb(table.unpack(results, 1, results.n))
    end)
end

RegisterNetEvent('QBCore:Server:TriggerCallback', function(name, ...)
    local src = source
    if type(name) ~= 'string' then return end
    local handler = legacyCallbacks[name]
    if not handler then return end

    local function respond(...)
        TriggerClientEvent('QBCore:Client:TriggerCallback', src, name, ...)
    end

    local ok, err = pcall(handler, src, respond, ...)
    if not ok then
        print(('^1[qbcore:qb-core-bridge]^7 legacy callback %q raised an error: %s'):format(tostring(name), tostring(err)))
    end
end)

QBCore.UsableItems = QBCore.UsableItems or {}
function F.CreateUseableItem(name, cb)
    if type(cb) == 'table' and not isCallable(cb) then cb = cb.cb or cb.callback end
    if type(name) ~= 'string' or not isCallable(cb) then return end
    local ok, err = Core.inventory.createUseable(name, cb)
    if err or ok == false then return ok, err end
    QBCore.UsableItems[name] = Core.inventory.getUseable(name)
end
function F.CanUseItem(name)
    local useable = Core.inventory.getUseable(name)
    QBCore.UsableItems[name] = useable
    return useable
end
AddEventHandler('onResourceStop', function(resource)
    for name, record in pairs(QBCore.UsableItems) do
        if record.resource == resource then QBCore.UsableItems[name] = nil end
    end
end)
function F.UseItem(src, item) return Core.inventory.useItem(src, type(item) == 'table' and item.name or item) end

function F.HasPermission(src, perm)
    if type(perm) == 'table' then
        for _, v in pairs(perm) do
            if Core.permissions.hasPermission(src, v) then return true end
        end
        return false
    end
    return Core.permissions.hasPermission(src, perm)
end

function F.GetPermission(src)
    local perms = {}
    for _, v in pairs(QBCore.Config.Server.Permissions) do
        if Core.permissions.hasPermission(src, v) then perms[v] = true end
    end
    return perms
end
function F.AddPermission(src, perm)
    local ok = Core.permissions.addPermission(src, perm)
    if ok then QBCore.Commands.Refresh(src) end
    return ok
end
function F.IsOptin(src)
    if not F.GetIdentifier(src, 'license') or not F.HasPermission(src, 'admin') then return false end
    local player = F.GetPlayer(src)
    return player ~= nil and player.PlayerData.optin == true
end
function F.Kick(source, reason, setKickReason, deferrals)
    reason = '\n' .. (reason or 'Kicked') .. '\n🔸 Check our Discord for further information: ' .. (QBCore.Config.Server.Discord or '')
    if setKickReason then setKickReason(reason) end
    CreateThread(function()
        if deferrals then deferrals.update(reason); Wait(2500) end
        if source then DropPlayer(source, reason) end
    end)
end

function F.Notify(src, text, type_, length)
    TriggerClientEvent('QBCore:Notify', src, text, type_, length)
end

function F.HasItem(src, items, amount) return Core.inventory.hasItem(src, items, amount) end

function F.ExecuteSql(_, query, cb)
    print('^3[qbcore:qb-core-bridge]^7 ExecuteSql is deprecated and its `wait` argument is ignored; use '
        .. 'Kora.sql.query or exports.kora_sql:query.')
    CreateThread(function()
        local rows = Kora.sql.query(query, {})
        if cb then cb(rows) end
    end)
end

function F.PaycheckInterval() return Config.jobs.paycheckInterval or 300000 end

function F.GetCoords(entity)
    local coords = GetEntityCoords(entity, false)
    return vector4(coords.x, coords.y, coords.z, GetEntityHeading(entity))
end

local function onlinePlayerByLicense(license)
    for src in pairs(PI.bySource) do
        local ids = Core.identity.getIdentifiers(src)
        if identifierMatches(ids.license, license) then return F.GetPlayer(src) end
    end
    return nil
end

function F.GetOfflinePlayerByLicense(license)
    local prefixed, bare = licenseForms(license)
    if not prefixed then return nil end
    local row = Kora.sql.single(
        'SELECT `citizenid` FROM `players` WHERE `license` IN (?, ?) AND `deleted_at` IS NULL ORDER BY `cid` LIMIT 1',
        { prefixed, bare }
    )
    return row and F.GetOfflinePlayerByCitizenId(row.citizenid) or nil
end

function F.GetPlayerByLicense(license)
    if type(license) ~= 'string' then return nil end
    return onlinePlayerByLicense(license) or F.GetOfflinePlayerByLicense(license)
end

function F.GetPlayerByAccount(account)
    for src in pairs(PI.bySource) do
        local h = PI.handle(src)
        if h and h.PlayerData.charinfo and h.PlayerData.charinfo.account == account then return F.GetPlayer(src) end
    end
    return nil
end

function F.GetPlayerByCharInfo(property, value)
    for src in pairs(PI.bySource) do
        local h = PI.handle(src)
        local ci = h and h.PlayerData.charinfo
        if ci and ci[property] == value then return F.GetPlayer(src) end
    end
    return nil
end

function F.GetPlayersByJob(job, checkOnDuty)
    local players, count = {}, 0
    for src, Player in pairs(QBCore.Players) do
        local jd = Player.PlayerData.job
        if jd and (jd.name == job or jd.type == job) then
            if not checkOnDuty or jd.onduty then
                players[#players + 1] = src
                count = count + 1
            end
        end
    end
    return players, count
end
function F.GetPlayersOnDuty(job) return F.GetPlayersByJob(job, true) end
function F.GetDutyCount(job) local _, count = F.GetPlayersByJob(job, true); return count end

function F.GetClosestPlayer(source, coords)
    coords = coords and (type(coords) == 'table' and vector3(coords.x, coords.y, coords.z) or coords) or nil
    local result = Kora.closest.player(source, coords)
    return result.id or -1, result.distance or -1
end

local function closestFromPool(source, coords, entityType, excludeSelf)
    coords = coords and (type(coords) == 'table' and vector3(coords.x, coords.y, coords.z) or coords)
        or GetEntityCoords(GetPlayerPed(source))
    local options = excludeSelf and { excludeEntities = { GetPlayerPed(source) } } or nil
    local entity, _, distance = Kora.world.getClosestEntity(entityType, coords, options)
    return entity or -1, distance or -1
end
function F.GetClosestObject(source, coords) return closestFromPool(source, coords, 'object', false) end
function F.GetClosestVehicle(source, coords) return closestFromPool(source, coords, 'vehicle', false) end
function F.GetClosestPed(source, coords) return closestFromPool(source, coords, 'ped', true) end

QBCore.Player_Buckets = QBCore.Player_Buckets or {}
QBCore.Entity_Buckets = QBCore.Entity_Buckets or {}
function F.GetBucketObjects() return QBCore.Player_Buckets, QBCore.Entity_Buckets end
function F.SetPlayerBucket(source, bucket)
    return Core.player.setPlayerBucket(source, bucket)
end
function F.SetEntityBucket(entity, bucket)
    if not (entity and bucket) then return false end
    SetEntityRoutingBucket(entity, bucket)
    QBCore.Entity_Buckets[entity] = { id = entity, bucket = bucket }
    return true
end
function F.GetPlayersInBucket(bucket)
    local pool = {}
    for _, v in pairs(QBCore.Player_Buckets) do if v.bucket == bucket then pool[#pool + 1] = v.id end end
    return pool
end
function F.GetEntitiesInBucket(bucket)
    local pool = {}
    for _, v in pairs(QBCore.Entity_Buckets) do if v.bucket == bucket then pool[#pool + 1] = v.id end end
    return pool
end

local function discardEntity(entity)
    if entity and entity ~= 0 and DoesEntityExist(entity) then DeleteEntity(entity) end
    return false
end

local function awaitEntity(entity)
    if not entity or entity == 0 then return false end
    local ready = Kora.loops.controlled(function()
        return DoesEntityExist(entity) and entity or nil
    end, false, 5000, 25)
    return ready or false
end

local function awaitVehicleWarp(ped, vehicle)
    return Kora.loops.controlled(function()
        if GetVehiclePedIsIn(ped) == vehicle then return true end
        TaskWarpPedIntoVehicle(ped, vehicle, -1)
    end, false, 2000, 25)
end

function F.SpawnVehicle(source, model, coords, warp)
    local ped = GetPlayerPed(source)
    model = type(model) == 'string' and joaat(model) or model
    if not coords then coords = GetEntityCoords(ped) end
    local heading = coords.w and coords.w or 0.0
    local vehicle = awaitEntity(CreateVehicle(model, coords.x, coords.y, coords.z, heading, true, true))
    if not vehicle then return false end

    local owned = Kora.loops.controlled(function()
        return DoesEntityExist(vehicle) and NetworkGetEntityOwner(vehicle) == source
    end, false, 5000, 25)
    if not owned then return discardEntity(vehicle) end
    if warp and not awaitVehicleWarp(ped, vehicle) then return discardEntity(vehicle) end
    return vehicle
end
function F.CreateAutomobile(source, model, coords, warp)
    return F.CreateVehicle(source, model, 'automobile', coords, warp)
end
function F.CreateVehicle(source, model, vehtype, coords, warp)
    model = type(model) == 'string' and joaat(model) or model
    vehtype = type(vehtype) == 'string' and tostring(vehtype) or vehtype
    if not coords then coords = GetEntityCoords(GetPlayerPed(source)) end
    local vehicle = awaitEntity(CreateVehicleServerSetter(model, vehtype, coords, coords.w and coords.w or 0.0))
    if not vehicle then return false end
    if warp and not awaitVehicleWarp(GetPlayerPed(source), vehicle) then return discardEntity(vehicle) end
    return vehicle
end

QBCore.ClientCallbacks = QBCore.ClientCallbacks or {}

function F.TriggerClientCallback(name, source, ...)
    if not source then return end
    local args = { ... }
    local cb
    if isCallable(args[1]) then cb = table.remove(args, 1) end

    if cb then
        QBCore.ClientCallbacks[name .. source] = cb
        TriggerClientEvent('QBCore:Client:TriggerClientCallback', source, name, table.unpack(args))
    else
        local p = promise.new()
        QBCore.ClientCallbacks[name .. source] = p
        TriggerClientEvent('QBCore:Client:TriggerClientCallback', source, name, table.unpack(args))
        local results = Citizen.Await(p)
        return table.unpack(results, 1, results.n)
    end
end

RegisterNetEvent('QBCore:Server:TriggerClientCallback', function(name, ...)
    local src = source
    if type(name) ~= 'string' then return end
    local key = name .. src
    local entry = QBCore.ClientCallbacks[key]
    QBCore.ClientCallbacks[key] = nil
    if type(entry) == 'function' then
        entry(...)
    elseif type(entry) == 'table' and type(entry.resolve) == 'function' then
        entry:resolve(table.pack(...))
    end
end)

function F.RemovePermission(src, permission)
    if permission then
        if IsPlayerAceAllowed(src, permission) then
            Core.permissions.removePermission(src, permission)
            QBCore.Commands.Refresh(src)
        end
    else
        for _, v in pairs(QBCore.Config.Server.Permissions) do
            if IsPlayerAceAllowed(src, v) then
                Core.permissions.removePermission(src, v)
                QBCore.Commands.Refresh(src)
            end
        end
    end
end

function F.ToggleOptin(src)
    if not F.GetIdentifier(src, 'license') or not F.HasPermission(src, 'admin') then return end
    local player = F.GetPlayer(src)
    if not player then return end
    player.Functions.SetPlayerData('optin', not player.PlayerData.optin)
end

function F.IsWhitelisted(src)
    if not QBCore.Config.Server.Whitelist then return true end
    return F.HasPermission(src, QBCore.Config.Server.WhitelistPermission) and true or false
end

function F.IsPlayerBanned(src)
    local prefixed, bare = licenseForms(F.GetIdentifier(src, 'license'))
    if not prefixed then return false end
    local row = Kora.sql.single('SELECT id, reason, expire FROM bans WHERE license IN (?, ?)', { prefixed, bare })
    if not row then return false end
    local expire = tonumber(row.expire)
    if not expire then
        return true, ('You have been banned from the server:\n%s\nThis ban is permanent.\n'):format(row.reason or '')
    end
    if os.time() < expire then
        local t = os.date('*t', expire)
        return true, ('You have been banned from the server:\n%s\nYour ban expires %d/%d/%d %d:%d\n')
            :format(row.reason or '', t.day, t.month, t.year, t.hour, t.min)
    end
    Kora.sql.query('DELETE FROM bans WHERE id = ?', { row.id })
    return false
end

function F.IsLicenseInUse(license)
    for src in pairs(PI.bySource) do
        local ids = Core.identity.getIdentifiers(src)
        if identifierMatches(ids.license, license) then return true end
    end
    return false
end

function F.GetDatabaseInfo()
    local details = { exists = false, database = '' }
    local cs = GetConvar('mysql_connection_string', '')
    if cs == '' then return details end
    if cs:find('mysql://') then
        cs = cs:sub(9, -1)
        details.database = cs:sub((cs:find('/') or 0) + 1, -1):gsub('[%?]+[%w%p]*$', '')
        details.exists = details.database ~= ''
    else
        for part in cs:gmatch('[^;]+') do
            local database = part:match('^%s*[Dd]atabase%s*=%s*(.-)%s*$')
            if database then
                details.database = database
                details.exists = database ~= ''
                break
            end
        end
    end
    return details
end

function F.GetCoreVersion(invokingResource)
    local version = GetResourceMetadata(GetCurrentResourceName(), 'version', 0)
    if invokingResource and invokingResource ~= '' then
        print(('%s called qbcore version check: %s'):format(invokingResource, version))
    end
    return version
end

function F.ExploitBan(playerId, origin)
    local name = GetPlayerName(playerId)
    Kora.sql.insert('INSERT INTO bans (name, license, discord, ip, reason, expire, bannedby) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        name, F.GetIdentifier(playerId, 'license'), F.GetIdentifier(playerId, 'discord'),
        F.GetIdentifier(playerId, 'ip'), origin, 2147483647, 'Anti Cheat',
    })
    DropPlayer(playerId, ('You have been banned for exploiting: %s'):format(tostring(origin)))
    TriggerEvent('qb-log:server:CreateLog', 'anticheat', 'Anti-Cheat', 'red', name .. ' banned for exploiting ' .. tostring(origin), true)
end

local function createUniqueId(generator, query)
    for _ = 1, 100 do
        local value = generator()
        local exists = Kora.sql.scalar(query, { value })
        if not exists or tonumber(exists) == 0 then return value end
    end
    QBCore.ShowError(GetCurrentResourceName(), 'createUniqueId: exceeded 100 retries')
end

function F.CreateAccountNumber()
    return createUniqueId(
        function()
            return 'US0' .. math.random(1, 9) .. 'QBCore' .. math.random(1111, 9999)
                .. math.random(1111, 9999) .. math.random(11, 99)
        end,
        'SELECT EXISTS(SELECT 1 FROM players WHERE JSON_UNQUOTE(JSON_EXTRACT(charinfo, "$.account")) = ?) AS uniqueCheck'
    )
end

function F.CreatePhoneNumber()
    return createUniqueId(
        function() return tostring(math.random(100, 999)) .. tostring(math.random(1000000, 9999999)) end,
        'SELECT EXISTS(SELECT 1 FROM players WHERE JSON_UNQUOTE(JSON_EXTRACT(charinfo, "$.phone")) = ?) AS uniqueCheck'
    )
end

local function forEachCompatPlayer(ids, callback)
    if type(ids) == 'number' then
        if ids == -1 then
            for _, player in pairs(QBCore.Players) do callback(player) end
        elseif QBCore.Players[ids] then
            callback(QBCore.Players[ids])
        end
    elseif type(ids) == 'table' then
        for _, id in ipairs(ids) do forEachCompatPlayer(id, callback) end
    end
end

function F.AddPlayerMethod(ids, methodName, handler)
    if type(methodName) ~= 'string' or not isCallable(handler) then return false end
    forEachCompatPlayer(ids, function(player)
        player[methodName] = handler
        player.Functions[methodName] = handler
    end)
    return true
end

function F.AddPlayerField(ids, fieldName, data)
    if type(fieldName) ~= 'string' or isCallable(data) then return false end
    forEachCompatPlayer(ids, function(player) player[fieldName] = data end)
    return true
end

function F.SetMethod(methodName, handler)
    if type(methodName) ~= 'string' then return false, 'invalid_method_name' end
    if QBCore.Functions[methodName] ~= nil then return false, 'method_exists' end
    QBCore.Functions[methodName] = handler
    provideExport('qb-core', methodName, handler)
    TriggerEvent('QBCore:Server:UpdateObject')
    return true, 'success'
end
function F.SetField(fieldName, data)
    if type(fieldName) ~= 'string' then return false, 'invalid_field_name' end
    if QBCore[fieldName] ~= nil then return false, 'field_exists' end
    QBCore[fieldName] = data
    TriggerEvent('QBCore:Server:UpdateObject')
    return true, 'success'
end

local REGISTRY_FOR = { item = 'items', job = 'jobs', gang = 'gangs' }
local SHARED_KEY = { item = 'Items', job = 'Jobs', gang = 'Gangs' }

local function sharedRecord(kind, key)
    local registry = REGISTRY_FOR[kind]
    local record = Core.registry.getShared(registry, key)
    if kind == 'item' and not record then
        registry = 'weapons'
        record = Core.registry.getShared(registry, key)
    end
    return record, registry
end

local function sharedAdd(kind, key, record)
    if type(key) ~= 'string' then return false, 'invalid_' .. kind .. '_name' end
    if sharedRecord(kind, key) then return false, kind .. '_exists' end
    local ok, err = Core.registry.registerShared(REGISTRY_FOR[kind], key, Core.util.deepClone(record))
    if not ok then return false, err end
    TriggerClientEvent('QBCore:Client:OnSharedUpdate', -1, SHARED_KEY[kind], key,
        QBCore.Shared[SHARED_KEY[kind]][key])
    TriggerEvent('QBCore:Server:UpdateObject')
    return true, 'success'
end
local function sharedUpdate(kind, key, record)
    if type(key) ~= 'string' then return false, 'invalid_' .. kind .. '_name' end
    local existing, registry = sharedRecord(kind, key)
    if not existing then return false, kind .. '_not_exists' end
    record = Core.util.deepClone(record)
    if registry == 'weapons' and type(record) == 'table' then
        for field, value in pairs(existing) do
            if record[field] == nil then record[field] = Core.util.deepClone(value) end
        end
    end
    local ok, err = Core.registry.registerShared(registry, key, record)
    if not ok then return false, err end
    TriggerClientEvent('QBCore:Client:OnSharedUpdate', -1, SHARED_KEY[kind], key,
        QBCore.Shared[SHARED_KEY[kind]][key])
    TriggerEvent('QBCore:Server:UpdateObject')
    return true, 'success'
end
local function sharedRemove(kind, key)
    if type(key) ~= 'string' then return false, 'invalid_' .. kind .. '_name' end
    if not sharedRecord(kind, key) then return false, kind .. '_not_exists' end
    local registries = kind == 'item' and { 'items', 'weapons' } or { REGISTRY_FOR[kind] }
    for _, registry in ipairs(registries) do
        if Core.registry.getShared(registry, key) then
            local ok, err = Core.registry.unregisterShared(registry, key)
            if not ok then return false, err or kind .. '_remove_failed' end
        end
    end
    if sharedRecord(kind, key) then return false, kind .. '_remove_failed' end
    TriggerClientEvent('QBCore:Client:OnSharedUpdate', -1, SHARED_KEY[kind], key, nil)
    TriggerEvent('QBCore:Server:UpdateObject')
    return true, 'success'
end
local function sharedAddMany(kind, records)
    for key in pairs(records) do
        if type(key) ~= 'string' then return false, 'invalid_' .. kind .. '_name' end
        if sharedRecord(kind, key) then return false, kind .. '_exists', key end
    end
    local legacyRecords = {}
    for key, record in pairs(records) do
        local ok, err = Core.registry.registerShared(REGISTRY_FOR[kind], key, Core.util.deepClone(record))
        if not ok then return false, err, key end
        legacyRecords[key] = QBCore.Shared[SHARED_KEY[kind]][key]
    end
    TriggerClientEvent('QBCore:Client:OnSharedUpdateMultiple', -1, SHARED_KEY[kind], legacyRecords)
    TriggerEvent('QBCore:Server:UpdateObject')
    return true, 'success'
end

function F.AddItem(name, item) return sharedAdd('item', name, item) end
function F.UpdateItem(name, item) return sharedUpdate('item', name, item) end
function F.AddItems(items) return sharedAddMany('item', items) end
function F.RemoveItem(name) return sharedRemove('item', name) end
function F.AddJob(name, job) return sharedAdd('job', name, job) end
function F.AddJobs(jobs) return sharedAddMany('job', jobs) end
function F.UpdateJob(name, job) return sharedUpdate('job', name, job) end
function F.RemoveJob(name) return sharedRemove('job', name) end
function F.AddGang(name, gang) return sharedAdd('gang', name, gang) end
function F.AddGangs(gangs) return sharedAddMany('gang', gangs) end
function F.UpdateGang(name, gang) return sharedUpdate('gang', name, gang) end
function F.RemoveGang(name) return sharedRemove('gang', name) end

local function GetShared(namespace, item)
    local ns = QBCore.Shared[namespace]
    if not ns and Core.compat.canonicalSharedNamespace then
        ns = QBCore.Shared[Core.compat.canonicalSharedNamespace(namespace)]
    end
    if not ns then return nil end
    return item and ns[item] or ns
end

local P = QBCore.Player

local function applyPlayerDefaults(data, defaults)
    for key, default in pairs(defaults) do
        if data[key] == nil then
            if type(default) == 'function' then
                data[key] = default()
            elseif type(default) == 'table' then
                data[key] = {}
                applyPlayerDefaults(data[key], default)
            else
                data[key] = default
            end
        elseif type(default) == 'table' and type(data[key]) == 'table' then
            applyPlayerDefaults(data[key], default)
        end
    end
end

local function validateLegacyRole(data, key)
    local role = data[key]
    local definition = role and role.name
        and Core.registry.getShared(key == 'job' and 'jobs' or 'gangs', role.name)
    local level = role and role.grade and role.grade.level
    local grade = definition and level ~= nil and definition.grades[(tonumber(level) or 0) + 1]
    if not grade then data[key] = nil; return end

    role.label = definition.label
    role.grade.name = grade.name
    role.grade.payment = grade.payment
    role.grade.isboss = grade.isboss or false
    role.isboss = grade.isboss or false
    if key == 'job' then
        role.type = definition.type or 'none'
        if QBCore.Shared.ForceJobDefaultDutyAtLogin then role.onduty = definition.defaultDuty end
    end
end

function P.Login(src, citizenid, newData)
    if not src or src == '' then
        QBCore.ShowError(GetCurrentResourceName(), 'ERROR QBCORE.PLAYER.LOGIN - NO SOURCE GIVEN!')
        return false
    end
    if citizenid then
        local data = Core.persistence._load(citizenid)
        local license = F.GetIdentifier(src, 'license')
        if data and license == data.license then
            return P.CheckPlayerData(src, Core.compat.toLegacyPlayerData(data)) ~= nil
        end
        DropPlayer(src, 'Dropped for character joining exploit')
        TriggerEvent('qb-log:server:CreateLog', 'anticheat', 'Anti-Cheat', 'white',
            (GetPlayerName(src) or tostring(src)) .. ' Has Been Dropped For Character Joining Exploit', false)
        return false
    end
    return P.CheckPlayerData(src, newData) ~= nil
end
function P.Logout(src) return Core.player.logout(src) end
function P.Save(src)
    local player = F.GetPlayer(src)
    if player then return player.Functions.Save() end
end
function P.SaveOffline(playerData)
    if type(playerData) ~= 'table' or not playerData.citizenid then return false, 'invalid player data' end
    local data = Core.compat.fromLegacyPlayerData(playerData)
    data.phone = data.phone or (data.charinfo and data.charinfo.phone)
    local ok, err = Core.persistence.saveOfflinePlayer(data,
        { 'name', 'money', 'charinfo', 'job', 'gang', 'position', 'metadata', 'items', 'phone' })
    if ok or err ~= 'player not found' then return ok, err end

    if PI.byCitizenId[data.citizenid] then return false, 'player is online' end
    if Core.persistence._persistentColumnsAvailable then
        local available, reason = Core.persistence._persistentColumnsAvailable(data.citizenid)
        if not available then return false, reason end
    end
    if PI.byCitizenId[data.citizenid] then return false, 'player is online' end
    if Core.persistence._beginOfflineWrite and not Core.persistence._beginOfflineWrite(data.citizenid) then
        return false, 'player data is busy'
    end
    local called, inserted, insertError = pcall(Core.persistence._insertNew,
        data.citizenid, data.license, tonumber(data.cid) or 1, data)
    if Core.persistence._endOfflineWrite then Core.persistence._endOfflineWrite(data.citizenid) end
    if not called then return false, tostring(inserted) end
    return inserted, insertError
end

function P.CreatePlayer(srcOrData, charinfo, cid)
    if type(srcOrData) == 'table' then
        local legacyData, offline = srcOrData, charinfo == true
        if offline or not legacyData.source then return buildOfflinePlayer(Core.compat.fromLegacyPlayerData(legacyData)) end
        if PI.handle(legacyData.source) then return nil end
        local internal = Core.compat.fromLegacyPlayerData(legacyData)
        if not P.SaveOffline(legacyData) then return nil end
        local ok = Core.player.login(legacyData.source, legacyData.citizenid, internal)
        return ok and F.GetPlayer(legacyData.source) or nil
    end
    return Core.player.createCharacter(srcOrData, charinfo, cid)
end
function P.DeleteCharacter(src, citizenid) return Core.multichar.deleteCharacter(src, citizenid) end
function P.ForceDeleteCharacter(citizenid)
    return Kora.sql.query('UPDATE `players` SET `deleted_at` = NOW() WHERE `citizenid` = ?', { citizenid })
end
function P.CheckPlayerData(src, playerData)
    playerData = playerData or {}
    local offline = not src
    if src then
        playerData.source = src
        playerData.license = playerData.license or F.GetIdentifier(src, 'license')
        playerData.name = GetPlayerName(src)
    end
    validateLegacyRole(playerData, 'job')
    validateLegacyRole(playerData, 'gang')
    applyPlayerDefaults(playerData, QBCore.Config.Player.PlayerDefaults)
    return P.CreatePlayer(playerData, offline)
end
function P.ForceUpdatePlayerData(src)
    if src then
        local player = F.GetPlayer(src)
        if player then return player.Functions.UpdatePlayerData() end
        return false
    end
    for _, player in pairs(QBCore.Players) do player.Functions.UpdatePlayerData() end
end

function P.GetOfflinePlayer(citizenid) return F.GetOfflinePlayerByCitizenId(citizenid) end
function P.GetPlayerByLicense(license) return F.GetPlayerByLicense(license) end
function P.GetOfflinePlayerByLicense(license) return F.GetOfflinePlayerByLicense(license) end

local function randomId(len, alpha)
    local chars = alpha and 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789' or '0123456789'
    local t = {}
    for i = 1, len do local n = math.random(1, #chars); t[i] = chars:sub(n, n) end
    return table.concat(t)
end
function P.CreateCitizenId() return Core.identity.generateCitizenId() end
function P.CreateFingerId()
    return Core.util.randomStr(2) .. Core.util.randomInt(3) .. Core.util.randomStr(1)
        .. Core.util.randomInt(2) .. Core.util.randomStr(3) .. Core.util.randomInt(4)
end
function P.CreateWalletId() return 'QB-' .. tostring(math.random(10000000, 99999999)) end
function P.CreateSerialNumber() return randomId(9, false) end

local commandExtras = {}
QBCore.Commands.List = {}
local function rebuildCommandList()
    if not (Core.commands and Core.commands.listCommands) then return end
    for k in pairs(QBCore.Commands.List) do QBCore.Commands.List[k] = nil end
    for _, c in ipairs(Core.commands.listCommands()) do
        local extra = commandExtras[c.name]
        QBCore.Commands.List[c.name:lower()] = {
            name = c.name:lower(),
            help = c.help,
            permission = extra and extra.permission or c.permission,
            params = extra and extra.params,
            arguments = extra and extra.params,
            argsrequired = extra and extra.argsrequired,
            callback = extra and extra.callback,
        }
    end
end
QBCore.Commands.IgnoreList = QBCore.Commands.IgnoreList or { god = true, user = true }

QBCore.Commands.Add = function(name, help, args, argsRequired, cb, permission, ...)
    local nativeArgs = args
    if type(args) == 'table' then
        nativeArgs = Core.util.deepClone(args)
        for _, argument in ipairs(nativeArgs) do
            if type(argument) == 'table' and argument.name == nil then
                argument.name = argument[1]
                argument.help = argument.help or argument[2]
            end
        end
    end
    local function guarded(source, commandArgs, rawCommand)
        TriggerEvent('QBCore:Server:PreCommandExecution', source, name, commandArgs, rawCommand)
        if WasEventCanceled and WasEventCanceled() then return end
        return cb(source, commandArgs, rawCommand)
    end

    local levels = { type(permission) == 'string' and permission:lower() or 'user' }
    local listPermission = levels[1]
    local extra = select('#', ...)
    if extra > 0 then
        for i = 1, extra do
            local level = select(i, ...)
            if type(level) == 'string' then levels[#levels + 1] = level:lower() end
        end
        listPermission = { table.unpack(levels) }
    end
    local nativePermission = levels[1]
    local rank = { god = 4, admin = 3, mod = 2, user = 1 }
    for _, level in ipairs(levels) do
        if (rank[level] or 0) < (rank[nativePermission] or 0) then nativePermission = level end
    end
    Core.commands.addCommand(name, help, nativeArgs, argsRequired, guarded, nativePermission)
    for _, level in ipairs(levels) do
        if level:match('^[%w_]+$') and type(name) == 'string' and name:match('^[%w_:%.%-]+$')
            and not QBCore.Commands.IgnoreList[level] then
            ExecuteCommand(('add_ace qbcore.%s command.%s allow'):format(level, name))
        end
    end
    commandExtras[name] = { params = args, argsrequired = argsRequired, callback = cb, permission = listPermission }
    rebuildCommandList()
end
QBCore.Commands.Refresh = function(src) Core.commands.refreshCommands(src); rebuildCommandList() end
rebuildCommandList()

Core.compat.populateLegacyConfig()

for _, k in ipairs({ 'Items', 'Vehicles', 'Jobs', 'Gangs', 'Weapons' }) do
    local _ = QBCore.Shared[k]
end

local function getCoreObject(filters)
    if not filters then return QBCore end
    local results = {}
    for i = 1, #filters do local k = filters[i]; if QBCore[k] then results[k] = QBCore[k] end end
    return results
end

if Config.compat.coreObjectExport then
    provideExport('qb-core', 'GetCoreObject', getCoreObject)
    provideExport('qb-core', 'GetShared', GetShared)
    provideExport('qb-core', 'GetSharedItems', function() return GetShared('Items') end)
    provideExport('qb-core', 'GetSharedVehicles', function() return GetShared('Vehicles') end)
    provideExport('qb-core', 'GetSharedJobs', function() return GetShared('Jobs') end)
    provideExport('qb-core', 'GetSharedGangs', function() return GetShared('Gangs') end)
    provideExport('qb-core', 'GetSharedWeapons', function() return GetShared('Weapons') end)
    for name, fn in pairs(QBCore.Functions) do
        if type(fn) == 'function' then provideExport('qb-core', name, fn) end
    end
end
