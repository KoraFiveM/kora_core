local M = {}

M.SOURCE = 1

---@param opts { client?: boolean }|nil pass { client = true } to mock the
---client realm (IsDuplicityVersion() returns false); default is server.
function M.install(opts)
    opts = opts or {}
    local isClient = opts.client == true
    local eventHandlers = {}
    local netHandlers = {}
    local clientEvents = {}
    local serverEvents = {}
    local playerStates = {}
    local stateWrites = {}
    local lifecycleTrace = {}
    local timeouts = {}
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
    _G.GlobalState = {}
    local players = {}
    function _G.GetPlayers() return players end

    function _G.AddEventHandler(name, cb) eventHandlers[name] = eventHandlers[name] or {}; table.insert(eventHandlers[name], cb) end
    function _G.RegisterNetEvent(name, cb) if cb then netHandlers[name] = netHandlers[name] or {}; table.insert(netHandlers[name], cb) end end
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
    function _G.GetCurrentResourceName() return 'kora_core' end
    local resourceStates = { kora_inventory = 'missing' }
    function _G.GetResourceState(name) return resourceStates[name] or 'missing' end
    local executeCommandCalls = {}
    function _G.ExecuteCommand(command) table.insert(executeCommandCalls, command) end
    function _G.GetConvar(_, d) return d end
    function _G.GetConvarInt(_, d) return d end
    function _G.vector4(x, y, z, w) return { x = x, y = y, z = z, w = w } end

    local cancelEventCount = 0
    function _G.CancelEvent() cancelEventCount = cancelEventCount + 1 end

    local aceGrants = {}
    function _G.IsPlayerAceAllowed(src, permission)
        return (aceGrants[src] or {})[permission] == true
    end

    local pvpNativeCalls = {}
    function _G.SetCanAttackFriendly(ped, toggle, arg3)
        table.insert(pvpNativeCalls, { fn = 'SetCanAttackFriendly', ped = ped, toggle = toggle, arg3 = arg3 })
    end
    function _G.NetworkSetFriendlyFireOption(toggle)
        table.insert(pvpNativeCalls, { fn = 'NetworkSetFriendlyFireOption', toggle = toggle })
    end

    if opts.client ~= nil or _G.IsDuplicityVersion == nil then
        function _G.IsDuplicityVersion() return not isClient end
    end

    function _G.GetHashKey(str)
        str = tostring(str or '')
        local hash = 0
        for i = 1, #str do
            hash = (hash * 33 + str:byte(i)) % 4294967296
        end
        return hash
    end
    _G.joaat = _G.GetHashKey
    local vehicleExtras = {}
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

    function _G.GetPlayerPed(_) return 100 end
    function _G.GetEntityCoords(_) return { x = 0.0, y = 0.0, z = 0.0 } end
    function _G.GetEntityHeading(_) return 0.0 end
    function _G.GetPlayerRoutingBucket(_) return 0 end
    function _G.SetEntityRoutingBucket(_, _) end

    _G.json = {
        encode = function(v) return M.stableEncode(v) end,
        decode = function(s) return M.simpleDecode(s) end,
    }

    _G.os = os
    _G.math = math

    local Kora = {}
    Kora.util = {
        fnv1a = function(value) return ('%08x'):format(#value) end,
        isFiniteNumber = function(value)
            return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
        end,
        isInteger = function(value) return Kora.util.isFiniteNumber(value) and value % 1 == 0 end,
        isCallable = function(value)
            if type(value) == 'function' then return true end
            if type(value) ~= 'table' then return false end
            if type(rawget(value, '__cfx_functionReference')) == 'string' then return true end
            local mt = getmetatable(value)
            return mt ~= nil and type(mt.__call) == 'function'
        end,
        trim = function(value) return type(value) == 'string' and value:match('^%s*(.-)%s*$') or value end,
    }
    Kora.compat = {
        provideExport = function(identity, name, fn)
            AddEventHandler(('__cfx_export_%s_%s'):format(identity, name), function(setCallback)
                setCallback(fn)
            end)
        end,
    }

    Kora.resources = {
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

    Kora.callback = { register = function() end, trigger = function() return nil end }
    Kora.events = { register = function() end, trigger = function() end, push = function() end }
    Kora.notify = { send = function() end }
    Kora.stream = setmetatable({}, { __index = function() return function() end end })
    Kora.loops = {
        controlled = function(call)
            for _ = 1, 16 do
                local result = call()
                if result then return result end
            end
            return false, 'Loop timed out.'
        end,
    }
    Kora.drawing = { text3d = function() end }
    Kora.world = { getClosestEntity = function() end }
    Kora.progressbar = { start = function() end }
    local cacheValues = { vehicle = false, seat = false, enteringVehicle = false, enteringSeat = false }
    local cacheListeners = {}
    Kora.cache = {
        onChange = function(key, handler)
            cacheListeners[key] = cacheListeners[key] or {}
            table.insert(cacheListeners[key], handler)
        end,
        vehicle = function() return cacheValues.vehicle end,
        seat = function() return cacheValues.seat end,
        enteringVehicle = function() return cacheValues.enteringVehicle end,
        enteringSeat = function() return cacheValues.enteringSeat end,
    }
    local cmdDefs = {}
    Kora.commands = {
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
    local function aceAllows(src, permission, prefix, includeCommand)
        return (prefix ~= nil and IsPlayerAceAllowed(src, prefix .. '.' .. permission))
            or IsPlayerAceAllowed(src, 'group.' .. permission)
            or (includeCommand and IsPlayerAceAllowed(src, 'command.' .. permission))
            or false
    end
    Kora.permissions = {
        getLevel = function(src, levels, prefix)
            for _, level in ipairs(levels) do
                if level == 'user' or aceAllows(src, level, prefix, false) then return level end
            end
            return 'user'
        end,
        hasPermission = function(src, permission, prefix)
            if permission == 'user' then return true end
            return aceAllows(src, permission, prefix, true)
        end,
    }
    Kora.status = { apply = function() return true end, remove = function() return true end }
    Kora.zones = { sphere = function() return { remove = function() end } end }

    local sqlCalls = { enqueue = {}, enqueueMany = {}, query = {}, single = {}, execute = {}, ensureTables = {}, migrate = {} }
    local sqlResponses = { query = {}, single = {} }
    Kora.sql = {
        NULL = '\0qbsql:null\0',
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
        ensureTables = function(specs) table.insert(sqlCalls.ensureTables, specs); return {} end,
        awaitTables = function() return true end,
        migrate = function(resource, list) table.insert(sqlCalls.migrate, { resource = resource, list = list }); return true end,
    }

    _G.Kora = Kora
    _G.exports = setmetatable({}, { __index = function() return setmetatable({}, { __index = function() return function() end end }) end })

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
        Kora = Kora,
        resourceStates = resourceStates,
        setPlayers = function(sources) players = sources end,
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
        drainTimeouts = function()
            local pending = timeouts
            timeouts = {}
            for _, fn in ipairs(pending) do fn() end
        end,
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

function M.stableEncode(v)
    local t = type(v)
    if t == 'nil' then return 'null'
    elseif t == 'number' then return tostring(v)
    elseif t == 'boolean' then return v and 'true' or 'false'
    elseif t == 'string' then return ('%q'):format(v)
    elseif t == 'table' then
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

function M.simpleDecode(text)
    if type(text) ~= 'string' then return nil end
    local pos = 1

    local function skip()
        pos = text:find('[^ \t\r\n]', pos) or #text + 1
    end

    local parseValue

    local function parseString()
        pos = pos + 1
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
        pos = pos + 1
        local out = {}
        skip()
        if text:sub(pos, pos) == '}' then pos = pos + 1; return out end
        while true do
            skip()
            local k = parseString()
            skip()
            pos = pos + 1
            local v = parseValue()
            out[k] = v
            skip()
            local c = text:sub(pos, pos)
            pos = pos + 1
            if c == '}' then break end
        end
        return out
    end

    local function parseArray()
        pos = pos + 1
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
