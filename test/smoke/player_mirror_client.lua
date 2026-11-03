-- Kora.player smoke test (K4) -- the client-side local copy that
-- '@kora_core/init.lua' installs into a consumer. kora_core's real client
-- replication + player modules run in this VM; a test exports bridge copies
-- every argument and result the way msgpack does across a resource boundary,
-- and counts calls so the "no export per read" property is checked.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua')
local handle = mocks.install({ client = true })

dofile('config.lua')
dofile('modules/util/shared.lua')
dofile('modules/replication/client.lua')
dofile('modules/player/client.lua')

local function clone(value)
    if type(value) ~= 'table' then return value end
    local copy = {}
    for k, v in pairs(value) do copy[clone(k)] = clone(v) end
    return copy
end

local exportCalls = 0
local liveSubscriptions = {}
local core = {
    getPlayerData = Core.player.getPlayerData,
    -- A function crossing the boundary becomes a function reference: still
    -- callable, but every argument it receives is a copy.
    onPlayerDataChange = function(prefix, fn)
        local id = Core.player.onPlayerDataChange(prefix, function(path, value) fn(clone(path), clone(value)) end)
        liveSubscriptions[id] = true
        return id
    end,
    offPlayerDataChange = Core.player.offPlayerDataChange,
}
local coreRunning = true
_G.exports = setmetatable({
    kora_core = setmetatable({}, { __index = function(_, name)
        return function(_, ...)
            assert(coreRunning, 'kora_core is not running')
            exportCalls = exportCalls + 1
            local args = { ... }
            for i = 1, select('#', ...) do args[i] = clone(args[i]) end
            return clone(core[name](table.unpack(args, 1, select('#', ...))))
        end
    end }),
}, { __index = function() return setmetatable({}, { __index = function() return function() end end }) end })

function _G.LoadResourceFile(resource, path)
    assert(resource == 'kora_core', 'only kora_core files are loaded')
    local file = assert(io.open(path, 'r'))
    local text = file:read('*a')
    file:close()
    return text
end

handle.resourceStates.kora_core = 'started'
local lifecycle = { start = {}, stop = {} }
handle.Kora.resources.onStart = function(name, fn)
    lifecycle.start[#lifecycle.start + 1] = { name = name, fn = fn }
    if GetResourceState(name) == 'started' then fn(name) end
end
handle.Kora.resources.onStop = function(name, fn)
    lifecycle.stop[#lifecycle.stop + 1] = { name = name, fn = fn }
end
local readyHandlers = {}
handle.Kora.onReady = function(fn) readyHandlers[#readyHandlers + 1] = fn; fn() end

local function restartKoraCore()
    coreRunning = false
    -- kora_core's VM dies, and every subscription in it with it.
    for id in pairs(liveSubscriptions) do Core.player.offPlayerDataChange(id); liveSubscriptions[id] = nil end
    for _, entry in ipairs(lifecycle.stop) do if entry.name == 'kora_core' then entry.fn('kora_core') end end
    coreRunning = true
    for _, entry in ipairs(lifecycle.start) do if entry.name == 'kora_core' then entry.fn('kora_core') end end
end

local function restartKoraLib()
    lifecycle.start, lifecycle.stop = {}, {}
    for _, fn in ipairs(readyHandlers) do fn() end
end

-- A player is already loaded when the consumer starts.
local seq = 1
TriggerEvent('qbcore:rep:snapshot', seq, {
    citizenid = 'CID1', money = { cash = 500 }, items = {},
    job = { name = 'police', label = 'Police', type = 'leo', onduty = true, isboss = false, grade = { level = 3, name = 'Sergeant' } },
    gang = { name = 'none', label = 'None', isboss = false, grade = { level = 1, name = 'None' } },
    metadata = { hunger = 80, thirst = 70 },
    charinfo = { firstname = 'A', lastname = 'B' },
})

local function delta(ops)
    seq = seq + 1
    TriggerEvent('qbcore:rep:delta', seq, ops)
end

dofile('init.lua')
local P = Kora.player
local callsAtLoad = exportCalls
local startHandlersAtLoad = #lifecycle.start

h.test('including init.lua costs nothing until Kora.player is first used', function()
    h.assertEqual(callsAtLoad, 0, 'no export calls at load')
    h.assertEqual(startHandlersAtLoad, 0, 'no lifecycle handlers at load')
end)

h.test('installs Kora.player on the client and seeds it from kora_core once', function()
    h.assertEqual(type(P), 'table')
    h.assertTrue(P.isLoaded())
    h.assertEqual(P.job().name, 'police')
    h.assertEqual(P.gang().name, 'none')
    h.assertEqual(P.metadata('hunger'), 80)
    h.assertEqual(P.get({ 'charinfo', 'firstname' }), 'A')
    h.assertEqual(P.get('citizenid'), 'CID1')
end)

h.test('reads and checkJob make no export calls', function()
    local before = exportCalls
    for _ = 1, 1000 do
        P.get('job'); P.job(); P.metadata('hunger'); P.get({ 'job', 'grade', 'level' })
        P.checkJob({ type = 'leo', minGrade = 2 })
    end
    h.assertEqual(exportCalls, before)
end)

h.test('checkJob uses the server rule shape and reasons', function()
    h.assertTrue(P.checkJob({ name = 'police' }))
    h.assertTrue(P.checkJob({ type = { 'leo', 'ems' }, minGrade = 3 }))
    local ok, reason = P.checkJob({ minGrade = 4 })
    h.assertFalse(ok); h.assertEqual(reason, 'grade_too_low')
    ok, reason = P.checkJob({ boss = true })
    h.assertFalse(ok); h.assertEqual(reason, 'not_boss')
    ok, reason = P.checkJob({ type = 'ems' })
    h.assertFalse(ok); h.assertEqual(reason, 'wrong_job')
end)

h.test('deltas patch the local copy and fire matching handlers', function()
    local seen = {}
    local id = P.onChange('job', function(path, value) seen[#seen + 1] = { path = table.concat(path, '.'), value = value } end)
    local dutySeen = {}
    local dutyId = P.onChange({ 'job', 'onduty' }, function(path, value) dutySeen[#dutySeen + 1] = value end)

    delta({ { p = { 'job', 'onduty' }, v = false } })
    h.assertEqual(P.job().onduty, false)
    local ok, reason = P.checkJob({ name = 'police' })
    h.assertFalse(ok); h.assertEqual(reason, 'off_duty')
    h.assertEqual(#seen, 1); h.assertEqual(seen[1].path, 'job.onduty'); h.assertEqual(seen[1].value, false)
    h.assertEqual(dutySeen[1], false)

    -- setJob replaces the whole root; a deeper handler still hears its own value.
    delta({ { p = { 'job' }, v = { name = 'ambulance', type = 'ems', onduty = true, isboss = true, grade = { level = 5 } } } })
    h.assertEqual(P.job().name, 'ambulance')
    h.assertEqual(seen[2].path, 'job')
    h.assertEqual(dutySeen[2], true)
    h.assertTrue(P.checkJob({ type = 'ems', boss = true }))

    delta({ { p = { 'metadata', 'hunger' }, v = 40 } })
    h.assertEqual(P.metadata('hunger'), 40)
    h.assertEqual(#seen, 2, 'a metadata change does not fire a job handler')

    h.assertTrue(P.offChange(id)); h.assertTrue(P.offChange(dutyId))
    h.assertFalse(P.offChange(id))
    delta({ { p = { 'job', 'onduty' }, v = false } })
    h.assertEqual(#seen, 2, 'removed handlers stay quiet')
end)

h.test('a root outside the defaults is watched from its first read', function()
    local before = exportCalls
    h.assertEqual(P.get({ 'money', 'cash' }), 500)
    h.assertTrue(exportCalls > before, 'the first read subscribes and seeds')
    local afterFirst = exportCalls
    delta({ { p = { 'money', 'cash' }, v = 650 } })
    h.assertEqual(P.get({ 'money', 'cash' }), 650)
    h.assertEqual(exportCalls, afterFirst, 'later reads are local')
end)

h.test('logout clears the copy and a new snapshot reseeds it without export calls', function()
    local values = {}
    P.onChange('charinfo', function(_, value) values[#values + 1] = value and value.firstname or false end)
    TriggerEvent('QBCore:Client:OnPlayerUnload')
    h.assertFalse(P.isLoaded())
    h.assertEqual(P.job(), nil)
    local ok, reason = P.checkJob({ name = 'police' })
    h.assertFalse(ok); h.assertEqual(reason, 'no_player')
    h.assertEqual(values[#values], false, 'handlers hear the logout')

    local before = exportCalls
    seq = 1
    TriggerEvent('qbcore:rep:snapshot', seq, {
        citizenid = 'CID2', money = { cash = 5 }, items = {},
        job = { name = 'mechanic', type = 'mechanic', onduty = true, grade = { level = 1 } },
        gang = { name = 'none', grade = { level = 1 } }, metadata = { hunger = 100 },
        charinfo = { firstname = 'C', lastname = 'D' },
    })
    h.assertEqual(exportCalls, before, 'the snapshot event carries the data')
    h.assertEqual(P.get('citizenid'), 'CID2')
    h.assertEqual(P.job().name, 'mechanic')
    h.assertEqual(P.get({ 'money', 'cash' }), 5, 'lazily watched roots are reseeded too')
    h.assertEqual(values[#values], 'C')
end)

h.test('a kora_core restart re-subscribes; a kora_lib restart does not double events', function()
    local hits = 0
    P.onChange({ 'metadata', 'thirst' }, function() hits = hits + 1 end)
    restartKoraCore()
    hits = 0
    delta({ { p = { 'metadata', 'thirst' }, v = 10 } })
    h.assertEqual(P.metadata('thirst'), 10)
    h.assertEqual(hits, 1, 'one event after a kora_core restart')

    restartKoraLib()
    hits = 0
    delta({ { p = { 'metadata', 'thirst' }, v = 20 } })
    h.assertEqual(P.metadata('thirst'), 20)
    h.assertEqual(hits, 1, 'resubscribing is idempotent')
end)

h.test('onChange validates its arguments', function()
    h.assertFalse(pcall(P.onChange, {}, function() end))
    h.assertFalse(pcall(P.onChange, 'job', 'nope'))
end)

h.report('player_mirror_client')
