-- Mocks for smoke-testing qbcore modules under plain lua5.4 (no FiveM, no DB).
-- Installs the FiveM natives the server modules touch, a fake qblib `QB` (with a
-- REAL working resources.serverRegistry, since the resource-stop sweep is under
-- test), and a fake `QB.sql` recording enqueue/enqueueMany calls so persistence
-- tests can assert exact column sets without a database.

local M = {}

M.SOURCE = 1

function M.install()
    -- --- FiveM natives ---
    local eventHandlers = {}
    local netHandlers = {}
    local clientEvents = {}     -- recorded TriggerClientEvent
    local serverEvents = {}     -- recorded TriggerServerEvent
    local playerStates = {}     -- source -> replicated Player() state bag values
    local stateWrites = {}      -- ordered state bag writes for lifecycle tests
    local lifecycleTrace = {}   -- interleaved client events and state writes
    local timeouts = {}         -- pending SetTimeout callbacks
    local threads = {}

    _G.source = nil

    function _G.AddEventHandler(name, cb) eventHandlers[name] = eventHandlers[name] or {}; table.insert(eventHandlers[name], cb) end
    function _G.RegisterNetEvent(name, cb) if cb then netHandlers[name] = netHandlers[name] or {}; table.insert(netHandlers[name], cb) end end
    function _G.TriggerEvent(name, ...)
        for _, fn in ipairs(eventHandlers[name] or {}) do fn(...) end
        for _, fn in ipairs(netHandlers[name] or {}) do fn(...) end
    end
    function _G.TriggerClientEvent(name, target, ...)
        table.insert(clientEvents, { name = name, target = target, args = { ... } })
        table.insert(lifecycleTrace, { kind = 'client', name = name, target = target })
    end
    function _G.TriggerServerEvent(name, ...) table.insert(serverEvents, { name = name, args = { ... } }) end

    function _G.CreateThread(fn) table.insert(threads, coroutine.create(fn)) end
    _G.Citizen = { CreateThread = _G.CreateThread, Await = function(p) return p and p.__value end, Wait = function() end }
    function _G.Wait(_) end
    function _G.SetTimeout(_, fn) table.insert(timeouts, fn) end

    local clock = 0
    function _G.GetGameTimer() clock = clock + 16; return clock end
    function _G.GetInvokingResource() return nil end
    function _G.GetCurrentResourceName() return 'qbcore' end
    local resourceStates = { qbinventory = 'missing' }
    function _G.GetResourceState(name) return resourceStates[name] or 'missing' end
    function _G.GetConvar(_, d) return d end
    function _G.GetConvarInt(_, d) return d end
    function _G.vector4(x, y, z, w) return { x = x, y = y, z = z, w = w } end

    -- Server-side Player(source).state, including the colon form used by the
    -- lifecycle module. This is deliberately small but records replication so
    -- state-bag ordering can be smoke-tested without a CFX runtime.
    function _G.Player(src)
        playerStates[src] = playerStates[src] or {}
        local state = playerStates[src]
        state.set = function(_, key, value, replicated)
            state[key] = value
            table.insert(stateWrites, { source = src, key = key, value = value, replicated = replicated })
            table.insert(lifecycleTrace, { kind = 'state', source = src, key = key, value = value, replicated = replicated })
        end
        return { state = state }
    end

    -- Ped/position natives for the persistence position sampler.
    function _G.GetPlayerPed(_) return 100 end
    function _G.GetEntityCoords(_) return { x = 0.0, y = 0.0, z = 0.0 } end
    function _G.GetEntityHeading(_) return 0.0 end

    -- json (FiveM provides a global json with encode/decode). Use a stable
    -- key-sorted encoder so the persistence "byte-identical" gate is testable.
    _G.json = {
        encode = function(v) return M.stableEncode(v) end,
        decode = function(s) return M.simpleDecode(s) end,
    }

    _G.os = os
    _G.math = math

    -- --- fake qblib QB ---
    local QB = {}

    -- resources.serverRegistry: a REAL implementation (the sweep is under test).
    QB.resources = {
        serverRegistry = function(onDispose)
            local tracked = {}
            return {
                track = function(owner) tracked[owner] = true end,
                untrack = function(owner) tracked[owner] = nil end,
                owner = function() return GetInvokingResource() or GetCurrentResourceName() end,
                _dispose = function(owner) if tracked[owner] then onDispose(owner); tracked[owner] = nil end end,
            }
        end,
    }

    QB.callback = { register = function() end, trigger = function() return nil end }
    QB.events = { register = function() end, trigger = function() end, push = function() end }
    QB.notify = { send = function() end }
    QB.stream = setmetatable({}, { __index = function() return function() end end })
    QB.drawing = { text3d = function() end }
    QB.world = { getClosestEntity = function() end }
    QB.progressbar = { start = function() end }

    -- fake QB.sql recording writes. query/single results are canned per exact
    -- SQL string (sqlResponses.query[sql] / .single[sql]) -- unset means the
    -- same nil/{} default every test relied on before this existed, so this
    -- is purely additive for a test that needs a specific row back.
    local sqlCalls = { enqueue = {}, enqueueMany = {}, query = {}, single = {}, execute = {} }
    local sqlResponses = { query = {}, single = {} }
    QB.sql = {
        ready = function() return true end,
        enqueue = function(t, k, row, opts) table.insert(sqlCalls.enqueue, { table = t, key = k, row = row, opts = opts }) end,
        enqueueMany = function(t, k, rows, opts) table.insert(sqlCalls.enqueueMany, { table = t, key = k, rows = rows, opts = opts }) end,
        query = function(sql, params)
            table.insert(sqlCalls.query, { sql = sql, params = params })
            return sqlResponses.query[sql] or {}
        end,
        single = function(sql, params)
            table.insert(sqlCalls.single, { sql = sql, params = params })
            return sqlResponses.single[sql]
        end,
        execute = function(sql, params) table.insert(sqlCalls.execute, { sql = sql, params = params }); return { affectedRows = 1 } end,
        flush = function() return true end,
    }

    _G.QB = QB
    _G.exports = setmetatable({}, { __index = function() return setmetatable({}, { __index = function() return function() end end }) end })

    -- Build the Core table (as build/initiate.lua would).
    _G.Core = setmetatable({}, { __index = function(self, k) local m = {}; rawset(self, k, m); return m end })
    _G.CoreInternal = {}

    return {
        eventHandlers = eventHandlers,
        clientEvents = clientEvents,
        serverEvents = serverEvents,
        playerStates = playerStates,
        stateWrites = stateWrites,
        lifecycleTrace = lifecycleTrace,
        sqlCalls = sqlCalls,
        sqlResponses = sqlResponses,
        QB = QB,
        resourceStates = resourceStates,
        -- Drain pending SetTimeout callbacks (end-of-frame flush in replication).
        drainTimeouts = function()
            local pending = timeouts
            timeouts = {}
            for _, fn in ipairs(pending) do fn() end
        end,
        -- Resume every CreateThread coroutine once.
        step = function()
            for _, co in ipairs(threads) do coroutine.resume(co) end
        end,
        fireEvent = function(name, src, ...)
            local prev = _G.source
            _G.source = src
            _G.TriggerEvent(name, ...)
            _G.source = prev
        end,
        lastClient = function(name)
            for i = #clientEvents, 1, -1 do if clientEvents[i].name == name then return clientEvents[i] end end
        end,
    }
end

-- A deterministic, key-sorted JSON-ish encoder so persistence's byte-identical
-- change gate is testable (real FiveM json.encode is not order-stable, but the
-- gate only needs SOME stable encoding to detect "unchanged").
function M.stableEncode(v)
    local t = type(v)
    if t == 'nil' then return 'null'
    elseif t == 'number' then return tostring(v)
    elseif t == 'boolean' then return v and 'true' or 'false'
    elseif t == 'string' then return ('%q'):format(v)
    elseif t == 'table' then
        -- Array?
        local n = #v
        local isArray = n > 0
        for k in pairs(v) do if type(k) ~= 'number' then isArray = false break end end
        local parts = {}
        if isArray then
            for i = 1, n do parts[i] = M.stableEncode(v[i]) end
            return '[' .. table.concat(parts, ',') .. ']'
        else
            local keys = {}
            for k in pairs(v) do keys[#keys + 1] = tostring(k) end
            table.sort(keys)
            for _, k in ipairs(keys) do parts[#parts + 1] = ('%q:'):format(k) .. M.stableEncode(v[k]) end
            return '{' .. table.concat(parts, ',') .. '}'
        end
    end
    return 'null'
end

function M.simpleDecode() return {} end

return M
