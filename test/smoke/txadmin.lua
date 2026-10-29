local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua')
local realPrint = print

local function fixture(active)
    local handle = mocks.install()
    local state = { online = { [1] = 'Admin', [2] = 'Player' }, lookups = {},
        grants = {}, changes = {}, warnings = {}, commands = {}, invoking = nil }
    function GetConvar(_, default) return active == false and default or 'true' end
    function GetPlayerName(src) return state.online[src] end
    function GetPlayerIdentifiers(src) return { 'license:test-' .. src, 'fivem:' .. src } end
    function GetPlayers()
        local players = {}
        for src in pairs(state.online) do players[#players + 1] = tostring(src) end
        table.sort(players)
        return players
    end
    function GetInvokingResource() return state.invoking end
    function CreateThread() error('permission checks must not create a thread') end
    function SetTimeout() error('permission checks must not create a timer') end
    function print(message) state.warnings[#state.warnings + 1] = message end

    local baseAce = IsPlayerAceAllowed
    function IsPlayerAceAllowed(src, permission)
        return baseAce(src, permission) or (state.grants[src] == true
            and (permission == 'group.admin' or permission == 'qbcore.admin'))
    end
    function ExecuteCommand(command)
        state.commands[#state.commands + 1] = command
        local operation, src = command:match('^(%w+)_principal player%.(%d+) qbcore%.txadmin$')
        h.assertTrue(operation == 'add' or operation == 'remove', 'only owned player links may change')
        state.grants[tonumber(src)] = operation == 'add' or nil
    end
    local trigger = TriggerEvent
    function TriggerEvent(name, ...)
        if name == 'qbcore:server:txAdminPermissionChanged' then
            state.changes[#state.changes + 1] = (...)
        end
        trigger(name, ...)
    end

    TX_SERVER_MODE = active ~= false
    TX_LUACOMHOST, TX_LUACOMTOKEN = 'localhost:40121', 'test-private-token'
    json = { decode = function()
        if state.badJson then error('bad json') end
        return state.response
    end }
    function PerformHttpRequest(url, callback, method, body, headers)
        state.lookups[#state.lookups + 1] = {
            url = url, callback = callback, method = method, body = body, headers = headers,
        }
    end
    exports = function(name, fn)
        h.assertEqual(name, 'qbcoreCheckFullAdmin')
        state.bridge = fn
    end
    dofile('integrations/txadmin.lua')
    exports = { monitor = { qbcoreCheckFullAdmin = function(_, src, callback)
        local previous = state.invoking
        state.invoking = 'kora_core'
        local result = state.bridge(src, callback)
        state.invoking = previous
        return result
    end } }
    dofile('modules/permissions/server.lua')
    dofile('modules/permissions/txadmin.lua')

    state.fire = function(name, src, ...)
        state.invoking = name == 'txAdmin:events:adminsUpdated' and 'monitor' or nil
        handle.fireEvent(name, src, ...)
        state.invoking = nil
    end
    state.respond = function(index, response, status)
        state.response = response
        state.lookups[index].callback(status or 200, 'mock-response')
    end
    state.manualAdmin = function(src) handle.setAce(src, 'group.admin', true) end
    return state
end

local function fullAdmin(master)
    return { name = 'Staff', isMaster = master == true, permissions = { 'all_permissions' } }
end

local function limitedAdmin()
    return { name = 'Staff', permissions = { 'players.kick', 'menu.vehicle' } }
end

h.test('full admins receive group.admin through the existing permission gateway', function()
    local s = fixture()
    s.fire('playerJoining', 1)
    h.assertFalse(IsPlayerAceAllowed(1, 'group.admin'), 'a pending lookup grants nothing')
    local request = s.lookups[1]
    h.assertEqual(request.url, 'http://localhost:40121/auth/self')
    h.assertEqual(request.method, 'GET')
    h.assertEqual(request.headers['X-TxAdmin-Identifiers'], 'license:test-1,fivem:1')
    h.assertEqual(request.headers['X-TxAdmin-Token'], 'test-private-token')
    s.respond(1, fullAdmin())
    h.assertTrue(IsPlayerAceAllowed(1, 'group.admin'))
    h.assertEqual(Core.permissions.getPermission(1), 'admin')
    h.assertFalse(Core.permissions.hasPermission(1, 'god'), 'full txAdmin access does not grant god')
    h.assertEqual(#s.changes, 1, 'the menu is notified')
end)

h.test('master accounts qualify while limited admins and ordinary players do not', function()
    local s = fixture()
    s.fire('playerJoining', 1)
    s.respond(1, fullAdmin(true))
    h.assertTrue(s.grants[1])
    s.fire('playerJoining', 2)
    s.respond(2, limitedAdmin())
    h.assertFalse(s.grants[2])
    s.fire('playerJoining', 2)
    s.respond(3, { logout = true, reason = 'nui_admin_not_found' })
    h.assertFalse(s.grants[2])
    h.assertEqual(#s.warnings, 0, 'ordinary players do not produce authentication warnings')
end)

h.test('promotion, demotion and deletion apply from adminsUpdated', function()
    local s = fixture()
    s.fire('playerJoining', 1)
    s.respond(1, limitedAdmin())
    s.fire('txAdmin:events:adminsUpdated', 0, { 1 })
    s.respond(2, fullAdmin())
    h.assertTrue(s.grants[1])
    s.fire('txAdmin:events:adminsUpdated', 0, { 1 })
    h.assertFalse(s.grants[1], 'demotion revokes before the replacement lookup finishes')
    s.respond(3, limitedAdmin())
    h.assertFalse(s.grants[1])
    s.fire('txAdmin:events:adminsUpdated', 0, { 1 })
    s.respond(4, fullAdmin())
    s.fire('txAdmin:events:adminsUpdated', 0, {})
    h.assertFalse(s.grants[1], 'deleted admins need not appear in the new list')
    h.assertEqual(#s.lookups, 4)
end)

h.test('revocation preserves manual grants', function()
    local s = fixture()
    s.manualAdmin(1)
    s.fire('playerJoining', 1)
    s.respond(1, fullAdmin())
    s.fire('txAdmin:events:adminsUpdated', 0, {})
    h.assertFalse(s.grants[1])
    h.assertTrue(IsPlayerAceAllowed(1, 'group.admin'))
    h.assertEqual(Core.permissions.getPermission(1), 'admin')
end)

h.test('permission updates invalidate older unfinished lookups', function()
    local s = fixture()
    s.fire('playerJoining', 1)
    s.fire('txAdmin:events:adminsUpdated', 0, { 1 })
    s.respond(2, limitedAdmin())
    s.respond(1, fullAdmin())
    h.assertFalse(s.grants[1], 'a late full-access response cannot undo a demotion')
    s.fire('playerJoining', 1)
    s.fire('txAdmin:events:adminsUpdated', 0, {})
    s.respond(3, fullAdmin())
    h.assertFalse(s.grants[1], 'deletion invalidates checks for an ungranted admin too')
end)

h.test('disconnects and reused player IDs cannot inherit old responses or grants', function()
    local s = fixture()
    s.fire('playerJoining', 1)
    s.fire('playerDropped', 1)
    s.online[1] = 'Replacement'
    s.fire('playerJoining', 1)
    s.respond(2, limitedAdmin())
    s.respond(1, fullAdmin())
    h.assertFalse(s.grants[1])
    s.fire('playerJoining', 1)
    s.respond(3, fullAdmin())
    s.fire('playerDropped', 1)
    h.assertFalse(s.grants[1], 'disconnect removes the owned ACE')
    s.fire('playerJoining', 1)
    s.respond(4, limitedAdmin())
    h.assertFalse(s.grants[1])
end)

h.test('one startup reconciliation checks already connected players', function()
    local s = fixture()
    s.fire('onResourceStart', 0, 'other')
    h.assertEqual(#s.lookups, 0)
    s.fire('onResourceStart', 0, 'kora_core')
    h.assertEqual(#s.lookups, 2)
    s.respond(1, fullAdmin())
    s.respond(2, limitedAdmin())
    h.assertTrue(s.grants[1])
    h.assertFalse(s.grants[2])
end)

for _, resource in ipairs({ 'kora_core', 'monitor' }) do
    h.test(resource .. ' stop removes grants and invalidates pending responses', function()
        local s = fixture()
        s.fire('playerJoining', 1)
        s.respond(1, fullAdmin())
        s.fire('playerJoining', 2)
        s.fire('onResourceStop', 0, resource)
        h.assertFalse(s.grants[1])
        s.respond(2, fullAdmin())
        h.assertFalse(s.grants[2])
        s.fire('playerJoining', 1)
        h.assertEqual(#s.lookups, 2, 'stopped resources cannot start new lookups')
    end)
end

h.test('missing bridges fail closed with a diagnostic without changing manual access', function()
    local s = fixture()
    s.manualAdmin(1)
    exports.monitor.qbcoreCheckFullAdmin = function() error('missing export') end
    s.fire('playerJoining', 1)
    s.fire('playerJoining', 2)
    h.assertEqual(#s.warnings, 1, 'repeated missing-export warnings are suppressed')
    h.assertTrue(IsPlayerAceAllowed(1, 'group.admin'))
    h.assertFalse(s.grants[2])
end)

h.test('HTTP failures and malformed responses cannot grant admin', function()
    local responses = { true, {}, { name = 'Staff', permissions = 'all_permissions' },
        { name = '', permissions = { 'all_permissions' } },
        { name = 'Staff', error = 'reject', permissions = { 'all_permissions' } },
        { logout = true, permissions = { 'all_permissions' } } }
    for _, response in ipairs(responses) do
        local s = fixture()
        s.fire('playerJoining', 1)
        s.respond(1, response)
        h.assertFalse(s.grants[1])
        h.assertEqual(#s.warnings, 1)
    end
    local s = fixture()
    s.fire('playerJoining', 1)
    s.respond(1, fullAdmin(), 500)
    h.assertFalse(s.grants[1])
    s.fire('playerJoining', 1)
    s.badJson = true
    s.respond(2, fullAdmin())
    h.assertFalse(s.grants[1])
end)

h.test('duplicate IDs and repeated callbacks do not produce duplicate grants', function()
    local s = fixture()
    s.fire('txAdmin:events:adminsUpdated', 0, { 1, '1', 1, 0, 'invalid', math.huge, 0/0 })
    h.assertEqual(#s.lookups, 1)
    s.respond(1, fullAdmin())
    s.respond(1, fullAdmin())
    h.assertEqual(#s.commands, 1)
    h.assertEqual(#s.changes, 1)
end)

h.test('untrusted callers cannot trigger the bridge or change automatic permissions', function()
    local s = fixture()
    s.fire('playerJoining', 1)
    s.respond(1, fullAdmin())
    s.invoking = 'other'
    TriggerEvent('txAdmin:events:adminsUpdated', {})
    h.assertTrue(s.grants[1])
    h.assertEqual(s.bridge(1, function() error('untrusted callbacks must not run') end), false)
    h.assertEqual(#s.lookups, 1)
    s.invoking = 'kora_core'
    local allowed
    s.bridge(0, function(value) allowed = value end)
    h.assertEqual(allowed, false)
    h.assertEqual(#s.lookups, 1)
end)

h.test('removed intercom tokens deny automatic access without exposing the token', function()
    local s = fixture()
    TX_LUACOMTOKEN = 'removed'
    s.fire('playerJoining', 1)
    h.assertEqual(#s.lookups, 0)
    h.assertFalse(s.grants[1])
    h.assertEqual(#s.warnings, 1)
end)

h.test('the monitor helper never calls a function reference from a stopped qbcore VM', function()
    local s = fixture()
    s.invoking = 'kora_core'
    s.bridge(1, function() error('the stopped resource callback must not run') end)
    s.fire('onResourceStop', 0, 'kora_core')
    s.respond(1, fullAdmin())
end)

h.test('servers without txAdmin keep their existing permission behavior', function()
    local s = fixture(false)
    s.manualAdmin(1)
    s.fire('playerJoining', 1)
    s.fire('onResourceStart', 0, 'kora_core')
    h.assertEqual(s.bridge, nil)
    h.assertEqual(#s.lookups, 0)
    h.assertEqual(Core.permissions.getPermission(1), 'admin')
end)

print = realPrint
h.report('txadmin')
