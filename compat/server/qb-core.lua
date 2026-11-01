-- compat/server/qb-core.lua -- the server half of the QBCore object, exposed via
-- exports['qb-core']:GetCoreObject(). Every function here calls the internal
-- Core.* implementation DIRECTLY (never exports.kora_core:fn()), so
-- GetInvokingResource() inside those resolves to the original external consumer
-- rather than to kora_core -- load-bearing for the owner-tracked registrations
-- (commands, useables, registry entries, onChange).

local PI = CoreInternal.player

-- CFX export-boundary callbacks may arrive as callable tables/funcrefs.
-- Current qb-core uses this check for player extension hooks in both live and
-- offline objects.
local isCallable = Kora.util.isCallable

-- `provide 'qb-core'` alone doesn't make exports['qb-core']:GetCoreObject()
-- resolve here; registering the __cfx_export event does (same identity hijack as
-- kora_target/client/compat/ox-target.lua).
local provideExport = Kora.compat.provideExport

-- Built-ins accept modern colon calls and the direct dot calls used by older
-- resources. A receiver may be a msgpack copy after crossing a CFX export.
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

local immutableRoots = { source = true, citizenid = true, license = true, cid = true }

local SETPLAYERDATA_REASON = 'qb-compat-setplayerdata'

-- A legacy `money` root write. Non-cash accounts replace the ledger as before.
-- A physical-cash account (kora_inventory owns it as an item stack, so its
-- ledger value is a constant 0 and PlayerData.money.cash is NOT the real
-- balance) is never written: the DELTA between the written value and the
-- PlayerData view the script saw is applied through the money funnel, so item
-- stacks stay the only authority. A write that leaves cash equal to the view
-- (the common "write the table back" case) is a no-op for cash. A removal
-- larger than the real balance refuses the WHOLE write (nothing is applied)
-- and logs, so a script can neither overdraw nor get a partial update.
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
            local delta = number - (tonumber(ledger[account]) or 0)
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

-- --- the per-player QBPlayer compat object -----------------------------------

-- The legacy view stays current through the funnel hook. Its nested tables
-- are detached so direct edits must be reconciled before entering authority.
local function buildQBPlayer(src)
    local handle = PI.handle(src)
    if not handle then return nil end

    -- PlayerData is a legacy-shaped VIEW (job/gang grade.level translated to
    -- real qb-core's zero-based numbering), NOT `handle.PlayerData` itself --
    -- see Core.compat.toLegacyPlayerData's comment for why a live metatable
    -- proxy can't be used here. Kept in sync incrementally by
    -- Core.compat.onPlayerDataChanged (registered below), which
    -- Core.player.setPath calls on every write, so this never goes stale --
    -- including root-level replacements like SetJob/SetGang/SetInventory.
    local self = { PlayerData = Core.compat.toLegacyPlayerData(Core.util.deepClone(handle.PlayerData)), Offline = false }
    local F = {}
    self.Functions = F

    local function publishWrite(ok, err, key)
        if ok then F.UpdateClient(key) end
        return ok, err
    end

    function F.GetName() return handle.PlayerData.name end
    function F.GetPlayerData() return Core.compat.toLegacyPlayerData(Core.util.deepClone(handle.PlayerData)) end

    function F.SetJob(name, grade) return Core.jobs.setJob(src, name, Core.compat.fromLegacyGradeLevel(grade)) end
    function F.SetGang(name, grade) return Core.jobs.setGang(src, name, Core.compat.fromLegacyGradeLevel(grade)) end
    function F.SetJobDuty(onDuty) return Core.jobs.setJobDuty(src, onDuty) end
    -- 'onduty' is routed through Core.jobs.setJobDuty rather than written
    -- straight to the path: duty is indexed (byJobOnDuty / byTypeOnDuty), and a
    -- raw setPath flips the value while leaving the index stale -- that player
    -- then silently receives no dispatch alerts and counts as off duty
    -- everywhere. Core.jobs also has an onChange reconciler covering direct
    -- writes, but going through the real function keeps the duty EVENTS
    -- (QBCore:Server:SetDuty / QBCore:Client:SetDuty) firing too, which the
    -- reconciler cannot retrofit.
    local function setRoleData(kind, key, value)
        if type(key) ~= 'string' then return false end
        local role = Core.compat.toLegacyJobOrGang(Core.util.deepClone(handle.PlayerData[kind]))
        role[key] = value
        local ok, err = writeLegacyRoot(src, kind, role)
        return publishWrite(ok, err, kind)
    end
    function F.SetJobData(k, v)
        if k == 'onduty' then return Core.jobs.setJobDuty(src, v and true or false) end
        return setRoleData('job', k, v)
    end
    function F.SetGangData(k, v) return setRoleData('gang', k, v) end

    -- `ignoreTax` is a kora_core addition past stock qb-core's 3-arg signature, so
    -- an unported resource simply passes nil and is taxed like any other
    -- transaction. SetMoney has no such param: it is never taxed.
    function F.AddMoney(t, amount, reason, ignoreTax) return Core.money.addMoney(src, t, amount, reason, ignoreTax) end
    function F.RemoveMoney(t, amount, reason, ignoreTax) return Core.money.removeMoney(src, t, amount, reason, ignoreTax) end
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

    -- Legacy full-data writers. SetPlayerData(key, value) targets a root key.
    function F.SetPlayerData(key, value)
        local column = PI.COLUMN_FOR[key]
        if not column and Config.compat.warnOnUnknownRoot then
            print(("^3[qbcore:qb-core-bridge]^7 SetPlayerData('%s', ...) targets an unknown root key with no DB "
                .. "column mapping; it will not persist."):format(tostring(key)))
        end
        local ok, err = writeLegacyRoot(src, key, value)
        return publishWrite(ok, err, key)
    end

    -- Reconcile legacy direct edits only when explicitly requested. Detached
    -- views keep uncommitted edits behind the authoritative funnel's fences.
    local function reconcilePlayerData(key, ...)
        if PI.handle(src) ~= handle then return false, 'player is no longer loaded' end
        if key == 'all' then key = nil end
        if key ~= nil and type(key) ~= 'string' then return false, 'player data key must be a string' end
        if key and select('#', ...) > 0 then self.PlayerData[key] = Core.util.deepClone((...)) end
        local current = Core.compat.toLegacyPlayerData(handle.PlayerData)
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
                -- A physical-cash edit was applied as an item delta; the ledger
                -- view of that account did not move, so re-baseline the detached
                -- copy or the next reconcile would apply the same delta again.
                if root == 'money' then
                    self.PlayerData.money = Core.util.deepClone(
                        Core.compat.toLegacyPlayerData(handle.PlayerData).money)
                end
            end
        end
        return true
    end

    function F.UpdateClient(key, ...)
        if key == 'all' then key = nil end
        local ok, err = reconcilePlayerData(key, ...)
        if not ok then return false, err end
        local data = Core.compat.toLegacyPlayerData(Core.util.deepClone(handle.PlayerData))
        local eventKey, value = key or 'all', data
        if key then value = data[key] end
        if not key then TriggerEvent('QBCore:Player:SetPlayerData', data) end
        TriggerEvent('QBCore:Server:OnPlayerUpdated', src, eventKey, value)
        -- The funnel's queued delta must reach the client before this legacy
        -- notification reads the authoritative mirror there.
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

    -- --- methods present on CURRENT qb-core's player object (server/player.lua's
    -- varargMethods/noargMethods) that classic-era compat lacked. Added so a
    -- script written against modern qb-core (`Player.Functions.Notify(...)`,
    -- `Player.Functions.HasItem(...)`, the reputation + extension methods) works
    -- too -- this object is the UNION of both qb-core eras.
    function F.Notify(text, type_, length) TriggerClientEvent('QBCore:Notify', src, text, type_, length) end
    function F.HasItem(items, amount) return Core.inventory.hasItem(src, items, amount) end

    -- Older job scripts use a separate jobrep map keyed by the CURRENT job,
    -- including signed increments. Keep it distinct from modern metadata.rep.
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

    -- Reputation lives in metadata.rep (a name->number map), matching qb-core.
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

    -- Extension hooks: qb-core lets a resource bolt a custom method/field onto a
    -- player object at runtime. AddMethod adds to THIS player's Functions table;
    -- AddField adds a field to the player object itself.
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

-- Offline lookups in current qb-core return a real Player object, not a bare
-- `{PlayerData, Offline}` record. Keep a legacy-shaped local snapshot with the
-- same method table; Save writes it back after translating grade levels to
-- kora_core's internal one-based representation.
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

-- Keep QBCore.Players in sync as players load / unload.
AddEventHandler('qbcore:server:playerLoaded', function(src)
    forgetPlayer(src)
    local player = buildQBPlayer(src)
    QBCore.Players[src] = player
    if player and player.PlayerData.citizenid then
        QBCore.PlayersByCitizenId[player.PlayerData.citizenid] = player
    end
end)
AddEventHandler('qbcore:server:playerDropped', forgetPlayer)
AddEventHandler('QBCore:Server:OnPlayerUnload', forgetPlayer)

-- Keeps QBCore.Players[src].PlayerData incrementally in sync with EVERY write
-- Core.player.setPath makes (it calls this on every successful write -- see
-- modules/player/server.lua). Mirrors the exact same setPath operation onto
-- the legacy view, translating job/gang grade.level on the way through --
-- this is what lets a wholesale root replacement (SetJob/SetGang/
-- SetInventory/ClearInventory) AND a single-field patch (SetJobDuty's
-- onduty, F.SetJobData/SetGangData below) both stay correct without
-- enumerating call sites: every one of them routes through setPath, and this
-- hook covers setPath itself.
Core.compat.onPlayerDataChanged = function(src, path, value)
    local player = QBCore.Players[src]
    if not player then return end

    local root = path[1]
    value = Core.util.deepClone(value)
    if root == 'job' or root == 'gang' then
        if #path == 1 then
            value = Core.compat.toLegacyJobOrGang(value)
        elseif path[2] == 'grade' and value ~= nil then
            if #path == 2 and type(value) == 'table' then
                value.level = Core.compat.toLegacyGradeLevel(value.level)
            elseif #path == 3 and path[3] == 'level' then
                value = Core.compat.toLegacyGradeLevel(value)
            end
        end
    end
    Core.util.pathSet(player.PlayerData, path, value)
end

-- --- QBCore.Functions.* ------------------------------------------------------

local F = QBCore.Functions

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
    -- Build lazily if the load hook hasn't fired yet.
    local p = buildQBPlayer(src)
    -- Logout clears the state flag before unload callbacks, but retains the
    -- handle until they finish. Allow those reads without rebuilding the cache.
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
        for _, v in pairs(ids) do if v == identifier then return src end end
    end
    return 0
end

-- Callbacks -> kora_lib's Kora.callback, PLUS real qb-core's raw net-event wire
-- protocol (QBCore:Server:TriggerCallback / QBCore:Client:TriggerCallback).
-- Some legacy scripts skip QBCore.Functions.TriggerCallback entirely and
-- fire the raw event themselves, so a handler registered via CreateCallback
-- must be reachable through BOTH transports without ever running twice for
-- one incoming request.
--
-- legacyCallbacks is the single source of truth: CreateCallback stores the
-- handler here (keyed by name), and BOTH the kora_lib-registered wrapper below
-- and the raw net event handler look the current handler up from this table
-- at dispatch time rather than closing over it -- so a later CreateCallback
-- call for the same name (a legitimate resource restart) updates what both
-- transports invoke, without re-registering either transport.
local legacyCallbacks = {}

-- Real QBCore hands the legacy handler a RESPONDER function as its second
-- argument -- function(source, cb, ...) ... cb(result) end -- and the handler
-- is expected to call that responder, not `return` its result. kora_lib's
-- Kora.callback.register instead ships back whatever the registered function
-- RETURNS. Bridging one onto the other means giving the legacy handler a
-- `cb` that resolves a promise, then awaiting that promise for the actual
-- return. A handler that never calls `cb` (a legitimate early-return, e.g.
-- qb-banking's card-missing checks) would otherwise leak the awaiting
-- coroutine and kora_lib's pending request forever -- the timeout guards that.
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

        -- Dispatch through legacyCallbacks[name], NOT the `handler` upvalue
        -- above -- see the table's comment: this is what makes a later
        -- re-registration for the same name take effect here too.
        legacyCallbacks[name](src, respond, ...)

        CreateThread(function()
            Wait(Config.compat.callbackTimeoutMs or 5000)
            respond()
        end)

        local results = Citizen.Await(p)
        return table.unpack(results, 1, results.n)
    end)
end
-- Retain the public callback wire for consumers while allowing native callers.
Core.compat.createCallback = F.CreateCallback

-- Real QBCore's TriggerCallback forwards EVERY value the client handler
-- returned to `cb`, not just the first -- kora_lib's Kora.callback.trigger (called
-- here cross-resource, kora_core -> kora_lib) now supports that end to end, so
-- table.pack/unpack is all that's needed to match it faithfully.
function F.TriggerCallback(name, src, cb, ...)
    local args = { ... }
    CreateThread(function()
        local results = table.pack(Kora.callback.trigger(src, name, table.unpack(args)))
        cb(table.unpack(results, 1, results.n))
    end)
end

-- Raw wire, client->server leg: a legacy script that skips
-- QBCore.Functions.TriggerCallback and fires the event directly. `name` gets
-- no validation in upstream either, but upstream also never crashes on
-- garbage input from the network -- guard the type instead of erroring.
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

-- Useable items.
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

-- Permissions / admin.
-- Upstream HasPermission takes a permission name *or* an array of them (any
-- match passes); our native one is single-permission only.
function F.HasPermission(src, perm)
    if type(perm) == 'table' then
        for _, v in pairs(perm) do
            if Core.permissions.hasPermission(src, v) then return true end
        end
        return false
    end
    return Core.permissions.hasPermission(src, perm)
end

-- Upstream GetPermission returns a SET of every configured permission group the
-- player holds ({ god = true, admin = true }), which callers index by name --
-- not the single highest level our native Core.permissions.getPermission
-- reports. Built from HasPermission so perms[x] and HasPermission(x) agree.
function F.GetPermission(src)
    local perms = {}
    for _, v in pairs(QBCore.Config.Server.Permissions) do
        if Core.permissions.hasPermission(src, v) then perms[v] = true end
    end
    return perms
end
function F.AddPermission(src, perm) return Core.permissions.addPermission(src, perm) end
function F.IsOptin(src) return Core.permissions.isOptin(src) end
-- Full upstream signature: supports the connect-phase setKickReason/deferrals
-- path so a script kicking during playerConnecting behaves the same.
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

-- ---------------------------------------------------------------------------
-- Parity block: the rest of real qb-core's QBCore.Functions.* surface
-- (server/functions.lua) plus the server/exports.lua registry mutators, so a
-- third-party script calling any of them -- via GetCoreObject OR directly via
-- exports['qb-core']:Fn(...) -- resolves. Native-heavy helpers are ported
-- almost verbatim from upstream (self-contained CFX code); semantic ones map
-- onto our Core.* implementations.
-- ---------------------------------------------------------------------------

function F.GetCoords(entity)
    local coords = GetEntityCoords(entity, false)
    return vector4(coords.x, coords.y, coords.z, GetEntityHeading(entity))
end

function F.GetPlayerByLicense(license)
    for src in pairs(PI.bySource) do
        local ids = Core.identity.getIdentifiers(src)
        if ids.license == license then return F.GetPlayer(src) end
    end
    return nil
end

function F.GetOfflinePlayerByLicense(license)
    local row = Kora.sql.single(
        'SELECT `citizenid` FROM `players` WHERE `license` = ? AND `deleted_at` IS NULL LIMIT 1',
        { license }
    )
    return row and F.GetOfflinePlayerByCitizenId(row.citizenid) or nil
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

-- Job/duty helpers -- iterate the live QBCore.Players map exactly as upstream,
-- so the (players, count) return shape and the job.name/job.type match are
-- byte-for-byte compatible.
--
-- The `jd.type == job` arm is live: CoreInternal.player.buildJob copies the
-- registry's job type onto PlayerData.job, and toLegacyJobOrGang shallow-copies
-- it into this legacy view. (It was dead until that change -- the type was
-- registry-only, so passing 'leo' here matched nothing.) The modern equivalent
-- with an O(1) index is Core.jobs.getPlayersByJobType; this scan is kept
-- because upstream's shape allows a caller to pass either a name or a type in
-- the same argument and the two can't be told apart here.
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

-- Server-side closest-entity helpers -- thin forwards to Kora.world.getClosestEntity
-- (see AGENTS.md's "thin forwards to Kora.*, not reimplementations"). GetClosestPlayer
-- additionally maps the ped Kora.world returns back to a player id via Kora.closest.player,
-- matching real qb-core's (playerId, distance) signature.
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

-- Routing buckets. QBCore tracks its own maps so GetPlayersInBucket/etc work.
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

-- Server-side vehicle creation. Legacy qb-core used frame-count loops here,
-- which made the real timeout depend on server tick rate and could still
-- return an invalid handle. Keep both compatibility entry points on the same
-- millisecond-bounded kora_lib lifecycle.
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
-- Upstream's CreateAutomobile uses the experimental CREATE_AUTOMOBILE native
-- (documented there as "doesn't work for all vehicles"). We delegate to the
-- reliable CreateVehicleServerSetter path with the 'automobile' type instead --
-- same result, and it avoids a CFX hash-literal the toolchain can't parse.
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

-- Client callbacks: real qb-core's own raw wire protocol
-- (QBCore:Client:TriggerClientCallback / QBCore:Server:TriggerClientCallback).
-- This used to route through kora_lib's callback system instead, but that meant
-- TriggerClientCallback would deliver over ONE transport (kora_lib) while a
-- handler registered via the client's CreateClientCallback is reachable over
-- TWO (kora_lib AND the raw net event, since CreateClientCallback now also
-- stores into legacyClientCallbacks -- see compat/client/qb-core.lua). Firing
-- both transports for a single TriggerClientCallback call would invoke the
-- client's handler twice for one logical request, so this now speaks the raw
-- wire exclusively (matching real qb-core's own implementation), and the
-- kora_lib path is left for cross-resource callers that talk to Kora.callback
-- directly rather than through this function.
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
        -- Sync form (no cb passed): store the awaiting promise instead, same
        -- shape server/qb-core.lua's CreateCallback bridge uses.
        local p = promise.new()
        QBCore.ClientCallbacks[name .. source] = p
        TriggerClientEvent('QBCore:Client:TriggerClientCallback', source, name, table.unpack(args))
        local results = Citizen.Await(p)
        return table.unpack(results, 1, results.n)
    end
end

-- Raw wire, client->server REPLY leg for the above: the client's handler
-- (registered via CreateClientCallback, invoked through its own raw
-- QBCore:Client:TriggerClientCallback listener) calls its responder, which
-- sends this event back. Clear the entry after use so a stray duplicate
-- reply can't resolve/call it a second time.
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

-- Permissions: add the Remove counterpart (upstream ExecuteCommand form; the
-- no-arg case strips every configured permission group).
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
    if not F.HasPermission(src, 'admin') then return end
    local current = Core.metadata.getMetaData(src, 'optin')
    Core.metadata.setMetaData(src, 'optin', not current)
end

function F.IsWhitelisted(src)
    if not QBCore.Config.Server.Whitelist then return true end
    return F.HasPermission(src, QBCore.Config.Server.WhitelistPermission) and true or false
end

function F.IsPlayerBanned(src)
    local license = F.GetIdentifier(src, 'license')
    local row = Kora.sql.single('SELECT id, reason, expire FROM bans WHERE license = ?', { license })
    if not row then return false end
    if os.time() < tonumber(row.expire) then
        local t = os.date('*t', tonumber(row.expire))
        return true, ('You have been banned from the server:\n%s\nYour ban expires %d/%d/%d %d:%d\n')
            :format(row.reason, t.day, t.month, t.year, t.hour, t.min)
    end
    Kora.sql.query('DELETE FROM bans WHERE id = ?', { row.id })
    return false
end

function F.IsLicenseInUse(license)
    for src in pairs(PI.bySource) do
        local ids = Core.identity.getIdentifiers(src)
        if ids.license == license then return true end
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

-- Runtime object extension (server/exports.lua's SetMethod/SetField).
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

-- Shared-registry mutators (server/exports.lua). These route through
-- Core.registry so the change materialises into QBCore.Shared.*, fires our
-- subscribers, AND replicates to clients -- strictly more correct than
-- upstream's raw table write, while returning upstream's (ok, reason) shape.
-- The legacy QBCore:Client:OnSharedUpdate event is fired too, for scripts that
-- listen for it directly.
local REGISTRY_FOR = { item = 'items', job = 'jobs', gang = 'gangs' }
local SHARED_KEY = { item = 'Items', job = 'Jobs', gang = 'Gangs' }

-- The legacy Items view includes both native registries. Resolve the same
-- items-first definition for writes, rather than admitting duplicate names or
-- reporting an existing weapon missing. Registration keeps caller ownership.
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
    local ok, err = Core.registry.registerShared(registry, key, Core.util.deepClone(record))
    if not ok then return false, err end
    TriggerClientEvent('QBCore:Client:OnSharedUpdate', -1, SHARED_KEY[kind], key,
        QBCore.Shared[SHARED_KEY[kind]][key])
    TriggerEvent('QBCore:Server:UpdateObject')
    return true, 'success'
end
local function sharedRemove(kind, key)
    if type(key) ~= 'string' then return false, 'invalid_' .. kind .. '_name' end
    if not sharedRecord(kind, key) then return false, kind .. '_not_exists' end
    -- Removing the visible legacy item also removes its shadowed weapon
    -- definition; otherwise a successful removal immediately exposes it again.
    local registries = kind == 'item' and { 'items', 'weapons' } or { REGISTRY_FOR[kind] }
    for _, registry in ipairs(registries) do
        if Core.registry.getShared(registry, key) then
            local ok, err = Core.registry.unregisterShared(registry, key)
            if not ok then return false, err or kind .. '_remove_failed' end
        end
    end
    -- Subscribers can synchronously change the registry. Never announce a
    -- successful removal while a replacement remains visible.
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

-- GetShared is a top-level export in real qb-core (shared/main.lua), not a
-- Functions entry. It reads QBCore.Shared[namespace], which our coreobject.lua
-- metatable resolves to a live compatibility view -- so this body is
-- identical to upstream's, except for the canonical-casing fallback (see
-- Core.compat.canonicalSharedNamespace's comment -- real-world legacy scripts
-- don't reliably call this with PascalCase, e.g. qb-recyclejob's GetShared('items')).
local function GetShared(namespace, item)
    local ns = QBCore.Shared[namespace]
    if not ns and Core.compat.canonicalSharedNamespace then
        ns = QBCore.Shared[Core.compat.canonicalSharedNamespace(namespace)]
    end
    if not ns then return nil end
    return item and ns[item] or ns
end

-- --- QBCore.Player.* ---------------------------------------------------------

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

-- Login accepts real qb-core's (source, citizenid, newData). A citizenid login
-- must belong to the source license; this is the anti-character-hijack check
-- current qb-core performs before constructing the Player object.
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

    -- Legacy CheckPlayerData/CreatePlayer can save a NEW offline character.
    -- A plain insert preserves that contract without an upsert ever rewriting
    -- another character's immutable license/cid or an active player's data.
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
function P.GetPlayerByLicense(license)
    return F.GetPlayerByLicense(license) or F.GetOfflinePlayerByLicense(license)
end
function P.GetOfflinePlayerByLicense(license) return F.GetOfflinePlayerByLicense(license) end

-- Id generators (server/player.lua). CitizenId routes to our identity module;
-- the rest are self-contained random generators matching qb-core's formats.
local function randomId(len, alpha)
    local chars = alpha and 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789' or '0123456789'
    local t = {}
    for i = 1, len do local n = math.random(1, #chars); t[i] = chars:sub(n, n) end
    return table.concat(t)
end
function P.CreateCitizenId() return Core.identity.generateCitizenId() end
function P.CreateFingerId() return randomId(2, true) .. randomId(3, false) .. randomId(1, true) .. randomId(2, false) end
function P.CreateWalletId() return 'QB-' .. tostring(math.random(10000000, 99999999)) end
function P.CreateSerialNumber() return randomId(9, false) end

-- --- QBCore.Commands ---------------------------------------------------------
-- Real qb-core's QBCore.Commands.List is a TABLE keyed by command name, not a
-- function -- scripts read List[name] and iterate pairs(List). We keep a keyed
-- table rebuilt whenever a command is added/refreshed through the compat.
-- (Commands another resource registers straight through Kora.commands aren't
-- reflected until the next Add/Refresh -- documented in AGENTS.md.)
--
-- Real qb-core's List entries also carry `params`/`argsrequired`/`callback`
-- (not just name/help/permission) -- QBCore:CallCommand (qb-core-events.lua)
-- invokes .callback directly, and checks .argsrequired/.params before doing
-- so. Core.commands.listCommands() (Kora.commands.list()) only ever returns
-- {name, help, permission} -- it has no reason to leak a raw handler function
-- to every caller -- so those three extra fields are captured HERE, at
-- QBCore.Commands.Add time, in a side table keyed by name and merged into the
-- List entry on rebuild. Same "only reflects Add/Refresh" limitation as the
-- rest of this table.
local commandExtras = {}
QBCore.Commands.List = {}
local function rebuildCommandList()
    -- Defensive: in production commands/server.lua loads before this file (see
    -- fxmanifest), but guard the call so a partial load order can't crash us.
    if not (Core.commands and Core.commands.listCommands) then return end
    for k in pairs(QBCore.Commands.List) do QBCore.Commands.List[k] = nil end
    for _, c in ipairs(Core.commands.listCommands()) do
        local extra = commandExtras[c.name]
        QBCore.Commands.List[c.name] = {
            name = c.name,
            help = c.help,
            permission = c.permission,
            params = extra and extra.params,
            argsrequired = extra and extra.argsrequired,
            callback = extra and extra.callback,
        }
    end
end
QBCore.Commands.Add = function(name, help, args, argsRequired, cb, permission)
    -- Stock resources also use { { 'id', 'description' } } suggestions. Adapt
    -- that legacy shape here, leaving the native command contract strict and
    -- retaining the caller's original params in the public legacy command list.
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
    Core.commands.addCommand(name, help, nativeArgs, argsRequired, cb, permission)
    commandExtras[name] = { params = args, argsrequired = argsRequired, callback = cb }
    rebuildCommandList()
end
QBCore.Commands.Refresh = function(src) Core.commands.refreshCommands(src); rebuildCommandList() end
rebuildCommandList()

-- --- QBCore.Config -----------------------------------------------------------
Core.compat.populateLegacyConfig()

-- Force the lazy QBCore.Shared data views to materialise as REAL keys now.
-- A consumer's GetCoreObject() result crosses the export boundary as a
-- msgpack copy: the metatable (and therefore coreobject.lua's lazy __index)
-- does not survive the crossing, so any key not rawset by this point simply
-- does not exist in the consumer's copy of Shared -- which is how
-- `for job in pairs(QBCore.Shared.Jobs)` in an external resource ends up
-- iterating nil even though the same read works fine inside this VM. The
-- registries are guaranteed created AND seed-ingested here: both happen
-- synchronously in modules/registry/server.lua, which loads before this file.
for _, k in ipairs({ 'Items', 'Vehicles', 'Jobs', 'Gangs', 'Weapons' }) do
    local _ = QBCore.Shared[k]
end

-- --- Exports -----------------------------------------------------------------
-- GetCoreObject supports upstream's optional `filters` array (return a subset of
-- the object). Beyond it, real qb-core exposes GetShared plus EVERY
-- QBCore.Functions.* as a direct exports['qb-core']:Fn(...) -- mirror that with
-- one provideExport loop so `exports['qb-core']:GetPlayer(src)` etc. resolve.
local function getCoreObject(filters)
    if not filters then return QBCore end
    local results = {}
    for i = 1, #filters do local k = filters[i]; if QBCore[k] then results[k] = QBCore[k] end end
    return results
end

if Config.compat.coreObjectExport then
    provideExport('qb-core', 'GetCoreObject', getCoreObject)
    provideExport('qb-core', 'GetShared', GetShared)
    -- Thin per-namespace wrappers around GetShared -- real qb-core exposes
    -- these as their own top-level exports too. GetSharedJobs/Gangs go through
    -- the SAME GetShared('Jobs'/'Gangs') call, so they resolve to the
    -- legacy zero-based grade view (QBCore.Shared.Jobs/Gangs), not the raw
    -- internal registry.
    provideExport('qb-core', 'GetSharedItems', function() return GetShared('Items') end)
    provideExport('qb-core', 'GetSharedVehicles', function() return GetShared('Vehicles') end)
    provideExport('qb-core', 'GetSharedJobs', function() return GetShared('Jobs') end)
    provideExport('qb-core', 'GetSharedGangs', function() return GetShared('Gangs') end)
    provideExport('qb-core', 'GetSharedWeapons', function() return GetShared('Weapons') end)
    for name, fn in pairs(QBCore.Functions) do
        if type(fn) == 'function' then provideExport('qb-core', name, fn) end
    end
end
