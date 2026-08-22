-- Replication smoke test -- server-side frame coalescing + seq, and client-side
-- delta apply / seq-gap resync / delete ops / legacy event. Because server and
-- client both define Core.replication.*, they'd collide in one process -- so
-- this file loads the SERVER realm, captures references, then loads the CLIENT
-- realm into a fresh Core (following qblib's same-name-across-realms workaround).

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

local serverQueueOp = Core.replication._queueOp

-- Log a player in so the funnel has a handle.
local data = CoreInternal.player.freshData('CID1', 'license:abc', 1, { firstname = 'A', lastname = 'B' })
Core.player.login(1, 'CID1', data)
local player = CoreInternal.player.handle(1)

h.test('N mutations in one frame coalesce into ONE delta with per-path last value', function()
    for i=#handle.clientEvents,1,-1 do handle.clientEvents[i]=nil end
    -- Same path written 3 times in one "frame" -> one op with the last value.
    serverQueueOp(player, { 'metadata', 'hunger' }, 90)
    serverQueueOp(player, { 'metadata', 'hunger' }, 80)
    serverQueueOp(player, { 'metadata', 'hunger' }, 70)
    -- A second distinct path -> a second op in the same batch.
    serverQueueOp(player, { 'money', 'cash' }, 1234)
    handle.drainTimeouts()   -- fire the end-of-frame SetTimeout(0)

    local delta = handle.lastClient('qbcore:rep:delta')
    h.assertTrue(delta ~= nil, 'expected a delta event')
    local ops = delta.args[2]
    h.assertEqual(#ops, 2, 'coalesced to two distinct paths')
    -- Find the hunger op; its value must be the LAST write (70).
    local hunger
    for _, op in ipairs(ops) do if op.p[2] == 'hunger' then hunger = op end end
    h.assertEqual(hunger.v, 70, 'last write wins within a frame')
end)

h.test('seq increments per batch', function()
    local before = player._seq
    for i=#handle.clientEvents,1,-1 do handle.clientEvents[i]=nil end
    serverQueueOp(player, { 'metadata', 'thirst' }, 55)
    handle.drainTimeouts()
    h.assertEqual(player._seq, before + 1)
end)

-- Now exercise the CLIENT realm in a fresh Core, so its Core.replication.* does
-- not collide with the server one captured above.
_G.Core = setmetatable({}, { __index = function(self, k) local m = {}; rawset(self, k, m); return m end })
_G.CoreInternal = {}
_G.source = nil
dofile('modules/replication/client.lua')
local clientRep = Core.replication

h.test('client applies a snapshot then a delta batch to its mirror', function()
    -- Snapshot at seq 0 primes the mirror.
    TriggerEvent('qbcore:rep:snapshot', 0, { money = { cash = 100 }, metadata = { hunger = 100 } })
    h.assertEqual(clientRep.getData({ 'money', 'cash' }), 100)
    -- Delta batch seq 1 applies in order.
    TriggerEvent('qbcore:rep:delta', 1, {
        { p = { 'money', 'cash' }, v = 250 },
        { p = { 'metadata', 'hunger' }, v = 80 },
    })
    h.assertEqual(clientRep.getData({ 'money', 'cash' }), 250)
    h.assertEqual(clientRep.getData({ 'metadata', 'hunger' }), 80)
end)

h.test('a delete op (d=true) removes the key rather than setting nil', function()
    TriggerEvent('qbcore:rep:snapshot', 10, { items = { [1] = { name = 'x' } } })
    TriggerEvent('qbcore:rep:delta', 11, { { p = { 'items', 1 }, d = true } })
    h.assertTrue(clientRep.getData({ 'items', 1 }) == nil, 'delete op should remove the slot')
end)

h.test('a seq gap requests exactly one resync', function()
    TriggerEvent('qbcore:rep:snapshot', 20, { money = { cash = 5 } })
    for i=#handle.serverEvents,1,-1 do handle.serverEvents[i]=nil end
    -- Deliver seq 22 (gap: expected 21) -> should request a resync, not apply.
    TriggerEvent('qbcore:rep:delta', 22, { { p = { 'money', 'cash' }, v = 999 } })
    h.assertEqual(clientRep.getData({ 'money', 'cash' }), 5, 'stale delta must not apply')
    local resyncs = 0
    for _, e in ipairs(handle.serverEvents) do if e.name == 'qbcore:rep:resync' then resyncs = resyncs + 1 end end
    h.assertEqual(resyncs, 1, 'exactly one resync requested on a gap')
end)

h.test('the legacy QBCore:Player:SetPlayerData event fires locally on a delta', function()
    local fired = false
    AddEventHandler('QBCore:Player:SetPlayerData', function() fired = true end)
    TriggerEvent('qbcore:rep:snapshot', 30, { money = { cash = 1 } })
    fired = false
    TriggerEvent('qbcore:rep:delta', 31, { { p = { 'money', 'cash' }, v = 2 } })
    h.assertTrue(fired, 'legacy full-blob event should fire client-side from the mirror')
end)

h.report('replication')
