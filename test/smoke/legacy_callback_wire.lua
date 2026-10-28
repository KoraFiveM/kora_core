-- Pins the RAW NET EVENT wire protocol some legacy scripts speak directly
-- instead of going through QBCore.Functions.TriggerCallback/TriggerClientCallback:
--   client->server: QBCore:Server:TriggerCallback / QBCore:Client:TriggerCallback
--   server->client: QBCore:Client:TriggerClientCallback / QBCore:Server:TriggerClientCallback
--
-- The design is compat-local handler registries (legacyCallbacks on the
-- server, legacyClientCallbacks on the client) that BOTH the kora_lib bridge and
-- the raw wire dispatch through -- one registration (CreateCallback /
-- CreateClientCallback), reachable over either transport, never invoked twice
-- for one incoming request. This file loads the server compat first and
-- exercises the server-side leg (raw request in, raw reply out, garbage
-- input, re-registration), THEN loads the client compat on top of the same
-- QBCore global and exercises the client-side leg the same way -- see the
-- "client half" section below for why that load order is safe.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua')
local handle = mocks.install()

dofile('config.lua')
dofile('shared/items.lua'); dofile('shared/jobs.lua'); dofile('shared/gangs.lua')
dofile('shared/vehicles.lua'); dofile('shared/weapons.lua'); dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua'); dofile('modules/registry/server.lua')
dofile('modules/player/shared.lua')
dofile('modules/replication/server.lua')
dofile('modules/persistence/server.lua')
dofile('modules/player/server.lua')
dofile('modules/money/server.lua')
dofile('modules/jobs/server.lua')
dofile('modules/metadata/server.lua')
dofile('modules/inventory/shared.lua'); dofile('modules/inventory/server.lua')
dofile('modules/inventory/gateway.lua')
dofile('modules/multichar/server.lua')
dofile('modules/permissions/server.lua')
dofile('modules/commands/server.lua')
dofile('modules/logging/server.lua')
dofile('compat/shared/coreobject.lua')

-- QB.callback fake that actually stores handlers (mocks.lua's is a total
-- no-op) -- same approach as test/smoke/callback_compat.lua.
local registered = {}
QB.callback = {
    register = function(name, handler) registered[name] = handler end,
    trigger = function() return nil end,
}

_G.promise = {
    new = function()
        local p = { __resolved = false }
        function p:resolve(v) if not self.__resolved then self.__resolved = true; self.__value = v end end
        function p:reject(v) if not self.__resolved then self.__resolved = true; self.__value = v end end
        return p
    end,
}

dofile('compat/server/qb-core.lua')

-- Same reasoning as callback_compat.lua: run the adapter's timeout thread
-- synchronously instead of queueing it, scoped to after every module has
-- already loaded.
_G.CreateThread = function(fn) fn() end

local function invokeViaQblib(name, src, ...)
    local handler = registered[name]
    assert(handler, 'qblib callback ' .. tostring(name) .. ' was not registered')
    local results = table.pack(pcall(handler, src, ...))
    assert(results[1], results[2])
    return table.unpack(results, 2, results.n)
end

-- --- server half -------------------------------------------------------------

h.test('raw QBCore:Server:TriggerCallback reaches a CreateCallback handler and replies over QBCore:Client:TriggerCallback', function()
    QBCore.Functions.CreateCallback('test:x', function(source, cb, arg) cb(arg * 2) end)

    handle.fireEvent('QBCore:Server:TriggerCallback', 7, 'test:x', 21)

    local ev = handle.lastClient('QBCore:Client:TriggerCallback')
    h.assertTrue(ev ~= nil, 'a QBCore:Client:TriggerCallback reply must be sent')
    h.assertEqual(ev.target, 7, 'the reply must target the requesting source')
    h.assertEqual(ev.args[1], 'test:x', 'the reply must carry the callback name')
    h.assertEqual(ev.args[2], 42, 'the reply must carry the responder value')
end)

h.test('the same CreateCallback handler is also reachable through the qblib bridge (one registration, two transports)', function()
    local a = invokeViaQblib('test:x', 3, 10)
    h.assertEqual(a, 20, 'the qblib transport must dispatch to the SAME registered handler')
end)

h.test('a non-string callback name on the raw wire does not error', function()
    h.assertTrue(pcall(function()
        handle.fireEvent('QBCore:Server:TriggerCallback', 7, 12345)
    end), 'garbage input must be ignored, not crash the resource')
end)

h.test('an unknown callback name on the raw wire does not error', function()
    h.assertTrue(pcall(function()
        handle.fireEvent('QBCore:Server:TriggerCallback', 7, 'test:does-not-exist')
    end), 'a name with no registered handler must be a silent no-op')
end)

h.test('a handler that errors is caught -- the resource does not crash', function()
    QBCore.Functions.CreateCallback('test:boom', function() error('kaboom') end)
    h.assertTrue(pcall(function()
        handle.fireEvent('QBCore:Server:TriggerCallback', 7, 'test:boom')
    end), 'a raw-wire handler error must be pcall-guarded')
end)

h.test('re-registering CreateCallback for the same name (a resource restart) updates BOTH transports', function()
    QBCore.Functions.CreateCallback('test:restart', function(source, cb) cb('first') end)
    QBCore.Functions.CreateCallback('test:restart', function(source, cb) cb('second') end)

    local viaQblib = invokeViaQblib('test:restart', 1)
    h.assertEqual(viaQblib, 'second', 'the qblib transport must use the NEWEST handler')

    handle.fireEvent('QBCore:Server:TriggerCallback', 1, 'test:restart')
    local ev = handle.lastClient('QBCore:Client:TriggerCallback')
    h.assertEqual(ev.args[2], 'second', 'the raw-wire transport must also use the NEWEST handler')
end)

h.test('server->client raw wire: TriggerClientCallback stores the pending callback and sends the request', function()
    QBCore.Functions.TriggerClientCallback('test:svc', 9, function() end, 'ping')
    h.assertTrue(QBCore.ClientCallbacks['test:svc9'] ~= nil, 'ClientCallbacks must be keyed by name .. source')

    local ev = handle.lastClient('QBCore:Client:TriggerClientCallback')
    h.assertTrue(ev ~= nil, 'the request must go out over the raw wire')
    h.assertEqual(ev.target, 9)
    h.assertEqual(ev.args[1], 'test:svc')
    h.assertEqual(ev.args[2], 'ping')
end)

h.test('server->client raw wire: the QBCore:Server:TriggerClientCallback reply resolves the pending callback and clears it', function()
    local seen
    QBCore.Functions.TriggerClientCallback('test:svc2', 9, function(v) seen = v end, 'ping')
    handle.fireEvent('QBCore:Server:TriggerClientCallback', 9, 'test:svc2', 'pong')
    h.assertEqual(seen, 'pong', 'the stored callback must be invoked with the reply value')
    h.assertTrue(QBCore.ClientCallbacks['test:svc29'] == nil, 'the entry must be cleared after use')
end)

-- --- client half ---------------------------------------------------------
-- Loading compat/client/qb-core.lua into the SAME process, on top of the
-- already-loaded QBCore global, is safe here even though both realm files
-- write into QBCore.Functions: every server-side test above already ran
-- (and QBCore.Functions.CreateCallback/TriggerCallback are captured as
-- upvalues nowhere else needed past this point), and the raw net events each
-- realm registers use disjoint event names, so nothing gets overwritten out
-- from under an earlier assertion. From here on, QBCore.Functions.CreateCallback
-- is an ALIAS for CreateClientCallback (client/qb-core.lua's own doing) and
-- QBCore.Functions.TriggerCallback is the client (name, cb, ...) signature --
-- exactly the objects the client-side tests below need.
dofile('compat/client/qb-core.lua')

h.test('raw QBCore:Client:TriggerClientCallback reaches a CreateClientCallback handler and replies over QBCore:Server:TriggerClientCallback', function()
    QBCore.Functions.CreateClientCallback('test:y', function(cb, arg) cb(arg + 1) end)

    handle.fireEvent('QBCore:Client:TriggerClientCallback', nil, 'test:y', 9)

    local found
    for _, ev in ipairs(handle.serverEvents) do
        if ev.name == 'QBCore:Server:TriggerClientCallback' then found = ev end
    end
    h.assertTrue(found ~= nil, 'a QBCore:Server:TriggerClientCallback reply must be sent')
    h.assertEqual(found.args[1], 'test:y')
    h.assertEqual(found.args[2], 10)
end)

h.test('client->server: TriggerCallback populates QBCore.ServerCallbacks and the raw-wire reply invokes it', function()
    local lastSeen
    QBCore.Functions.TriggerCallback('test:z', function(v) lastSeen = v end, 5)
    h.assertTrue(QBCore.ServerCallbacks['test:z'] ~= nil,
        'TriggerCallback must store into ServerCallbacks until the server replies')

    local request
    for i = #handle.serverEvents, 1, -1 do
        if handle.serverEvents[i].name == 'QBCore:Server:TriggerCallback' then
            request = handle.serverEvents[i]
            break
        end
    end
    h.assertTrue(request ~= nil, 'TriggerCallback must use the legacy server wire')
    h.assertEqual(request.args[1], 'test:z')
    h.assertEqual(request.args[2], 5)

    -- Simulate the server's raw-wire reply arriving directly.
    handle.fireEvent('QBCore:Client:TriggerCallback', nil, 'test:z', 99)
    h.assertEqual(lastSeen, 99, 'the raw-wire reply must invoke the stored callback with its value')
    h.assertTrue(QBCore.ServerCallbacks['test:z'] == nil, 'the entry must be cleared after use')
end)

h.test('re-registering CreateClientCallback for the same name (a resource restart) updates BOTH transports', function()
    local calls = {}
    QBCore.Functions.CreateClientCallback('test:restart-client', function(cb) table.insert(calls, 'first'); cb('first') end)
    QBCore.Functions.CreateClientCallback('test:restart-client', function(cb) table.insert(calls, 'second'); cb('second') end)

    handle.fireEvent('QBCore:Client:TriggerClientCallback', nil, 'test:restart-client')

    local found
    for _, ev in ipairs(handle.serverEvents) do
        if ev.name == 'QBCore:Server:TriggerClientCallback' and ev.args[1] == 'test:restart-client' then found = ev end
    end
    h.assertTrue(found ~= nil)
    h.assertEqual(found.args[2], 'second', 'the raw-wire transport must use the NEWEST handler')
    h.assertEqual(calls[#calls], 'second', 'only the newest handler body must have run for this call')
end)

h.test('a non-string callback name on the client raw wire does not error', function()
    h.assertTrue(pcall(function()
        handle.fireEvent('QBCore:Client:TriggerClientCallback', nil, 12345)
    end), 'garbage input must be ignored, not crash the resource')
    h.assertTrue(pcall(function()
        handle.fireEvent('QBCore:Client:TriggerCallback', nil, 12345)
    end), 'garbage input must be ignored, not crash the resource')
end)

h.report('legacy_callback_wire')
