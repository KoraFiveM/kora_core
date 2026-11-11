local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua')
local handle = mocks.install({ client = true })

dofile('config.lua')
dofile('shared/items.lua'); dofile('shared/jobs.lua'); dofile('shared/gangs.lua')
dofile('shared/vehicles.lua'); dofile('shared/weapons.lua'); dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua'); dofile('modules/registry/client.lua')
dofile('modules/player/shared.lua'); dofile('modules/player/client.lua')
dofile('compat/shared/coreobject.lua')
dofile('compat/client/qb-core.lua')

local replyOnAwait
_G.promise = { new = function()
    local p = { resolved = false }
    function p:resolve(...) self.resolved = true; self.value = (...) end
    return p
end }
Citizen.Await = function(p)
    if replyOnAwait then replyOnAwait() end
    return p.value
end

local sent
local origServerEvent = TriggerServerEvent
TriggerServerEvent = function(name, ...) sent = { name = name, args = table.pack(...) }; return origServerEvent(name, ...) end

h.test('callback form: cb is not forwarded as an argument and receives the reply', function()
    sent, replyOnAwait = nil, nil
    local got
    local r = QBCore.Functions.TriggerCallback('t:cb', function(v) got = v end, 'a', 2)
    h.assertEqual(r, nil)
    h.assertEqual(sent.name, 'QBCore:Server:TriggerCallback')
    h.assertEqual(sent.args[1], 't:cb'); h.assertEqual(sent.args[2], 'a'); h.assertEqual(sent.args[3], 2)
    h.assertEqual(sent.args.n, 3, 'callback must not be forwarded')
    handle.fireEvent('QBCore:Client:TriggerCallback', nil, 't:cb', 'reply')
    h.assertEqual(got, 'reply')
    handle.fireEvent('QBCore:Client:TriggerCallback', nil, 't:cb', 'again')
    h.assertEqual(got, 'reply', 'a duplicate reply must not re-invoke')
end)

local function inThread(fn)
    local co = coroutine.create(fn)
    local ok, err = coroutine.resume(co)
    if not ok then error(err, 0) end
end

h.test('await form: returns the reply and forwards every argument', function() inThread(function()
    sent = nil
    replyOnAwait = function() handle.fireEvent('QBCore:Client:TriggerCallback', nil, 't:await', 42, 'x') end
    local r = QBCore.Functions.TriggerCallback('t:await', 'arg1', { k = 1 })
    h.assertEqual(r, 42)
    h.assertEqual(sent.args.n, 3)
    h.assertEqual(sent.args[2], 'arg1'); h.assertEqual(sent.args[3].k, 1)
end) end)

h.test('await form with no extra args', function() inThread(function()
    replyOnAwait = function() handle.fireEvent('QBCore:Client:TriggerCallback', nil, 't:none', true) end
    h.assertEqual(QBCore.Functions.TriggerCallback('t:none'), true)
    h.assertEqual(sent.args.n, 1)
end) end)

h.test('await outside a thread errors clearly and sends nothing', function()
    sent = nil
    local ok, err = pcall(QBCore.Functions.TriggerCallback, 't:main')
    h.assertFalse(ok)
    h.assertTrue(tostring(err):find('must be called from a thread', 1, true) ~= nil)
    h.assertEqual(sent, nil)
end)

h.test('stock parity: a leading nil is the await form and is forwarded', function() inThread(function()
    replyOnAwait = function() handle.fireEvent('QBCore:Client:TriggerCallback', nil, 't:nil', 'ok') end
    h.assertEqual(QBCore.Functions.TriggerCallback('t:nil', nil, 'x'), 'ok')
    h.assertEqual(sent.args.n, 3)
    h.assertEqual(sent.args[2], nil); h.assertEqual(sent.args[3], 'x')
end) end)

h.test('await times out with nil when no reply arrives, and a late reply is ignored', function() inThread(function()
    replyOnAwait = function() handle.drainTimeouts() end
    h.assertEqual(QBCore.Functions.TriggerCallback('t:slow'), nil)
    h.assertEqual(QBCore.ServerCallbacks['t:slow'], nil)
    replyOnAwait = nil
    handle.fireEvent('QBCore:Client:TriggerCallback', nil, 't:slow', 'late')
end) end)

h.test('concurrent same-name calls are answered in order, each with its own entry', function()
    local got = {}
    QBCore.Functions.TriggerCallback('t:multi', function(v) got[#got + 1] = 'a' .. tostring(v) end)
    QBCore.Functions.TriggerCallback('t:multi', function(v) got[#got + 1] = 'b' .. tostring(v) end)
    handle.fireEvent('QBCore:Client:TriggerCallback', nil, 't:multi', 1)
    handle.fireEvent('QBCore:Client:TriggerCallback', nil, 't:multi', 2)
    handle.fireEvent('QBCore:Client:TriggerCallback', nil, 't:multi', 3)
    h.assertEqual(table.concat(got, ','), 'a1,b2')
end)

h.test('a raw function stored in ServerCallbacks still receives the reply', function()
    local got
    QBCore.ServerCallbacks['t:raw'] = function(v) got = v end
    handle.fireEvent('QBCore:Client:TriggerCallback', nil, 't:raw', 9)
    h.assertEqual(got, 9)
end)

h.report('client_trigger_callback')
