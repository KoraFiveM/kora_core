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

local registered = {}
Kora.callback = {
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

_G.CreateThread = function(fn) fn() end

local function invoke(name, src, ...)
    local handler = registered[name]
    assert(handler, 'callback ' .. tostring(name) .. ' was not registered')
    local results = table.pack(pcall(handler, src, ...))
    assert(results[1], results[2])
    return table.unpack(results, 2, results.n)
end

h.test('a legacy handler that calls its responder synchronously replies with every value it sent', function()
    QBCore.Functions.CreateCallback('test:sync', function(source, cb, multiplier)
        cb(source * multiplier, 'ok')
    end)
    local a, b = invoke('test:sync', 3, 10)
    h.assertEqual(a, 30, 'the first responder value must reach the caller')
    h.assertEqual(b, 'ok', 'a second responder value must also reach the caller')
end)

h.test('calling the responder twice only honours the first call', function()
    QBCore.Functions.CreateCallback('test:double-respond', function(source, cb)
        cb('first')
        cb('second')
    end)
    local a = invoke('test:double-respond', 1)
    h.assertEqual(a, 'first', 'a second cb(...) call must be a no-op, not overwrite the reply')
end)

h.test('a legacy handler that returns without ever calling its responder resolves empty instead of erroring', function()
    QBCore.Functions.CreateCallback('test:never-responds', function(source, cb)
        if source == 0 then return end
    end)
    local a = invoke('test:never-responds', 0)
    h.assertEqual(a, nil, 'no responder call must resolve to nothing once the timeout fires, not hang or error')
end)

h.report('callback_compat')
