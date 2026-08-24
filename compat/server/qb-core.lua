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

    -- PlayerData is a legacy-shaped VIEW (job/gang grade.level translated to
    -- real qb-core's zero-based numbering), NOT `handle.PlayerData` itself --
    -- see Core.compat.toLegacyPlayerData's comment for why a live metatable
    -- proxy can't be used here. Kept in sync incrementally by
    -- Core.compat.onPlayerDataChanged (registered below), which
    -- Core.player.setPath calls on every write, so this never goes stale --
    -- including root-level replacements like SetJob/SetGang/SetInventory.
    local self = { PlayerData = Core.compat.toLegacyPlayerData(handle.PlayerData), Offline = false }
    local F = {}
    self.Functions = F

    function F.GetName() return handle.PlayerData.name end
    function F.GetPlayerData() return Core.compat.toLegacyPlayerData(Core.util.deepClone(handle.PlayerData)) end

    function F.SetJob(name, grade) return Core.jobs.setJob(src, name, Core.compat.fromLegacyGradeLevel(grade)) end
    function F.SetGang(name, grade) return Core.jobs.setGang(src, name, Core.compat.fromLegacyGradeLevel(grade)) end
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

    -- --- methods present on CURRENT qb-core's player object (server/player.lua's
    -- varargMethods/noargMethods) that classic-era compat lacked. Added so a
    -- script written against modern qb-core (`Player.Functions.Notify(...)`,
    -- `Player.Functions.HasItem(...)`, the reputation + extension methods) works
    -- too -- this object is the UNION of both qb-core eras.
    function F.Notify(text, type_, length) TriggerClientEvent('QBCore:Notify', src, text, type_, length) end
    function F.HasItem(items, amount) return Core.inventory.hasItem(src, items, amount) end

    -- Reputation lives in metadata.rep (a name->number map), matching qb-core.
    function F.GetRep(rep)
        local reps = Core.metadata.getMetaData(src, 'rep') or {}
        return reps[rep] or 0
    end
    function F.AddRep(rep, amount)
        amount = tonumber(amount)
        if not rep or not amount then return end
        local reps = Core.metadata.getMetaData(src, 'rep') or {}
        reps[rep] = math.max(0, (reps[rep] or 0) + amount)
        Core.metadata.setMetaData(src, 'rep', reps)
    end
    function F.RemoveRep(rep, amount)
        amount = tonumber(amount)
        if not rep or not amount then return end
        local reps = Core.metadata.getMetaData(src, 'rep') or {}
        reps[rep] = math.max(0, (reps[rep] or 0) - amount)
        Core.metadata.setMetaData(src, 'rep', reps)
    end

    -- UpdateClient pushes PlayerData to the owning client. Our replication does
    -- that automatically on every setPath, so there's nothing to force here --
    -- kept as a no-op alias pair so both legacy names resolve. (UpdatePlayerData
    -- above is the same no-op for the identical reason.)
    function F.UpdateClient() --[[ data is already live via delta replication ]] end

    -- Extension hooks: qb-core lets a resource bolt a custom method/field onto a
    -- player object at runtime. AddMethod adds to THIS player's Functions table;
    -- AddField adds a field to the player object itself.
    function F.AddMethod(name, method) F[name] = method; return true end
    function F.AddField(name, data) self[name] = data; return true end

    return self
end

-- Keep QBCore.Players in sync as players load / unload.
AddEventHandler('qbcore:server:playerLoaded', function(src)
    QBCore.Players[src] = buildQBPlayer(src)
end)
AddEventHandler('qbcore:server:playerDropped', function(src)
    QBCore.Players[src] = nil
end)

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
    if root == 'job' or root == 'gang' then
        Core.util.pathSet(player.PlayerData, path, #path == 1 and Core.compat.toLegacyJobOrGang(value) or value)
    else
        Core.util.pathSet(player.PlayerData, path, value)
    end
end

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

-- Callbacks -> qblib's QB.callback, PLUS real qb-core's raw net-event wire
-- protocol (QBCore:Server:TriggerCallback / QBCore:Client:TriggerCallback).
-- Some legacy scripts skip QBCore.Functions.TriggerCallback entirely and
-- fire the raw event themselves, so a handler registered via CreateCallback
-- must be reachable through BOTH transports without ever running twice for
-- one incoming request.
--
-- legacyCallbacks is the single source of truth: CreateCallback stores the
-- handler here (keyed by name), and BOTH the qblib-registered wrapper below
-- and the raw net event handler look the current handler up from this table
-- at dispatch time rather than closing over it -- so a later CreateCallback
-- call for the same name (a legitimate resource restart) updates what both
-- transports invoke, without re-registering either transport.
local legacyCallbacks = {}

-- Real QBCore hands the legacy handler a RESPONDER function as its second
-- argument -- function(source, cb, ...) ... cb(result) end -- and the handler
-- is expected to call that responder, not `return` its result. qblib's
-- QB.callback.register instead ships back whatever the registered function
-- RETURNS. Bridging one onto the other means giving the legacy handler a
-- `cb` that resolves a promise, then awaiting that promise for the actual
-- return. A handler that never calls `cb` (a legitimate early-return, e.g.
-- qb-banking's card-missing checks) would otherwise leak the awaiting
-- coroutine and qblib's pending request forever -- the timeout guards that.
function F.CreateCallback(name, handler)
    legacyCallbacks[name] = handler
    QB.callback.register(name, function(src, ...)
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
function F.CreateUseableItem(name, cb) Core.inventory.createUseable(name, cb) end
function F.CanUseItem(name) return Core.registry.getShared('items', name) ~= nil end
function F.UseItem(src, item) return Core.inventory.useItem(src, type(item) == 'table' and item.name or item) end

-- Permissions / admin.
function F.HasPermission(src, perm) return Core.permissions.hasPermission(src, perm) end
function F.GetPermission(src) return Core.permissions.getPermission(src) end
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
        .. 'QB.sql.query or exports.qbsql:query.')
    CreateThread(function()
        local rows = QB.sql.query(query, {})
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

-- CFX delivers export-boundary callbacks as tables with a __call/functionRef;
-- treat those as callable too (same test real qb-core uses).
local function isCallable(v)
    if type(v) == 'function' then return true end
    if type(v) == 'table' then
        if type(rawget(v, '__cfx_functionReference')) == 'string' then return true end
        local mt = getmetatable(v)
        return mt ~= nil and type(mt.__call) == 'function'
    end
    return false
end

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

-- Server-side closest-entity helpers -- thin forwards to QB.world.getClosestEntity
-- (see AGENTS.md's "thin forwards to QB.*, not reimplementations"). GetClosestPlayer
-- additionally maps the ped QB.world returns back to a player id via QB.closest.player,
-- matching real qb-core's (playerId, distance) signature.
function F.GetClosestPlayer(source, coords)
    coords = coords and (type(coords) == 'table' and vector3(coords.x, coords.y, coords.z) or coords) or nil
    local result = QB.closest.player(source, coords)
    return result.id or -1, result.distance or -1
end

local function closestFromPool(source, coords, entityType, excludeSelf)
    coords = coords and (type(coords) == 'table' and vector3(coords.x, coords.y, coords.z) or coords)
        or GetEntityCoords(GetPlayerPed(source))
    local options = excludeSelf and { excludeEntities = { GetPlayerPed(source) } } or nil
    local entity, _, distance = QB.world.getClosestEntity(entityType, coords, options)
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
    if not (source and bucket) then return false end
    local plicense = F.GetIdentifier(source, 'license')
    SetPlayerRoutingBucket(source, bucket)
    QBCore.Player_Buckets[plicense] = { id = source, bucket = bucket }
    return true
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

-- Server-side vehicle creation (ported verbatim from upstream).
function F.SpawnVehicle(source, model, coords, warp)
    local ped = GetPlayerPed(source)
    model = type(model) == 'string' and joaat(model) or model
    if not coords then coords = GetEntityCoords(ped) end
    local heading = coords.w and coords.w or 0.0
    local veh = CreateVehicle(model, coords.x, coords.y, coords.z, heading, true, true)
    local t = 0
    while not DoesEntityExist(veh) and t < 1000 do Wait(0); t = t + 1 end
    if warp then
        t = 0
        while GetVehiclePedIsIn(ped) ~= veh and t < 100 do Wait(0); t = t + 1; TaskWarpPedIntoVehicle(ped, veh, -1) end
    end
    t = 0
    while NetworkGetEntityOwner(veh) ~= source and t < 1000 do Wait(0); t = t + 1 end
    return veh
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
    local veh = CreateVehicleServerSetter(model, vehtype, coords, coords.w and coords.w or 0.0)
    local t = 0
    while not DoesEntityExist(veh) and t < 1000 do Wait(0); t = t + 1 end
    if warp then TaskWarpPedIntoVehicle(GetPlayerPed(source), veh, -1) end
    return veh
end

-- Client callbacks: real qb-core's own raw wire protocol
-- (QBCore:Client:TriggerClientCallback / QBCore:Server:TriggerClientCallback).
-- This used to route through qblib's callback system instead, but that meant
-- TriggerClientCallback would deliver over ONE transport (qblib) while a
-- handler registered via the client's CreateClientCallback is reachable over
-- TWO (qblib AND the raw net event, since CreateClientCallback now also
-- stores into legacyClientCallbacks -- see compat/client/qb-core.lua). Firing
-- both transports for a single TriggerClientCallback call would invoke the
-- client's handler twice for one logical request, so this now speaks the raw
-- wire exclusively (matching real qb-core's own implementation), and the
-- qblib path is left for cross-resource callers that talk to QB.callback
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
    local row = QB.sql.single('SELECT id, reason, expire FROM bans WHERE license = ?', { license })
    if not row then return false end
    if os.time() < tonumber(row.expire) then
        local t = os.date('*t', tonumber(row.expire))
        return true, ('You have been banned from the server:\n%s\nYour ban expires %d/%d/%d %d:%d\n')
            :format(row.reason, t.day, t.month, t.year, t.hour, t.min)
    end
    QB.sql.query('DELETE FROM bans WHERE id = ?', { row.id })
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
    QB.sql.insert('INSERT INTO bans (name, license, discord, ip, reason, expire, bannedby) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        name, F.GetIdentifier(playerId, 'license'), F.GetIdentifier(playerId, 'discord'),
        F.GetIdentifier(playerId, 'ip'), origin, 2147483647, 'Anti Cheat',
    })
    DropPlayer(playerId, ('You have been banned for exploiting: %s'):format(tostring(origin)))
    TriggerEvent('qb-log:server:CreateLog', 'anticheat', 'Anti-Cheat', 'red', name .. ' banned for exploiting ' .. tostring(origin), true)
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

local function sharedAdd(kind, key, record)
    if type(key) ~= 'string' then return false, 'invalid_' .. kind .. '_name' end
    if Core.registry.getShared(REGISTRY_FOR[kind], key) then return false, kind .. '_exists' end
    local ok, err = Core.registry.registerShared(REGISTRY_FOR[kind], key, record)
    if not ok then return false, err end
    TriggerClientEvent('QBCore:Client:OnSharedUpdate', -1, SHARED_KEY[kind], key, record)
    TriggerEvent('QBCore:Server:UpdateObject')
    return true, 'success'
end
local function sharedUpdate(kind, key, record)
    if type(key) ~= 'string' then return false, 'invalid_' .. kind .. '_name' end
    if not Core.registry.getShared(REGISTRY_FOR[kind], key) then return false, kind .. '_not_exists' end
    Core.registry.registerShared(REGISTRY_FOR[kind], key, record)
    TriggerClientEvent('QBCore:Client:OnSharedUpdate', -1, SHARED_KEY[kind], key, record)
    TriggerEvent('QBCore:Server:UpdateObject')
    return true, 'success'
end
local function sharedRemove(kind, key)
    if type(key) ~= 'string' then return false, 'invalid_' .. kind .. '_name' end
    if not Core.registry.getShared(REGISTRY_FOR[kind], key) then return false, kind .. '_not_exists' end
    Core.registry.unregisterShared(REGISTRY_FOR[kind], key)
    TriggerClientEvent('QBCore:Client:OnSharedUpdate', -1, SHARED_KEY[kind], key, nil)
    TriggerEvent('QBCore:Server:UpdateObject')
    return true, 'success'
end
local function sharedAddMany(kind, records)
    for key in pairs(records) do
        if type(key) ~= 'string' then return false, 'invalid_' .. kind .. '_name' end
        if Core.registry.getShared(REGISTRY_FOR[kind], key) then return false, kind .. '_exists', key end
    end
    for key, record in pairs(records) do Core.registry.registerShared(REGISTRY_FOR[kind], key, record) end
    TriggerClientEvent('QBCore:Client:OnSharedUpdateMultiple', -1, SHARED_KEY[kind], records)
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
-- metatable resolves to the live materialised registry table -- so this body is
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

-- Login accepts real qb-core's (source, citizenid, newData); newData is used
-- verbatim when supplied, otherwise the character is loaded from persistence.
function P.Login(src, citizenid, newData)
    local d = newData or Core.persistence._load(citizenid)
    return d and Core.player.login(src, citizenid, d)
end
function P.Logout(src) return Core.player.logout(src) end
function P.Save(src) local h = PI.handle(src); if h then Core.persistence.saveNow(h) end end
function P.SaveOffline() --[[ offline saves go through QB.sql directly ]] end

function P.CreatePlayer(srcOrData, charinfo, cid)
    if type(srcOrData) == 'table' then
        -- real qb-core CreatePlayer(PlayerData, Offline) builds a player from a
        -- full pre-made blob -- an internal login-flow path we don't expose.
        -- External scripts create characters via the multichar events /
        -- exports.qbcore:createCharacter, so refuse loudly rather than silently.
        print('^3[qbcore:qb-core-bridge]^7 CreatePlayer(PlayerData, Offline) is not supported; use createCharacter/selectCharacter.')
        return nil
    end
    return Core.player.createCharacter(srcOrData, charinfo, cid)
end
function P.DeleteCharacter(src, citizenid) return Core.multichar.deleteCharacter(src, citizenid) end
function P.ForceDeleteCharacter(citizenid)
    return QB.sql.query('UPDATE `players` SET `deleted_at` = NOW() WHERE `citizenid` = ?', { citizenid })
end
function P.CheckPlayerData(src) return F.GetPlayer(src) end
function P.ForceUpdatePlayerData() --[[ live data; no-op ]] end

function P.GetOfflinePlayer(citizenid) return F.GetOfflinePlayerByCitizenId(citizenid) end
function P.GetPlayerByLicense(license) return F.GetPlayerByLicense(license) end
function P.GetOfflinePlayerByLicense(license)
    local row = QB.sql.single('SELECT `citizenid` FROM `players` WHERE `license` = ? AND `deleted_at` IS NULL LIMIT 1', { license })
    return row and F.GetOfflinePlayerByCitizenId(row.citizenid) or nil
end

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
-- (Commands another resource registers straight through QB.commands aren't
-- reflected until the next Add/Refresh -- documented in AGENTS.md.)
--
-- Real qb-core's List entries also carry `params`/`argsrequired`/`callback`
-- (not just name/help/permission) -- QBCore:CallCommand (qb-core-events.lua)
-- invokes .callback directly, and checks .argsrequired/.params before doing
-- so. Core.commands.listCommands() (QB.commands.list()) only ever returns
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
    commandExtras[name] = { params = args, argsrequired = argsRequired, callback = cb }
    Core.commands.addCommand(name, help, args, argsRequired, cb, permission)
    rebuildCommandList()
end
QBCore.Commands.Refresh = function(src) Core.commands.refreshCommands(src); rebuildCommandList() end
rebuildCommandList()

-- --- QBCore.Config -----------------------------------------------------------
-- Map the commonly-read Config fields onto ours. Config.Server is what
-- Kick/IsWhitelisted/RemovePermission read (Discord link, whitelist toggle,
-- the permission-group list).
QBCore.Config.Money = { MoneyTypes = Config.money.default, PayCheckTimeOut = 10 }
QBCore.Config.Player = { MaxWeight = Config.inventory.maxWeight, MaxInvSlots = Config.inventory.slots }
QBCore.Config.MaxPlayers = GetConvarInt('sv_maxclients', 32)
QBCore.Config.Server = {
    Discord = GetConvar('qb_discord', ''),
    Whitelist = false,
    WhitelistPermission = 'admin',
    Permissions = { 'god', 'admin', 'mod' },
    Closed = false,
    ClosedReason = 'Server Closed',
}
-- Upstream constants some legacy scripts read directly (real qb-core's
-- shared/config.lua). Informational-only here -- they don't drive our own
-- needs-decay loop, which is server-owned on a different cadence -- so these
-- are just hardcoded to match upstream's documented defaults for any legacy
-- script that reads them directly.
QBCore.Config.UpdateInterval = 5
QBCore.Config.StatusInterval = 5000

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
