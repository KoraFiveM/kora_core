if Config.compat.defaultCommands == false then return end

local F = QBCore.Functions

local MAX_REASON = 200
local MAX_MESSAGE = 255
local NEARBY_RADIUS = 20.0
local DV_RADIUS = 5.0

local function reply(src, message, kind)
    if src == 0 then
        print(('[kora_core:commands] %s'):format(message))
        return
    end
    TriggerClientEvent('QBCore:Notify', src, message, kind or 'primary')
end

local function audit(src, name, data)
    data = data or {}
    data.command = name
    local ok, err = pcall(Core.logging.logEvent, 'admin', src, data)
    if not ok then Kora.logging.warn('commands.audit_log_failed', 'Command audit log failed', { command = name, error = tostring(err) }) end
end

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
        reply(src, Kora.lang('Commands.player_required'), 'error')
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
        Kora.logging.warn('commands.already_registered', 'Command is already registered by another resource; keeping that one', { command = name })
        return
    end
    QBCore.Commands.Add(name, help, params, argsRequired, function(src, args, raw)
        args = type(args) == 'table' and args or {}
        if permission ~= 'user' and src ~= 0 and not F.HasPermission(src, permission) then
            audit(src, name, { args = loggable(args), denied = true })
            return reply(src, Kora.lang('Commands.permission_denied'), 'error')
        end
        if permission ~= 'user' then audit(src, name, { args = loggable(args) }) end
        return handler(src, args, raw)
    end, permission)
end

local function param(name, help) return { name = name, help = help } end

register('tp', Kora.lang('CommandHelp.tp'), {
    param('id/x', Kora.lang('CommandParams.id_of_player_or_x_position')), param('y', Kora.lang('CommandParams.y_position')), param('z', Kora.lang('CommandParams.z_position')),
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
                reply(src, Kora.lang('Commands.player_offline'), 'error')
            end
        else
            local location = QBCore.Shared.Locations and QBCore.Shared.Locations[first]
            if location then
                TriggerClientEvent('QBCore:Command:TeleportToCoords', src, location.x, location.y, location.z, location.w)
            else
                reply(src, Kora.lang('Commands.location_missing'), 'error')
            end
        end
    elseif first and args[2] and args[3] then
        local function coordinate(value) return finite((str(value) or ''):gsub(',', '')) end
        local x, y, z = coordinate(args[1]), coordinate(args[2]), coordinate(args[3])
        local heading = args[4] and coordinate(args[4]) or false
        if x and y and z then
            TriggerClientEvent('QBCore:Command:TeleportToCoords', src, x + 0.0, y + 0.0, z + 0.0, heading and heading + 0.0 or false)
        else
            reply(src, Kora.lang('Commands.incorrect_format'), 'error')
        end
    else
        reply(src, Kora.lang('Commands.coordinates_required'), 'error')
    end
end)

register('tpm', Kora.lang('CommandHelp.tpm'), {}, false, 'admin', function(src)
    if not requirePlayer(src) then return end
    TriggerClientEvent('QBCore:Command:GoToMarker', src)
end)

register('togglepvp', Kora.lang('CommandHelp.togglepvp'), {}, false, 'admin', function(src)
    QBCore.Config.Server.PVP = not QBCore.Config.Server.PVP
    TriggerClientEvent('QBCore:Client:PvpHasToggled', -1, QBCore.Config.Server.PVP)
    reply(src, QBCore.Config.Server.PVP and Kora.lang('Commands.pvp_enabled') or Kora.lang('Commands.pvp_disabled'), 'success')
end)

AddEventHandler('kora_core:server:playerLoaded', function(src)
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

local function permissionCommand(name, help, apply, resultKey)
    register(name, help, {
        param('id', Kora.lang('CommandParams.id_of_player')), param('permission', Kora.lang('CommandParams.permission_level')),
    }, true, 'god', function(src, args)
        local id = resolveTarget(args[1])
        if not id then return reply(src, Kora.lang('Commands.player_offline'), 'error') end
        local permission = configuredPermission(args[2])
        if not permission then
            return reply(src, Kora.lang('Commands.permission_choices', table.concat(QBCore.Config.Server.Permissions, ', ')), 'error')
        end
        audit(src, name, { target = id, permission = permission })
        apply(id, permission)
        QBCore.Commands.Refresh(id)
        reply(src, Kora.lang(resultKey, permission, id), 'success')
    end)
end

permissionCommand('addpermission', Kora.lang('CommandHelp.addpermission'),
    function(id, permission) F.AddPermission(id, permission) end, 'Commands.permission_granted')
permissionCommand('removepermission', Kora.lang('CommandHelp.removepermission'),
    function(id, permission) F.RemovePermission(id, permission) end, 'Commands.permission_removed')

register('openserver', Kora.lang('CommandHelp.openserver'), {}, false, 'admin', function(src)
    if not QBCore.Config.Server.Closed then return reply(src, Kora.lang('Commands.already_open'), 'error') end
    if src ~= 0 and not F.HasPermission(src, 'admin') then
        return F.Kick(src, Kora.lang('Commands.kick_permission_denied'))
    end
    QBCore.Config.Server.Closed = false
    reply(src, Kora.lang('Commands.opened'), 'success')
end)

register('closeserver', Kora.lang('CommandHelp.closeserver'), {
    param('reason', Kora.lang('CommandParams.reason_for_closing_optional')),
}, false, 'admin', function(src, args)
    if QBCore.Config.Server.Closed then return reply(src, Kora.lang('Commands.already_closed'), 'error') end
    if src ~= 0 and not F.HasPermission(src, 'admin') then
        return F.Kick(src, Kora.lang('Commands.kick_permission_denied'))
    end
    local parts = {}
    for i = 1, math.min(#args, 32) do parts[#parts + 1] = str(args[i], 64) or '' end
    local reason = #parts > 0 and table.concat(parts, ' '):sub(1, MAX_REASON) or Kora.lang('Commands.no_reason')
    QBCore.Config.Server.Closed = true
    QBCore.Config.Server.ClosedReason = reason
    for playerSrc in pairs(QBCore.Players) do
        if not F.HasPermission(playerSrc, QBCore.Config.Server.WhitelistPermission) then
            F.Kick(playerSrc, reason)
        end
    end
    reply(src, Kora.lang('Commands.closed'), 'success')
end)

AddEventHandler('playerConnecting', function(_, setKickReason, deferrals)
    if not QBCore.Config.Server.Closed then return end
    if F.HasPermission(source, QBCore.Config.Server.WhitelistPermission) then return end
    local reason = QBCore.Config.Server.ClosedReason or Kora.lang('Commands.server_closed')
    if setKickReason then setKickReason(reason) end
    deferrals.defer()
    deferrals.done(reason)
end)

local function playerVehicle(ped)
    local vehicle = GetVehiclePedIsIn(ped, false)
    return vehicle ~= 0 and vehicle or nil
end

register('car', Kora.lang('CommandHelp.car'), { param('model', Kora.lang('CommandParams.model_name_of_the_vehicle')) }, true, 'admin', function(src, args)
    if not requirePlayer(src) then return end
    local model = str(args[1], 64)
    if not model or not model:match('^[%w_]+$') or #model > 32 then
        return reply(src, Kora.lang('Commands.incorrect_format'), 'error')
    end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local coords = GetEntityCoords(ped)
    local previous = playerVehicle(ped)
    local vehicle = F.SpawnVehicle(src, model, { x = coords.x, y = coords.y, z = coords.z, w = GetEntityHeading(ped) }, true)
    if not vehicle then return reply(src, Kora.lang('Notify.vehicle_spawn_failed'), 'error') end
    if previous and previous ~= vehicle then DeleteEntity(previous) end

    local plate = GetVehicleNumberPlateText(vehicle)
    if plate and GetResourceState('kora_vehiclekeys') == 'started' then
        local ok, err = pcall(function() return exports.kora_vehiclekeys:giveKeys(src, plate) end)
        if not ok then Kora.logging.warn('commands.car_grant_keys_failed', '/car could not grant keys', { error = tostring(err) }) end
    end
    audit(src, 'car', { model = model, plate = plate })
end)

register('dv', Kora.lang('CommandHelp.dv'), {}, false, 'admin', function(src)
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
        reply(src, Kora.lang('Commands.deleted_entities', removed), 'success')
    end)
end

deleteAll('dvall', Kora.lang('CommandHelp.dvall'), function() return GetAllVehicles() end)
deleteAll('dvp', Kora.lang('CommandHelp.dvp'), function() return GetAllPeds() end, function(ped) return IsPedAPlayer and IsPedAPlayer(ped) end)
deleteAll('dvo', Kora.lang('CommandHelp.dvo'), function() return GetAllObjects() end)

local function moneyArgs(src, args)
    local id = resolveTarget(args[1])
    if not id then reply(src, Kora.lang('Commands.player_offline'), 'error'); return end
    local account = moneyType(args[2])
    if not account then
        reply(src, Kora.lang('Commands.account_choices', table.concat(Config.money.types, ', ')), 'error')
        return
    end
    local amount = finite(args[3])
    if not amount then reply(src, Kora.lang('Commands.incorrect_format'), 'error'); return end
    return id, account, amount
end

local MONEY_PARAMS = {
    param('id', Kora.lang('CommandParams.player_id')), param('moneytype', Kora.lang('CommandParams.type_of_money_cash_bank_crypto')), param('amount', Kora.lang('CommandParams.amount_of_money')),
}

register('givemoney', Kora.lang('CommandHelp.givemoney'), MONEY_PARAMS, true, 'admin', function(src, args)
    local id, account, amount = moneyArgs(src, args)
    if not id then return end
    local ok, err = Core.money.addMoney(id, account, amount, 'Admin give money', true)
    audit(src, 'givemoney', { target = id, account = account, amount = amount, ok = ok and true or false })
    if not ok then reply(src, Kora.lang('Commands.give_money_failed', tostring(err)), 'error') end
end)

register('setmoney', Kora.lang('CommandHelp.setmoney'), MONEY_PARAMS, true, 'admin', function(src, args)
    local id, account, amount = moneyArgs(src, args)
    if not id then return end
    local ok, err = Core.money.setMoney(id, account, amount, 'Admin set money')
    audit(src, 'setmoney', { target = id, account = account, amount = amount, ok = ok and true or false })
    if not ok then reply(src, Kora.lang('Commands.set_money_failed', tostring(err)), 'error') end
end)

register('job', Kora.lang('CommandHelp.job'), {}, false, 'user', function(src)
    local player = src ~= 0 and F.GetPlayer(src)
    if not player then return end
    local job = player.PlayerData.job
    local onDuty = Kora.lang(job.onduty and 'Commands.yes' or 'Commands.no')
    reply(src, Kora.lang('Commands.job_status', tostring(job.label), tostring(job.grade.name), onDuty))
end)

register('gang', Kora.lang('CommandHelp.gang'), {}, false, 'user', function(src)
    local player = src ~= 0 and F.GetPlayer(src)
    if not player then return end
    local gang = player.PlayerData.gang
    reply(src, Kora.lang('Commands.gang_status', tostring(gang.label), tostring(gang.grade.name)))
end)

local function roleCommand(name, help, kind, apply)
    register(name, help, {
        param('id', Kora.lang('CommandParams.player_id')), param(kind, kind == 'job' and Kora.lang('CommandParams.job_name') or Kora.lang('CommandParams.gang_name')),
        param('grade', kind == 'job' and Kora.lang('CommandParams.job_grade') or Kora.lang('CommandParams.gang_grade')),
    }, true, 'admin', function(src, args)
        local id = resolveTarget(args[1])
        if not id then return reply(src, Kora.lang('Commands.player_offline'), 'error') end
        local role = str(args[2], 64)
        role = role and role:lower()
        local grade = toInteger(args[3])
        if not role or not role:match('^[%w_%-]+$') then
            return reply(src, Kora.lang('Commands.incorrect_format'), 'error')
        end
        if not grade or grade < 0 then
            return reply(src, Kora.lang('Commands.grade_invalid'), 'error')
        end
        local ok, err = apply(id, role, Core.compat.fromLegacyGradeLevel(grade))
        audit(src, name, { target = id, [kind] = role, grade = grade, ok = ok and true or false })
        if not ok then
            local what = kind == 'job' and Kora.lang('Commands.set_role_job') or Kora.lang('Commands.set_role_gang')
            reply(src, Kora.lang('Commands.set_role_failed', what, tostring(err)), 'error')
        end
    end)
end

roleCommand('setjob', Kora.lang('CommandHelp.setjob'), 'job', Core.jobs.setJob)
roleCommand('setgang', Kora.lang('CommandHelp.setgang'), 'gang', Core.jobs.setGang)

local function messageOf(args, max)
    local parts = {}
    for i = 1, math.min(#args, 64) do parts[#parts + 1] = str(args[i], 128) or '' end
    return table.concat(parts, ' '):sub(1, max)
end

register('ooc', Kora.lang('CommandHelp.ooc'), {}, false, 'user', function(src, args)
    if not requirePlayer(src) then return end
    local player = F.GetPlayer(src)
    if not player then return end
    local message = messageOf(args, MAX_MESSAGE)
    if message == '' then return reply(src, Kora.lang('Notify.arguments_required'), 'error') end
    local name = GetPlayerName(src) or tostring(src)
    local origin = GetEntityCoords(GetPlayerPed(src))
    local color = QBCore.Config.Commands.OOCColor
    for _, target in pairs(F.GetPlayers()) do
        local prefix
        if target == src or distance(origin, GetEntityCoords(GetPlayerPed(target))) < NEARBY_RADIUS then
            prefix = Kora.lang('Commands.ooc_prefix')
        elseif F.HasPermission(target, 'admin') and F.IsOptin(target) then
            prefix = Kora.lang('Commands.ooc_proximity_prefix')
            TriggerEvent('qb-log:server:CreateLog', 'ooc', 'OOC', 'white',
                ('**%s** (CitizenID: %s | ID: %s) **Message:** %s'):format(name, player.PlayerData.citizenid, src, message), false)
        end
        if prefix then
            TriggerClientEvent('chat:addMessage', target, { color = color, multiline = true, args = { prefix .. name, message } })
        end
    end
end)

register('me', Kora.lang('CommandHelp.me'), { param('message', Kora.lang('CommandParams.message_to_send')) }, false, 'user', function(src, args)
    if not requirePlayer(src) then return end
    local message = messageOf(args, MAX_MESSAGE):gsub('[~<].-[>~]', '')
    if message == '' then return reply(src, Kora.lang('Notify.arguments_required'), 'error') end
    local ped = GetPlayerPed(src)
    local origin = GetEntityCoords(ped)
    for _, target in ipairs(F.GetPlayers()) do
        local targetPed = GetPlayerPed(target)
        if targetPed == ped or distance(origin, GetEntityCoords(targetPed)) < NEARBY_RADIUS then
            TriggerClientEvent('QBCore:Command:ShowMe3D', target, src, message)
        end
    end
end)
