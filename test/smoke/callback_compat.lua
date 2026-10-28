-- Pins the legacy CreateCallback responder-bridge fix. Real qb-core hands the
-- handler a RESPONDER function as its second argument -- function(source, cb,
-- ...) ... cb(result) end -- and expects the handler to CALL it, not return a
-- value. kora_lib's QB.callback.register instead ships back whatever the
-- registered function RETURNS. Before this fix, `cb` was silently bound to
-- the callback's first data argument (or nil), producing exactly the
-- qb-banking symptom: "attempt to call a nil value (local 'cb')", and the
-- bank UI never opening.
--
-- The shared test/mocks.lua QB.callback.register is a total no-op (doesn't
-- even store the handler), so it can't exercise this bridge. This file
-- installs its own QB.callback fake that captures the registered handler and
-- invokes it exactly the way kora_lib's real transport does --
-- table.pack(pcall(handler, src, ...)) -- see kora_lib/local/callback/server.lua.
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
QB.callback = {
    register = function(name, handler) registered[name] = handler end,
    trigger = function() return nil end,
}

-- Minimal real promise: :resolve/:reject settle it once, later calls no-op.
_G.promise = {
    new = function()
        local p = { __resolved = false }
        function p:resolve(v) if not self.__resolved then self.__resolved = true; self.__value = v end end
        function p:reject(v) if not self.__resolved then self.__resolved = true; self.__value = v end end
        return p
    end,
}

dofile('compat/server/qb-core.lua')

-- The adapter's own CreateThread(function() Wait(timeout); respond() end)
-- always runs BEFORE the Citizen.Await(p) that follows it -- see
-- compat/server/qb-core.lua's F.CreateCallback. Run it synchronously here
-- (Wait is a no-op mock either way) instead of queueing a coroutine into the
-- SHARED mocks.lua thread list: that list also holds every background loop
-- other already-dofiled modules may have started (needs/paycheck/etc), and
-- since Wait never actually yields in this plain-Lua harness, resuming a
-- `while true do ... Wait(x) end`-shaped one of those would spin forever.
-- Overriding only here, after every module has already loaded, keeps this
-- change scoped to the callback invocations this file makes.
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
    -- Mirrors qb-banking/server.lua's real early-out shape: `if not Player
    -- then return end` before ever calling cb.
    QBCore.Functions.CreateCallback('test:never-responds', function(source, cb)
        if source == 0 then return end
    end)
    local a = invoke('test:never-responds', 0)
    h.assertEqual(a, nil, 'no responder call must resolve to nothing once the timeout fires, not hang or error')
end)

h.report('callback_compat')
