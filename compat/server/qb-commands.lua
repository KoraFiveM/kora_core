-- compat/server/qb-commands.lua -- the 20 stock qb-core default commands
-- (qb-core/server/commands.lua), registered through the compat
-- QBCore.Commands.Add path so they get the same owner tracking, chat
-- suggestions, `command.<name>` ACE, QBCore:Server:PreCommandExecution hook and
-- QBCore:CallCommand reachability as any other legacy command.
--
-- Kora stays authoritative: money goes through Core.money (cash stays
-- item-backed), job/gang through Core.jobs, permissions through the
-- Core.permissions principals, /car spawns a server-owned networked vehicle and
-- grants keys through kora_vehiclekeys. Every argument is validated here
-- because QBCore:CallCommand hands handlers client-supplied args. Every use of
-- a non-'user' command is written to Core.logging under category 'admin'.
--
-- Disable with Config.compat.defaultCommands = false. A name another resource
-- (or kora itself) already registered is left alone; see docs/default-commands.md.

if Config.compat.defaultCommands == false then return end

local F = QBCore.Functions

local MAX_REASON = 200
local MAX_MESSAGE = 255
local NEARBY_RADIUS = 20.0
local DV_RADIUS = 5.0

local function reply(src, message, kind)
    if src == 0 then
        print(('[qbcore:commands] %s'):format(message))
        return
    end
    TriggerClientEvent('QBCore:Notify', src, message, kind or 'primary')
end

local function audit(src, name, data)
    data = data or {}
    data.command = name
    local ok, err = pcall(Core.logging.logEvent, 'admin', src, data)
    if not ok then print(('^3[qbcore:commands]^7 audit log failed for /%s: %s'):format(name, tostring(err))) end
end

-- Handler args can come from QBCore:CallCommand (any client), so never assume
-- strings: coerce, and bound what gets logged.
local function str(value, max)
    if type(value) ~= 'string' and type(value) ~= 'number' then return nil end
    value = tostring(value)
    return max and value:sub(1, max) or value
end

local function loggable(args)
    local out = {}
    for i = 1, math.min(#args, 8) do out[i] = str(args[i], 64) or type(args[i]) end
    return out
end

local function finite(value)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    return n
end

local function toInteger(value)
    local n = finite(value)
    if not n or n % 1 ~= 0 then return nil end
    return n
end

local function resolveTarget(arg)
    local id = toInteger(arg)
    if not id or id < 1 then return nil end
    local player = F.GetPlayer(id)
    if not player then return nil end
    return id, player
end

local function requirePlayer(src)
    if src == 0 then
        reply(src, 'This command must be used by a player in game.', 'error')
        return false
    end
    return true
end

local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function moneyType(arg)
    local account = str(arg, 32)
    account = account and account:lower()
    for _, configured in ipairs(Config.money.types) do
        if configured == account then return account end
    end
end

local existing = {}
for _, command in ipairs(Core.commands.listCommands()) do existing[command.name] = true end

local function register(name, help, params, argsRequired, permission, handler)
    if existing[name] then
        print(('^3[qbcore:commands]^7 /%s is already registered by another resource; keeping that one.'):format(name))
        return
    end
    QBCore.Commands.Add(name, help, params, argsRequired, function(src, args, raw)
        args = type(args) == 'table' and args or {}
        -- QBCore:CallCommand reaches the raw callback with only the per-command
        -- ACE checked, so enforce the permission level here as well.
        if permission ~= 'user' and src ~= 0 and not F.HasPermission(src, permission) then
            audit(src, name, { args = loggable(args), denied = true })
            return reply(src, 'You do not have permission to use this command.', 'error')
        end
        if permission ~= 'user' then audit(src, name, { args = loggable(args) }) end
        return handler(src, args, raw)
    end, permission)
end

local function param(name, help) return { name = name, help = help } end

register('tp', 'TP To Player or Coords (Admin Only)', {
    param('id/x', 'ID of player or X position'), param('y', 'Y position'), param('z', 'Z position'),
}, false, 'admin', function(src, args)
    if not requirePlayer(src) then return end
    local first = str(args[1])
    if first and not args[2] and not args[3] then
        if tonumber(first) then
            local id = toInteger(first)
            local target = id and id >= 1 and F.GetPlayer(id) and GetPlayerPed(id) or 0
            if target and target ~= 0 then
                TriggerClientEvent('QBCore:Command:TeleportToPlayer', src, GetEntityCoords(target))
            else
                reply(src, 'Player not online', 'error')
            end
        else
            local location = QBCore.Shared.Locations and QBCore.Shared.Locations[first]
            if location then
                TriggerClientEvent('QBCore:Command:TeleportToCoords', src, location.x, location.y, location.z, location.w)
            else
                reply(src, 'Location does not exist', 'error')
            end
        end
    elseif first and args[2] and args[3] then
        local function coordinate(value) return finite((str(value) or ''):gsub(',', '')) end
        local x, y, z = coordinate(args[1]), coordinate(args[2]), coordinate(args[3])
        local heading = args[4] and coordinate(args[4]) or false
        if x and y and z then
            TriggerClientEvent('QBCore:Command:TeleportToCoords', src, x + 0.0, y + 0.0, z + 0.0, heading and heading + 0.0 or false)
        else
            reply(src, 'Incorrect format', 'error')
        end
    else
        reply(src, 'Not every argument has been entered (x, y, z)', 'error')
    end
end)

register('tpm', 'TP To Marker (Admin Only)', {}, false, 'admin', function(src)
    if not requirePlayer(src) then return end
    TriggerClientEvent('QBCore:Command:GoToMarker', src)
end)

register('togglepvp', 'Toggle PVP on the server (Admin Only)', {}, false, 'admin', function(src)
    QBCore.Config.Server.PVP = not QBCore.Config.Server.PVP
    TriggerClientEvent('QBCore:Client:PvpHasToggled', -1, QBCore.Config.Server.PVP)
    reply(src, QBCore.Config.Server.PVP and 'PVP enabled' or 'PVP disabled', 'success')
end)

-- A player who joins while PVP is off must not default to on.
AddEventHandler('qbcore:server:playerLoaded', function(src)
    if QBCore.Config.Server.PVP == false then TriggerClientEvent('QBCore:Client:PvpHasToggled', src, false) end
end)

local function configuredPermission(arg)
    local permission = str(arg, 32)
    permission = permission and permission:lower()
    if not permission or not permission:match('^[%a_][%w_]*$') then return nil end
    for _, allowed in ipairs(QBCore.Config.Server.Permissions) do
        if allowed == permission then return permission end
    end
end

local function permissionCommand(name, help, apply, verb)
    register(name, help, {
        param('id', 'ID of player'), param('permission', 'Permission level'),
    }, true, 'god', function(src, args)
        local id = resolveTarget(args[1])
        if not id then return reply(src, 'Player not online', 'error') end
        local permission = configuredPermission(args[2])
        if not permission then
            return reply(src, 'Permission must be one of: ' .. table.concat(QBCore.Config.Server.Permissions, ', '), 'error')
        end
        audit(src, name, { target = id, permission = permission })
        apply(id, permission)
        QBCore.Commands.Refresh(id)
        reply(src, ('%s %s permission %s player %d'):format(verb[1], permission, verb[2], id), 'success')
    end)
end

permissionCommand('addpermission', 'Give Player Permissions (God Only)',
    function(id, permission) F.AddPermission(id, permission) end, { 'Granted', 'to' })
permissionCommand('removepermission', 'Remove Player Permissions (God Only)',
    function(id, permission) F.RemovePermission(id, permission) end, { 'Removed', 'from' })

register('openserver', 'Open the server for everyone (Admin Only)', {}, false, 'admin', function(src)
    if not QBCore.Config.Server.Closed then return reply(src, 'The server is already open', 'error') end
    if src ~= 0 and not F.HasPermission(src, 'admin') then
        return F.Kick(src, 'You don\'t have permissions for this..')
    end
    QBCore.Config.Server.Closed = false
    reply(src, 'The server has been opened', 'success')
end)

register('closeserver', 'Close the server for people without permissions (Admin Only)', {
    param('reason', 'Reason for closing (optional)'),
}, false, 'admin', function(src, args)
    if QBCore.Config.Server.Closed then return reply(src, 'The server is already closed', 'error') end
    if src ~= 0 and not F.HasPermission(src, 'admin') then
        return F.Kick(src, 'You don\'t have permissions for this..')
    end
    local parts = {}
    for i = 1, math.min(#args, 32) do parts[#parts + 1] = str(args[i], 64) or '' end
    local reason = #parts > 0 and table.concat(parts, ' '):sub(1, MAX_REASON) or 'No reason specified'
    QBCore.Config.Server.Closed = true
    QBCore.Config.Server.ClosedReason = reason
    for playerSrc in pairs(QBCore.Players) do
        if not F.HasPermission(playerSrc, QBCore.Config.Server.WhitelistPermission) then
            F.Kick(playerSrc, reason)
        end
    end
    reply(src, 'The server has been closed', 'success')
end)

-- Stock qb-core refuses new connections while Closed (kora_core had the flag but
-- never enforced it).
AddEventHandler('playerConnecting', function(_, setKickReason, deferrals)
    if not QBCore.Config.Server.Closed then return end
    if F.HasPermission(source, QBCore.Config.Server.WhitelistPermission) then return end
    local reason = QBCore.Config.Server.ClosedReason or 'Server Closed'
    if setKickReason then setKickReason(reason) end
    deferrals.defer()
    deferrals.done(reason)
end)

local function playerVehicle(ped)
    local vehicle = GetVehiclePedIsIn(ped, false)
    return vehicle ~= 0 and vehicle or nil
end

register('car', 'Spawn Vehicle (Admin Only)', { param('model', 'Model name of the vehicle') }, true, 'admin', function(src, args)
    if not requirePlayer(src) then return end
    local model = str(args[1], 64)
    if not model or not model:match('^[%w_]+$') or #model > 32 then
        return reply(src, 'Incorrect format', 'error')
    end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local coords = GetEntityCoords(ped)
    local previous = playerVehicle(ped)
    -- Server-owned networked entity: the spawn is authorized here, not trusted from a client event.
    local vehicle = F.SpawnVehicle(src, model, { x = coords.x, y = coords.y, z = coords.z, w = GetEntityHeading(ped) }, true)
    if not vehicle then return reply(src, 'Unable to spawn that vehicle', 'error') end
    if previous and previous ~= vehicle then DeleteEntity(previous) end

    local plate = GetVehicleNumberPlateText(vehicle)
    if plate and GetResourceState('kora_vehiclekeys') == 'started' then
        local ok, err = pcall(function() return exports.kora_vehiclekeys:giveKeys(src, plate) end)
        if not ok then print(('^3[qbcore:commands]^7 /car could not grant keys: %s'):format(tostring(err))) end
    end
    audit(src, 'car', { model = model, plate = plate })
end)

register('dv', 'Delete Vehicle (Admin Only)', {}, false, 'admin', function(src)
    if not requirePlayer(src) then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local occupied = playerVehicle(ped)
    local removed = 0
    if occupied then
        DeleteEntity(occupied)
        removed = 1
    else
        local origin = GetEntityCoords(ped)
        for _, vehicle in ipairs(GetAllVehicles()) do
            if distance(origin, GetEntityCoords(vehicle)) <= DV_RADIUS then
                DeleteEntity(vehicle)
                removed = removed + 1
            end
        end
    end
    audit(src, 'dv', { removed = removed })
end)

local function deleteAll(name, help, list, skip)
    register(name, help, {}, false, 'admin', function(src)
        local removed = 0
        for _, entity in ipairs(list()) do
            if not (skip and skip(entity)) then
                DeleteEntity(entity)
                removed = removed + 1
            end
        end
        audit(src, name, { removed = removed })
        reply(src, ('Deleted %d entities'):format(removed), 'success')
    end)
end

deleteAll('dvall', 'Delete All Vehicles (Admin Only)', function() return GetAllVehicles() end)
-- Stock also deletes player peds, which would delete the players themselves.
deleteAll('dvp', 'Delete All Peds (Admin Only)', function() return GetAllPeds() end, function(ped) return IsPedAPlayer and IsPedAPlayer(ped) end)
deleteAll('dvo', 'Delete All Objects (Admin Only)', function() return GetAllObjects() end)

local function moneyArgs(src, args)
    local id = resolveTarget(args[1])
    if not id then reply(src, 'Player not online', 'error'); return end
    local account = moneyType(args[2])
    if not account then
        reply(src, 'Type of money must be one of: ' .. table.concat(Config.money.types, ', '), 'error')
        return
    end
    local amount = finite(args[3])
    if not amount then reply(src, 'Incorrect format', 'error'); return end
    return id, account, amount
end

local MONEY_PARAMS = {
    param('id', 'Player ID'), param('moneytype', 'Type of money (cash, bank, crypto)'), param('amount', 'Amount of money'),
}

register('givemoney', 'Give A Player Money (Admin Only)', MONEY_PARAMS, true, 'admin', function(src, args)
    local id, account, amount = moneyArgs(src, args)
    if not id then return end
    -- An admin grant is not a taxable transaction.
    local ok, err = Core.money.addMoney(id, account, amount, 'Admin give money', true)
    audit(src, 'givemoney', { target = id, account = account, amount = amount, ok = ok and true or false })
    if not ok then reply(src, 'Could not give money: ' .. tostring(err), 'error') end
end)

register('setmoney', 'Set Players Money Amount (Admin Only)', MONEY_PARAMS, true, 'admin', function(src, args)
    local id, account, amount = moneyArgs(src, args)
    if not id then return end
    local ok, err = Core.money.setMoney(id, account, amount, 'Admin set money')
    audit(src, 'setmoney', { target = id, account = account, amount = amount, ok = ok and true or false })
    if not ok then reply(src, 'Could not set money: ' .. tostring(err), 'error') end
end)

register('job', 'Check Your Job', {}, false, 'user', function(src)
    local player = src ~= 0 and F.GetPlayer(src)
    if not player then return end
    local job = player.PlayerData.job
    reply(src, ('Job: %s | Grade: %s | Duty: %s'):format(tostring(job.label), tostring(job.grade.name), tostring(job.onduty)))
end)

register('gang', 'Check Your Gang', {}, false, 'user', function(src)
    local player = src ~= 0 and F.GetPlayer(src)
    if not player then return end
    local gang = player.PlayerData.gang
    reply(src, ('Gang: %s | Grade: %s'):format(tostring(gang.label), tostring(gang.grade.name)))
end)

local function roleCommand(name, help, kind, apply)
    register(name, help, {
        param('id', 'Player ID'), param(kind, kind == 'job' and 'Job name' or 'Gang name'),
        param('grade', kind == 'job' and 'Job grade' or 'Gang grade'),
    }, true, 'admin', function(src, args)
        local id = resolveTarget(args[1])
        if not id then return reply(src, 'Player not online', 'error') end
        local role = str(args[2], 64)
        role = role and role:lower()
        local grade = toInteger(args[3])
        if not role or not role:match('^[%w_%-]+$') then
            return reply(src, 'Incorrect format', 'error')
        end
        if not grade or grade < 0 then
            return reply(src, 'Grade must be a whole number of 0 or more', 'error')
        end
        -- Stock grades are zero-based; kora's are one-based.
        local ok, err = apply(id, role, Core.compat.fromLegacyGradeLevel(grade))
        audit(src, name, { target = id, [kind] = role, grade = grade, ok = ok and true or false })
        if not ok then reply(src, ('Could not set %s: %s'):format(kind, tostring(err)), 'error') end
    end)
end

roleCommand('setjob', 'Set A Players Job (Admin Only)', 'job', Core.jobs.setJob)
roleCommand('setgang', 'Set A Players Gang (Admin Only)', 'gang', Core.jobs.setGang)

local function messageOf(args, max)
    local parts = {}
    for i = 1, math.min(#args, 64) do parts[#parts + 1] = str(args[i], 128) or '' end
    return table.concat(parts, ' '):sub(1, max)
end

register('ooc', 'OOC Chat Message', {}, false, 'user', function(src, args)
    if not requirePlayer(src) then return end
    local player = F.GetPlayer(src)
    if not player then return end
    local message = messageOf(args, MAX_MESSAGE)
    if message == '' then return reply(src, 'All arguments must be filled out!', 'error') end
    local name = GetPlayerName(src) or tostring(src)
    local origin = GetEntityCoords(GetPlayerPed(src))
    local color = QBCore.Config.Commands.OOCColor
    for _, target in pairs(F.GetPlayers()) do
        local prefix
        if target == src or distance(origin, GetEntityCoords(GetPlayerPed(target))) < NEARBY_RADIUS then
            prefix = 'OOC | '
        elseif F.HasPermission(target, 'admin') and F.IsOptin(target) then
            prefix = 'Proximity OOC | '
            TriggerEvent('qb-log:server:CreateLog', 'ooc', 'OOC', 'white',
                ('**%s** (CitizenID: %s | ID: %s) **Message:** %s'):format(name, player.PlayerData.citizenid, src, message), false)
        end
        if prefix then
            TriggerClientEvent('chat:addMessage', target, { color = color, multiline = true, args = { prefix .. name, message } })
        end
    end
end)

register('me', 'Show local message', { param('message', 'Message to send') }, false, 'user', function(src, args)
    if not requirePlayer(src) then return end
    local message = messageOf(args, MAX_MESSAGE):gsub('[~<].-[>~]', '')
    if message == '' then return reply(src, 'All arguments must be filled out!', 'error') end
    local ped = GetPlayerPed(src)
    local origin = GetEntityCoords(ped)
    for _, target in ipairs(F.GetPlayers()) do
        local targetPed = GetPlayerPed(target)
        if targetPed == ped or distance(origin, GetEntityCoords(targetPed)) < NEARBY_RADIUS then
            TriggerClientEvent('QBCore:Command:ShowMe3D', target, src, message)
        end
    end
end)
