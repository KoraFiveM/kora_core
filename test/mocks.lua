-- Mocks for smoke-testing qbcore modules under plain lua5.4 (no FiveM, no DB).
-- Installs the FiveM natives the server modules touch, a fake qblib `QB` (with a
-- REAL working resources.serverRegistry, since the resource-stop sweep is under
-- test), and a fake `QB.sql` recording enqueue/enqueueMany calls so persistence
-- tests can assert exact column sets without a database.

local M = {}

M.SOURCE = 1

---@param opts { client?: boolean }|nil pass { client = true } to mock the
---client realm (IsDuplicityVersion() returns false); default is server.
function M.install(opts)
    opts = opts or {}
    local isClient = opts.client == true
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
    local cloneLocalNetPayloads = false

    local function clone(value, seen)
        if type(value) ~= 'table' then return value end
        seen = seen or {}
        if seen[value] then return seen[value] end
        local copy = {}
        seen[value] = copy
        for key, child in pairs(value) do copy[clone(key, seen)] = clone(child, seen) end
        return copy
    end

    _G.source = nil

    function _G.AddEventHandler(name, cb) eventHandlers[name] = eventHandlers[name] or {}; table.insert(eventHandlers[name], cb) end
    function _G.RegisterNetEvent(name, cb) if cb then netHandlers[name] = netHandlers[name] or {}; table.insert(netHandlers[name], cb) end end
    -- RegisterServerEvent: client-fired
    -- server events) use to mark an event name net-safe. Real semantics are just
    -- a security registration -- the actual listening still goes through
    -- AddEventHandler, which is already mocked above -- so this is a no-op here.
    function _G.RegisterServerEvent(_) end
    function _G.TriggerEvent(name, ...)
        for _, fn in ipairs(eventHandlers[name] or {}) do fn(...) end
        for _, fn in ipairs(netHandlers[name] or {}) do
            if cloneLocalNetPayloads then
                local args = { ... }
                for index, value in ipairs(args) do args[index] = clone(value) end
                fn(table.unpack(args))
            else
                fn(...)
            end
        end
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
    local executeCommandCalls = {}     -- recorded ExecuteCommand invocations, e.g. dependencySupervisor's restarts
    function _G.ExecuteCommand(command) table.insert(executeCommandCalls, command) end
    function _G.GetConvar(_, d) return d end
    function _G.GetConvarInt(_, d) return d end
    function _G.vector4(x, y, z, w) return { x = x, y = y, z = z, w = w } end

    -- CancelEvent -- recorder for the 'chatMessage' '/'-suppression handler
    -- (compat/server/qb-core-events.lua). Reset per-install, exposed as a
    -- counter accessor since the native itself takes/returns nothing.
    local cancelEventCount = 0
    function _G.CancelEvent() cancelEventCount = cancelEventCount + 1 end

    -- IsPlayerAceAllowed -- QBCore:CallCommand's permission gate. Controllable
    -- per (source, permission) pair via the returned handle's setAce, default
    -- disallowed (matching a real server where a fresh player has no ACE grants).
    local aceGrants = {}
    function _G.IsPlayerAceAllowed(src, permission)
        return (aceGrants[src] or {})[permission] == true
    end

    -- SetCanAttackFriendly / NetworkSetFriendlyFireOption -- recorders for
    -- QBCore:Client:PvpHasToggled (compat/client/qb-core-events.lua).
    local pvpNativeCalls = {}
    function _G.SetCanAttackFriendly(ped, toggle, arg3)
        table.insert(pvpNativeCalls, { fn = 'SetCanAttackFriendly', ped = ped, toggle = toggle, arg3 = arg3 })
    end
    function _G.NetworkSetFriendlyFireOption(toggle)
        table.insert(pvpNativeCalls, { fn = 'NetworkSetFriendlyFireOption', toggle = toggle })
    end

    -- Realm switch. coreobject.lua's client-only vehicle-extra helpers
    -- (QBCore.Shared.ChangeVehicleExtra/SetDefaultVehicleExtras) are guarded
    -- by `if not IsDuplicityVersion() then`, so this must exist for ANY test
    -- that dofiles coreobject.lua, not just client-realm ones. Only set it when
    -- the caller passed an explicit `opts.client`, OR nothing has defined it
    -- yet -- some test files set `_G.IsDuplicityVersion` themselves BEFORE
    -- calling mocks.install() (see test/smoke/player_updated_client.lua), and
    -- unconditionally overwriting that here would silently flip their realm
    -- back to the server default.
    if opts.client ~= nil or _G.IsDuplicityVersion == nil then
        function _G.IsDuplicityVersion() return not isClient end
    end

    -- Client-only natives touched by compat/client/qb-core.lua and
    -- coreobject.lua's vehicle-extra helpers. A simple, deterministic (not
    -- CFX-accurate) hash is enough here -- tests only need the SAME string to
    -- always produce the SAME hash, and different strings to (almost always)
    -- differ.
    function _G.GetHashKey(str)
        str = tostring(str or '')
        local hash = 0
        for i = 1, #str do
            hash = (hash * 33 + str:byte(i)) % 4294967296
        end
        return hash
    end
    local vehicleExtras = {}   -- [vehicle][extra] = enabled (boolean)
    function _G.DoesExtraExist(_, _) return true end
    function _G.SetVehicleExtra(vehicle, extra, disable)
        vehicleExtras[vehicle] = vehicleExtras[vehicle] or {}
        vehicleExtras[vehicle][extra] = not disable
    end
    function _G.IsVehicleExtraTurnedOn(vehicle, extra)
        return (vehicleExtras[vehicle] or {})[extra] == true
    end
    function _G.PlayerPedId() return 100 end
    function _G.GetEntityModel(_) return 0 end
    function _G.GetPedDrawableVariation(_, _) return 0 end

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
    function _G.GetPlayerRoutingBucket(_) return 0 end
    function _G.SetEntityRoutingBucket(_, _) end

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
        -- Mirrors qblib/local/resources/server.lua: track(resource, id) records
        -- WHICH resource owns WHICH id, untrack(id) drops one id, and the stop
        -- sweep disposes every id a resource owned -- onDispose receives the
        -- ID, not the resource. The old mock took a single argument for both,
        -- which is why it never caught Core.inventory.createUseable calling
        -- track(owner) with the id missing (a nil table index at runtime).
        serverRegistry = function(onDispose)
            local byResource, ownerOf = {}, {}
            return {
                track = function(resource, id)
                    assert(resource ~= nil and id ~= nil, 'serverRegistry.track(resource, id) requires both')
                    local previous = ownerOf[id]
                    if previous and previous ~= resource and byResource[previous] then
                        byResource[previous][id] = nil
                    end
                    byResource[resource] = byResource[resource] or {}
                    byResource[resource][id] = true
                    ownerOf[id] = resource
                end,
                untrack = function(id)
                    local resource = ownerOf[id]
                    if resource and byResource[resource] then byResource[resource][id] = nil end
                    ownerOf[id] = nil
                end,
                owner = function() return GetInvokingResource() or GetCurrentResourceName() end,
                _dispose = function(resource)
                    local owned = byResource[resource]
                    if not owned then return end
                    byResource[resource] = nil
                    for id in pairs(owned) do
                        ownerOf[id] = nil
                        onDispose(id)
                    end
                end,
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
    -- Small local-player cache facade for client compatibility tests. Tests
    -- can drive an edge with setCache(key, value), which mirrors qblib's
    -- onChange(newValue, oldValue) contract without loading another resource.
    local cacheValues = { vehicle = false, seat = false, enteringVehicle = false, enteringSeat = false }
    local cacheListeners = {}
    QB.cache = {
        onChange = function(key, handler)
            cacheListeners[key] = cacheListeners[key] or {}
            table.insert(cacheListeners[key], handler)
        end,
        vehicle = function() return cacheValues.vehicle end,
        seat = function() return cacheValues.seat end,
        enteringVehicle = function() return cacheValues.enteringVehicle end,
        enteringSeat = function() return cacheValues.enteringSeat end,
    }
    -- QB.commands -- a minimal but REAL implementation (previously all no-ops,
    -- so QBCore.Commands.Add/List never actually populated anything under
    -- test). Only tracks what QBCore:CallCommand's tests need: name, help,
    -- permission out of list(), matching QBCore.commands/server.lua's own
    -- {name, help, permission} shape.
    local cmdDefs = {}
    QB.commands = {
        add = function(name, help, args, argsRequired, handler, opts)
            opts = opts or {}
            cmdDefs[name] = { help = help, args = args, argsRequired = argsRequired, handler = handler, permission = opts.permission or 'user' }
        end,
        remove = function(name) cmdDefs[name] = nil end,
        refresh = function() end,
        list = function()
            local out = {}
            for name, def in pairs(cmdDefs) do
                out[#out + 1] = { name = name, help = def.help, permission = def.permission }
            end
            return out
        end,
    }
    QB.status = { apply = function() return true end, remove = function() return true end }
    QB.zones = { sphere = function() return { remove = function() end } end }

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
        executeCommandCalls = executeCommandCalls,
        cancelEventCount = function() return cancelEventCount end,
        setAce = function(src, permission, allowed)
            aceGrants[src] = aceGrants[src] or {}
            aceGrants[src][permission] = allowed
        end,
        pvpNativeCalls = pvpNativeCalls,
        setCache = function(key, value)
            local previous = cacheValues[key]
            if previous == value then return end
            cacheValues[key] = value
            for _, handler in ipairs(cacheListeners[key] or {}) do handler(value, previous) end
        end,
        setCloneLocalNetPayloads = function(value) cloneLocalNetPayloads = value == true end,
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

-- A real (small) JSON decoder. This used to `return {}` unconditionally, which
-- made every test touching the decode path pass vacuously -- including the one
-- that should have caught PlayerData.items coming back from the database with
-- STRING slot keys. A mock that cannot fail is not a test.
--
-- Supports the subset the players table actually stores: objects, arrays,
-- strings (with the standard escapes), numbers, true/false/null. `null`
-- decodes to nil, matching FiveM's json.decode.
function M.simpleDecode(text)
    if type(text) ~= 'string' then return nil end
    local pos = 1

    local function skip()
        pos = text:find('[^ \t\r\n]', pos) or #text + 1
    end

    local parseValue

    local function parseString()
        pos = pos + 1 -- opening quote
        local buf = {}
        while true do
            local c = text:sub(pos, pos)
            if c == '' then error('unterminated string') end
            if c == '"' then pos = pos + 1; break end
            if c == '\\' then
                local esc = text:sub(pos + 1, pos + 1)
                local map = { n = '\n', t = '\t', r = '\r', b = '\b', f = '\f', ['"'] = '"', ['\\'] = '\\', ['/'] = '/' }
                if esc == 'u' then
                    buf[#buf + 1] = utf8.char(tonumber(text:sub(pos + 2, pos + 5), 16) or 63)
                    pos = pos + 6
                else
                    buf[#buf + 1] = map[esc] or esc
                    pos = pos + 2
                end
            else
                buf[#buf + 1] = c
                pos = pos + 1
            end
        end
        return table.concat(buf)
    end

    local function parseObject()
        pos = pos + 1 -- {
        local out = {}
        skip()
        if text:sub(pos, pos) == '}' then pos = pos + 1; return out end
        while true do
            skip()
            local k = parseString()
            skip()
            pos = pos + 1 -- :
            local v = parseValue()
            -- A JSON object always has string keys; that is precisely the shape
            -- the inventory column round-trips through.
            out[k] = v
            skip()
            local c = text:sub(pos, pos)
            pos = pos + 1
            if c == '}' then break end
        end
        return out
    end

    local function parseArray()
        pos = pos + 1 -- [
        local out, n = {}, 0
        skip()
        if text:sub(pos, pos) == ']' then pos = pos + 1; return out end
        while true do
            n = n + 1
            out[n] = parseValue()
            skip()
            local c = text:sub(pos, pos)
            pos = pos + 1
            if c == ']' then break end
        end
        return out
    end

    parseValue = function()
        skip()
        local c = text:sub(pos, pos)
        if c == '{' then return parseObject() end
        if c == '[' then return parseArray() end
        if c == '"' then return parseString() end
        if text:sub(pos, pos + 3) == 'true' then pos = pos + 4; return true end
        if text:sub(pos, pos + 4) == 'false' then pos = pos + 5; return false end
        if text:sub(pos, pos + 3) == 'null' then pos = pos + 4; return nil end
        local numText = text:match('^%-?%d+%.?%d*[eE]?[%+%-]?%d*', pos)
        if numText and numText ~= '' then
            pos = pos + #numText
            return tonumber(numText)
        end
        error('unexpected character at ' .. pos .. ': ' .. c)
    end

    local ok, value = pcall(parseValue)
    if not ok then return nil end
    return value
end

return M
