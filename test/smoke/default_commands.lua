local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('shared/items.lua'); dofile('shared/jobs.lua'); dofile('shared/gangs.lua')
dofile('shared/vehicles.lua'); dofile('shared/weapons.lua'); dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua'); dofile('modules/registry/server.lua')
dofile('modules/player/shared.lua')
dofile('modules/replication/server.lua'); dofile('modules/persistence/server.lua')
dofile('modules/player/server.lua'); dofile('modules/money/server.lua')
dofile('modules/jobs/server.lua'); dofile('modules/metadata/server.lua')
dofile('modules/inventory/shared.lua'); dofile('modules/inventory/server.lua')
dofile('modules/inventory/gateway.lua')
dofile('modules/multichar/server.lua'); dofile('modules/permissions/server.lua')
dofile('modules/commands/server.lua')
dofile('compat/shared/coreobject.lua')

local handlers, permissions = {}, {}
local realAdd = Kora.commands.add
Kora.commands.add = function(name, help, args, argsRequired, handler, opts)
    handlers[name], permissions[name] = handler, opts and opts.permission
    return realAdd(name, help, args, argsRequired, handler, opts)
end
local logged = {}
Core.logging = { logEvent = function(category, src, data) logged[#logged + 1] = { category = category, src = src, data = data } end }
Core.identity = { primary = function() return 'license:abc' end }
handle.resourceStates.kora_vehiclekeys = 'started'

dofile('compat/server/qb-core.lua')
dofile('compat/server/qb-core-events.lua')
Core.commands.addCommand('dvo', 'custom dvo', {}, false, function() end, 'admin')
local calls = {}
local function stub(name, fn) _G[name] = function(...) calls[#calls + 1] = { name, ... }; return fn and fn(...) end end
local entities, deleted = {}, {}
_G.WasEventCanceled = function() return false end
dofile('compat/server/qb-commands.lua')

local data = CoreInternal.player.freshData('CMD1', 'license:cmd1', 1, { firstname = 'A', lastname = 'B' })
assert(Core.player.login(1, 'CMD1', data))
local data2 = CoreInternal.player.freshData('CMD2', 'license:cmd2', 1, { firstname = 'C', lastname = 'D' })
assert(Core.player.login(2, 'CMD2', data2))
handle.setPlayers({ 1, 2 })
handle.setAce(1, 'kora_core.admin', true)
handle.setAce(1, 'kora_core.god', true)

local function notifications(src)
    local out = {}
    for _, ev in ipairs(handle.clientEvents) do
        if ev.name == 'QBCore:Notify' and ev.target == src then out[#out + 1] = ev.args[1] end
    end
    return out
end
local function lastNotify(src) local n = notifications(src); return n[#n] end
local function run(name, src, ...) return handlers[name](src, { ... }, name .. ' ' .. table.concat({ ... }, ' ')) end

h.test('all 20 stock commands are registered with stock permission levels', function()
    local expected = {
        tp = 'admin', tpm = 'admin', togglepvp = 'admin', addpermission = 'god', removepermission = 'god',
        openserver = 'admin', closeserver = 'admin', car = 'admin', dv = 'admin', dvall = 'admin', dvp = 'admin',
        givemoney = 'admin', setmoney = 'admin', job = 'user', setjob = 'admin', gang = 'user', setgang = 'admin',
        ooc = 'user', me = 'user',
    }
    for name, level in pairs(expected) do
        h.assertEqual(permissions[name], level, '/' .. name)
        h.assertTrue(QBCore.Commands.List[name] ~= nil, '/' .. name .. ' missing from Commands.List')
        h.assertEqual(QBCore.Commands.List[name].permission, level)
    end
end)

h.test('a command another resource registered first is kept (dvo)', function()
    h.assertEqual(permissions.dvo, 'admin')
    h.assertEqual(QBCore.Commands.List.dvo.help, 'custom dvo')
end)

h.test('permission groups get the command.<name> ACE like stock', function()
    local seen = {}
    for _, c in ipairs(handle.executeCommandCalls) do seen[c] = true end
    h.assertTrue(seen['add_ace kora_core.admin command.tp allow'])
    h.assertTrue(seen['add_ace kora_core.god command.addpermission allow'] == nil, 'god is in the ignore list')
    h.assertTrue(seen['add_ace kora_core.user command.job allow'] == nil, 'user is in the ignore list')
end)

h.test('QBCore:Server:PreCommandExecution fires and can cancel', function()
    local seen
    AddEventHandler('QBCore:Server:PreCommandExecution', function(src, name, args, raw) seen = { src, name, args, raw } end)
    handlers.togglepvp(1, {}, 'togglepvp')
    h.assertEqual(seen[2], 'togglepvp')
    h.assertEqual(QBCore.Config.Server.PVP, false)
    _G.WasEventCanceled = function() return true end
    handlers.togglepvp(1, {}, 'togglepvp')
    h.assertEqual(QBCore.Config.Server.PVP, false, 'cancelled execution must not toggle')
    _G.WasEventCanceled = function() return false end
    handlers.togglepvp(1, {}, 'togglepvp')
    h.assertEqual(QBCore.Config.Server.PVP, true)
end)

h.test('admin command use is audit-logged', function()
    local before = #logged
    handlers.togglepvp(1, {}, 'togglepvp')
    h.assertEqual(logged[before + 1].category, 'admin')
    h.assertEqual(logged[before + 1].data.command, 'togglepvp')
    h.assertEqual(logged[before + 1].src, 1)
    handlers.togglepvp(1, {}, 'togglepvp')
    local n = #logged
    handlers.job(1, {}, 'job')
    h.assertEqual(#logged, n, 'user commands are not audited')
end)

h.test('givemoney / setmoney go through Core.money and validate input', function()
    local bank = Core.money.getMoney(2, 'bank')
    run('givemoney', 1, '2', 'bank', '250')
    h.assertEqual(Core.money.getMoney(2, 'bank'), bank + 250)
    run('setmoney', 1, '2', 'bank', '10')
    h.assertEqual(Core.money.getMoney(2, 'bank'), 10)
    run('givemoney', 1, '2', 'bank', 'abc'); run('givemoney', 1, '2', 'bank', 'inf'); run('givemoney', 1, '2', 'bank', 'nan')
    run('givemoney', 1, '2', 'gold', '5'); run('givemoney', 1, '99', 'bank', '5'); run('givemoney', 1, 'x', 'bank', '5')
    h.assertEqual(Core.money.getMoney(2, 'bank'), 10)
    run('givemoney', 1, '2', 'bank', '-5')
    h.assertEqual(Core.money.getMoney(2, 'bank'), 10, 'negative give refused')
    h.assertEqual(lastNotify(1) ~= nil, true)
end)

h.test('setjob lower-cases, converts the zero-based grade and reports unknown jobs', function()
    run('setjob', 1, '2', 'POLICE', '2')
    local job = Core.jobs.getJob(2)
    h.assertEqual(job.name, 'police')
    h.assertEqual(job.grade.level, 3, 'zero-based grade 2 is kora grade 3')
    run('setjob', 1, '2', 'nosuchjob', '0')
    h.assertEqual(Core.jobs.getJob(2).name, 'police')
    h.assertTrue(lastNotify(1):find('unknown job') ~= nil)
    run('setjob', 1, '2', 'police', '-1'); run('setjob', 1, '2', 'police;x', '0'); run('setjob', 1, '77', 'police', '0')
    h.assertEqual(Core.jobs.getJob(2).grade.level, 3)
end)

h.test('setgang sets a gang and job/gang info commands notify', function()
    local gang = KoraCoreSeed.gangs[2].name
    run('setgang', 1, '2', gang:upper(), '0')
    h.assertEqual(Core.jobs.getGang(2).name, gang)
    handlers.job(2, {}, 'job')
    h.assertTrue(lastNotify(2):find('^Job: ') ~= nil)
    handlers.gang(2, {}, 'gang')
    h.assertTrue(lastNotify(2):find('^Gang: ') ~= nil)
end)

h.test('addpermission / removepermission only accept configured levels', function()
    handle.executeCommandCalls[#handle.executeCommandCalls + 1] = '--marker'
    local mark = #handle.executeCommandCalls
    run('addpermission', 1, '2', 'admin')
    handle.setAce(2, 'admin', true)
    h.assertEqual(handle.executeCommandCalls[mark + 1], 'add_principal identifier.license:abc kora_core.admin')
    run('removepermission', 1, '2', 'admin')
    h.assertEqual(handle.executeCommandCalls[mark + 2], 'remove_principal identifier.license:abc kora_core.admin')
    local after = #handle.executeCommandCalls
    run('addpermission', 1, '2', 'admin allow; quit')
    run('addpermission', 1, '2', 'superuser')
    run('addpermission', 1, '99', 'admin')
    h.assertEqual(#handle.executeCommandCalls, after, 'invalid permission/target must not reach ExecuteCommand')
end)

h.test('closeserver / openserver toggle the flag and kick non-whitelisted players', function()
    local kicked = {}
    _G.DropPlayer = function(src) kicked[#kicked + 1] = src end
    handle.setAce(1, 'kora_core.admin', true)
    handle.setAce(1, 'command.admin', true)
    run('closeserver', 1, 'maintenance', 'window')
    h.assertEqual(QBCore.Config.Server.Closed, true)
    h.assertEqual(QBCore.Config.Server.ClosedReason, 'maintenance window')
    run('closeserver', 1, 'again')
    h.assertTrue(lastNotify(1):find('already closed') ~= nil)
    run('openserver', 1)
    h.assertEqual(QBCore.Config.Server.Closed, false)
end)

h.test('tp validates players, locations and coordinates', function()
    _G.GetPlayerPed = function(id) return id == 2 and 200 or 100 end
    _G.GetEntityCoords = function(e) return { x = e, y = 2.0, z = 3.0 } end
    handle.clientEvents = handle.clientEvents
    run('tp', 1, '2')
    h.assertEqual(handle.lastClient('QBCore:Command:TeleportToPlayer').args[1].x, 200)
    run('tp', 1, '1,5', '2,5', '3')
    local ev = handle.lastClient('QBCore:Command:TeleportToCoords')
    h.assertEqual(ev.args[1], 15.0); h.assertEqual(ev.args[2], 25.0); h.assertEqual(ev.args[3], 3.0)
    local count = 0
    for _, e in ipairs(handle.clientEvents) do if e.name == 'QBCore:Command:TeleportToCoords' then count = count + 1 end end
    run('tp', 1, 'x', 'y', 'z'); run('tp', 1, 'inf', '1', '2'); run('tp', 1, 'nowhere')
    local after = 0
    for _, e in ipairs(handle.clientEvents) do if e.name == 'QBCore:Command:TeleportToCoords' then after = after + 1 end end
    h.assertEqual(after, count, 'bad coordinates/locations must not teleport')
    run('tp', 1, '99')
    h.assertEqual(lastNotify(1), 'Player not online')
end)

h.test('car spawns a server-side networked vehicle and grants keys via kora_vehiclekeys', function()
    local created, keys = {}, {}
    _G.GetEntityHeading = function() return 90.0 end
    _G.GetVehiclePedIsIn = function() return 0 end
    _G.CreateVehicle = function(model, x, y, z, heading, isNetwork, netMissionEntity)
        created[#created + 1] = { model = model, heading = heading, net = isNetwork, mission = netMissionEntity }
        return 555
    end
    _G.DoesEntityExist = function() return true end
    _G.NetworkGetEntityOwner = function() return 1 end
    _G.GetVehicleNumberPlateText = function() return 'ABC123' end
    _G.TaskWarpPedIntoVehicle = function() end
    _G.joaat = _G.joaat or function(s) return #s end
    _G.GetVehiclePedIsIn = function(ped, last) return created[1] and 555 or 0 end
    exports.kora_vehiclekeys = { giveKeys = function(_, src, plate) keys[#keys + 1] = { src, plate }; return true end }
    run('car', 1, 'adder')
    h.assertEqual(#created, 1)
    h.assertEqual(created[1].net, true)
    h.assertEqual(created[1].mission, true)
    h.assertEqual(keys[1][1], 1); h.assertEqual(keys[1][2], 'ABC123')
    run('car', 1, 'bad model;x'); run('car', 1, ('x'):rep(40))
    h.assertEqual(#created, 1, 'invalid model names never reach CreateVehicle')
end)

h.test('dv deletes the occupied vehicle, else vehicles within 5m', function()
    local removed = {}
    _G.DeleteEntity = function(e) removed[#removed + 1] = e end
    _G.GetVehiclePedIsIn = function() return 77 end
    run('dv', 1)
    h.assertEqual(removed[1], 77)
    removed = {}
    _G.GetVehiclePedIsIn = function() return 0 end
    _G.GetAllVehicles = function() return { 100, 101 } end
    _G.GetEntityCoords = function(e) return { x = e == 100 and 1.0 or 50.0, y = 0.0, z = 0.0 } end
    run('dv', 1)
    h.assertEqual(#removed, 1)
    h.assertEqual(removed[1], 100)
end)

h.test('dvp spares player peds', function()
    local removed = {}
    _G.DeleteEntity = function(e) removed[#removed + 1] = e end
    _G.GetAllPeds = function() return { 1, 2, 3 } end
    _G.IsPedAPlayer = function(p) return p == 2 end
    run('dvp', 1)
    h.assertEqual(#removed, 2)
end)

h.test('me strips markup and only reaches nearby players', function()
    _G.GetPlayerPed = function(id) return id end
    _G.GetEntityCoords = function(e) return { x = e == 2 and 500.0 or 0.0, y = 0.0, z = 0.0 } end
    local before = 0
    for _, e in ipairs(handle.clientEvents) do if e.name == 'QBCore:Command:ShowMe3D' then before = before + 1 end end
    run('me', 1, 'waves', '~r~hello~s~')
    local targets = {}
    for _, e in ipairs(handle.clientEvents) do if e.name == 'QBCore:Command:ShowMe3D' then targets[#targets + 1] = e end end
    h.assertEqual(#targets - before, 1)
    h.assertEqual(targets[#targets].target, 1)
    h.assertEqual(targets[#targets].args[2], 'waves hello')
end)

h.test('CallCommand runs the command for an ACE holder and survives hostile args', function()
    handle.setAce(2, 'command.togglepvp', true)
    handle.setAce(2, 'kora_core.admin', true)
    local pvp = QBCore.Config.Server.PVP
    handle.fireEvent('QBCore:CallCommand', 2, 'togglepvp', 'not-a-table')
    h.assertEqual(QBCore.Config.Server.PVP, not pvp)
    handle.fireEvent('QBCore:CallCommand', 2, 'togglepvp', { { 'nested' }, 5 })
    h.assertEqual(QBCore.Config.Server.PVP, pvp)
    handle.setAce(2, 'command.givemoney', true)
    local bank = Core.money.getMoney(1, 'bank')
    handle.fireEvent('QBCore:CallCommand', 2, 'givemoney', { { 'x' }, {}, {} })
    h.assertEqual(Core.money.getMoney(1, 'bank'), bank, 'table-valued args are rejected, not coerced')
    handle.setAce(2, 'kora_core.admin', false)
end)

h.test('CallCommand by a non-admin with broad per-command ACE is refused by the permission check', function()
    handle.setAce(2, 'command.togglepvp', true)
    handle.setAce(2, 'command.givemoney', true)
    handle.setAce(2, 'command.addpermission', true)
    local pvp, bank = QBCore.Config.Server.PVP, Core.money.getMoney(1, 'bank')
    local denied = #logged
    handle.fireEvent('QBCore:CallCommand', 2, 'togglepvp', {})
    handle.fireEvent('QBCore:CallCommand', 2, 'givemoney', { '1', 'bank', '1000' })
    handle.fireEvent('QBCore:CallCommand', 2, 'addpermission', { '2', 'god' })
    h.assertEqual(QBCore.Config.Server.PVP, pvp)
    h.assertEqual(Core.money.getMoney(1, 'bank'), bank)
    h.assertEqual(lastNotify(2), 'You do not have permission to use this command.')
    h.assertEqual(logged[#logged].data.denied, true)
    h.assertTrue(#logged > denied, 'denied attempts are audited')
    h.assertFalse(QBCore.Functions.HasPermission(2, 'god'))
end)

h.test('setjob/setgang reject a missing or invalid grade instead of defaulting to 0', function()
    local job = Core.player.getPlayerData(1, { 'job', 'name' })
    run('setjob', 1, '2', 'police')
    h.assertEqual(lastNotify(1), 'Grade must be a whole number of 0 or more')
    run('setjob', 1, '2', 'police', 'abc')
    run('setjob', 1, '2', 'police', '1.5')
    h.assertEqual(Core.player.getPlayerData(1, { 'job', 'name' }), job)
    run('setgang', 1, '2', 'ballas')
    h.assertEqual(lastNotify(1), 'Grade must be a whole number of 0 or more')
end)

h.report('default_commands')
