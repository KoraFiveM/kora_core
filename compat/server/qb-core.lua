-- compat/server/qb-core.lua -- the server half of the QBCore object, exposed via
-- exports['qb-core']:GetCoreObject(). Every function here calls the internal
-- Core.* implementation DIRECTLY (never exports.qbcore:fn()), so
-- GetInvokingResource() inside those resolves to the original external consumer
-- rather than to qbcore -- load-bearing for the owner-tracked registrations
-- (commands, useables, registry entries, onChange).

local PI = CoreInternal.player

-- `provide 'qb-core'` alone doesn't make exports['qb-core']:GetCoreObject()
-- resolve here; registering the __cfx_export event does (same identity hijack as
-- qbtarget/client/compat/ox-target.lua).
local function provideExport(providedResource, exportName, func)
    AddEventHandler(('__cfx_export_%s_%s'):format(providedResource, exportName), function(setCB)
        setCB(func)
    end)
end

-- --- the per-player QBPlayer compat object -----------------------------------

-- Build the legacy QBPlayer for a source: PlayerData (a LIVE reference to the
-- internal blob, so same-VM reads stay fresh) + a Functions method table whose
-- methods are two-line wrappers onto the funnel.
local function buildQBPlayer(src)
    local handle = PI.handle(src)
    if not handle then return nil end

    local self = { PlayerData = handle.PlayerData, Offline = false }
    local F = {}
    self.Functions = F

    function F.GetName() return handle.PlayerData.name end
    function F.GetPlayerData() return Core.util.deepClone(handle.PlayerData) end

    function F.SetJob(name, grade) return Core.jobs.setJob(src, name, grade) end
    function F.SetGang(name, grade) return Core.jobs.setGang(src, name, grade) end
    function F.SetJobDuty(onDuty) return Core.jobs.setJobDuty(src, onDuty) end
    function F.SetJobData(k, v) return Core.player.setPath(src, { 'job', k }, v) end
    function F.SetGangData(k, v) return Core.player.setPath(src, { 'gang', k }, v) end

    function F.AddMoney(t, amount, reason) return Core.money.addMoney(src, t, amount, reason) end
    function F.RemoveMoney(t, amount, reason) return Core.money.removeMoney(src, t, amount, reason) end
    function F.SetMoney(t, amount, reason) return Core.money.setMoney(src, t, amount, reason) end
    function F.GetMoney(t) return Core.money.getMoney(src, t) end

    function F.AddItem(name, amount, slot, info) return Core.inventory.addItem(src, name, amount, slot, info) end
    function F.RemoveItem(name, amount, slot) return Core.inventory.removeItem(src, name, amount, slot) end
    function F.GetItemByName(name) return Core.inventory.getItemByName(src, name) end
    function F.GetItemsByName(name) return Core.inventory.getItemsByName(src, name) end
    function F.GetItemBySlot(slot) return Core.inventory.getItemBySlot(src, slot) end
    function F.ClearInventory(keep) return Core.inventory.clearInventory(src, keep) end
    function F.SetInventory(items) return Core.inventory.setItems(src, items) end

    function F.SetMetaData(k, v) return Core.metadata.setMetaData(src, k, v) end
    function F.GetMetaData(k) return Core.metadata.getMetaData(src, k) end

    function F.SetCharInfo(k, v) return Core.player.setPath(src, { 'charinfo', k }, v) end
    function F.SetCreditCard(number) return Core.player.setPath(src, { 'charinfo', 'card' }, number) end

    -- Legacy full-data writers. SetPlayerData(key, value) targets a root key.
    function F.SetPlayerData(key, value)
        local column = PI.COLUMN_FOR[key]
        if not column and Config.compat.warnOnUnknownRoot then
            print(("^3[qbcore:qb-core-bridge]^7 SetPlayerData('%s', ...) targets an unknown root key with no DB "
                .. "column mapping; it will not persist."):format(tostring(key)))
        end
        return Core.player.setPath(src, { key }, value)
    end
    function F.UpdatePlayerData() --[[ no-op: data is always live here ]] end

    function F.Save() Core.persistence.saveNow(handle); return true end
    function F.Logout() return Core.player.logout(src) end

    return self
end

-- Keep QBCore.Players in sync as players load / unload.
AddEventHandler('qbcore:server:playerLoaded', function(src)
    QBCore.Players[src] = buildQBPlayer(src)
end)
AddEventHandler('qbcore:server:playerDropped', function(src)
    QBCore.Players[src] = nil
end)

-- --- QBCore.Functions.* ------------------------------------------------------

local F = QBCore.Functions

function F.GetPlayer(src)
    if QBCore.Players[src] then return QBCore.Players[src] end
    -- Build lazily if the load hook hasn't fired yet.
    local p = buildQBPlayer(src)
    if p then QBCore.Players[src] = p end
    return p
end

function F.GetPlayerByCitizenId(cid)
    local handle = PI.byCitizenId[cid]
    return handle and F.GetPlayer(handle.source) or nil
end

function F.GetPlayerByPhone(number)
    for src in pairs(PI.bySource) do
        local h = PI.handle(src)
        if h and h.PlayerData.phone == number then return F.GetPlayer(src) end
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
    return { PlayerData = data, Offline = true }
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

-- Callbacks -> qblib's QB.callback.
function F.CreateCallback(name, cb)
    QB.callback.register(name, function(src, ...) return cb(src, ...) end)
end
-- Real QBCore's TriggerCallback forwards EVERY value the client handler
-- returned to `cb`, not just the first -- qblib's QB.callback.trigger (called
-- here cross-resource, qbcore -> qblib) now supports that end to end, so
-- table.pack/unpack is all that's needed to match it faithfully.
function F.TriggerCallback(name, src, cb, ...)
    local args = { ... }
    CreateThread(function()
        local results = table.pack(QB.callback.trigger(src, name, table.unpack(args)))
        cb(table.unpack(results, 1, results.n))
    end)
end

-- Useable items.
function F.CreateUseableItem(name, cb) Core.inventory.createUseable(name, cb) end
function F.CanUseItem(name) return Core.registry.getShared('items', name) ~= nil end
function F.UseItem(src, item) return Core.inventory.useItem(src, type(item) == 'table' and item.name or item) end

-- Permissions / admin.
function F.HasPermission(src, perm) return Core.permissions.hasPermission(src, perm) end
function F.GetPermission(src) return Core.permissions.getPermission(src) end
function F.AddPermission(src, perm) return Core.permissions.addPermission(src, perm) end
function F.IsOptin(src) return Core.permissions.isOptin(src) end
function F.Kick(src, reason) DropPlayer(src, reason or 'Kicked') end

function F.Notify(src, text, type_, length)
    TriggerClientEvent('QBCore:Notify', src, text, type_, length)
end

function F.HasItem(src, items, amount) return Core.inventory.hasItem(src, items, amount) end

function F.ExecuteSql(_, query, cb)
    print('^3[qbcore:qb-core-bridge]^7 ExecuteSql is deprecated and its `wait` argument is ignored; use '
        .. 'QB.sql.query or exports.qbsql:query.')
    CreateThread(function()
        local rows = QB.sql.query(query, {})
        if cb then cb(rows) end
    end)
end

function F.PaycheckInterval() return Config.jobs.paycheckInterval or 300000 end

-- --- QBCore.Player.* ---------------------------------------------------------

local P = QBCore.Player
function P.Login(src, citizenid) local d = Core.persistence._load(citizenid); return d and Core.player.login(src, citizenid, d) end
function P.Logout(src) return Core.player.logout(src) end
function P.Save(src) local h = PI.handle(src); if h then Core.persistence.saveNow(h) end end
function P.SaveOffline() --[[ offline saves go through QB.sql directly ]] end
function P.CreatePlayer(src, charinfo, cid) return Core.player.createCharacter(src, charinfo, cid) end
function P.DeleteCharacter(src, citizenid) return Core.multichar.deleteCharacter(src, citizenid) end
function P.CheckPlayerData(src) return F.GetPlayer(src) end
function P.ForceUpdatePlayerData() --[[ live data; no-op ]] end

-- QBCore.Commands.Add -> Core.commands.add.
QBCore.Commands.Add = function(name, help, args, argsRequired, cb, permission)
    Core.commands.addCommand(name, help, args, argsRequired, cb, permission)
end
QBCore.Commands.Refresh = function(src) Core.commands.refreshCommands(src) end
QBCore.Commands.List = function() return Core.commands.listCommands() end

-- Map the commonly-read Config fields onto ours.
QBCore.Config.Money = { MoneyTypes = Config.money.default, PayCheckTimeOut = 10 }
QBCore.Config.Player = { MaxWeight = Config.inventory.maxWeight, MaxInvSlots = Config.inventory.slots }
QBCore.Config.MaxPlayers = GetConvarInt('sv_maxclients', 32)

-- Register the export. A nested table of functions crossing exports() is the
-- assumption Phase 0 validated (and legacy qb-core has relied on for years).
if Config.compat.coreObjectExport then
    provideExport('qb-core', 'GetCoreObject', function() return QBCore end)
end
