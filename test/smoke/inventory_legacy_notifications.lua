-- Timed client fixture: full legacy notifications are bounded, while delta
-- application, public reads, and modern subscribers retain their timing.
local h = dofile('test/harness.lua')
local handle = dofile('test/mocks.lua').install({ client = true })

dofile('config.lua')
dofile('shared/items.lua'); dofile('shared/jobs.lua'); dofile('shared/gangs.lua')
dofile('shared/vehicles.lua'); dofile('shared/weapons.lua'); dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua')
dofile('modules/replication/client.lua')
dofile('modules/player/client.lua')
dofile('compat/shared/coreobject.lua')
dofile('compat/client/qb-core.lua')
handle.setCloneLocalNetPayloads(true)

local now, timers = 0, {}
function GetGameTimer() return now end
function SetTimeout(delay, fn)
    timers[#timers + 1] = { due = now + delay, fn = fn }
end

local function advance(ms)
    local target = now + ms
    while true do
        local nextIndex
        for i, timer in ipairs(timers) do
            if timer.due <= target and (not nextIndex or timer.due < timers[nextIndex].due) then
                nextIndex = i
            end
        end
        if not nextIndex then break end
        local timer = table.remove(timers, nextIndex)
        now = timer.due
        timer.fn()
    end
    now = target
end

local legacy, changes, jobs, gangs = {}, {}, {}, {}
AddEventHandler('QBCore:Player:SetPlayerData', function(data)
    legacy[#legacy + 1] = { at = now, data = Core.util.deepClone(data) }
end)
AddEventHandler('QBCore:Client:OnJobUpdate', function(job) jobs[#jobs + 1] = job end)
AddEventHandler('QBCore:Client:OnGangUpdate', function(gang) gangs[#gangs + 1] = gang end)
Core.player.onPlayerDataChange({ 'items' }, function(path, value)
    changes[#changes + 1] = { path = path, value = value }
end)

local function weapon(ammo)
    return { name = 'weapon_pistol', amount = 1, slot = 1, info = { ammo = ammo, quality = 98 } }
end

local function reset()
    now, timers = 0, {}
    Config.compat.fireLegacyPlayerDataEvent = true
    Config.compat.inventoryPlayerDataEventInterval = 250
    Config.compat.jobUpdateEventSource = 'client'
    TriggerEvent('qbcore:rep:snapshot', 0, {
        citizenid = 'FIRST', items = { [1] = weapon(30) }, money = { cash = 100 },
        job = { name = 'police', grade = { level = 3 } },
        gang = { name = 'ballas', grade = { level = 2 } },
    })
    legacy, changes, jobs, gangs = {}, {}, {}, {}
end

local function itemDelta(seq, ammo)
    TriggerEvent('qbcore:rep:delta', seq, { { p = { 'items', 1 }, v = weapon(ammo) } })
end

h.test('inventory bursts notify once with current data while public reads and subscribers stay immediate', function()
    reset()
    local applied = Core.replication.getStats().opsApplied
    itemDelta(1, 29)
    advance(100)
    itemDelta(2, 28)
    h.assertEqual(#legacy, 0)
    h.assertEqual(#changes, 2)
    h.assertEqual(Core.player.getPlayerData({ 'items', 1 }).info.ammo, 28)
    h.assertEqual(QBCore.PlayerData.items[1].info.ammo, 28)
    h.assertEqual(QBCore.Functions.GetPlayerData().items[1].info.ammo, 28)
    local stats = Core.replication.getStats()
    h.assertEqual(stats.seq, 2)
    h.assertEqual(stats.opsApplied, applied + 2)
    h.assertEqual(stats.lastDeltaAt, 100)
    advance(149)
    h.assertEqual(#legacy, 0)
    advance(1)
    h.assertEqual(#legacy, 1)
    h.assertEqual(legacy[1].at, 250)
    h.assertEqual(legacy[1].data.items[1].info.ammo, 28)
    h.assertEqual(legacy[1].data.items[1].info.quality, 98)
    h.assertEqual(legacy[1].data.money.cash, 100)
    h.assertEqual(legacy[1].data.job.grade.level, 2)
    h.assertEqual(Core.replication.getData({ 'job', 'grade', 'level' }), 3,
        'the serialized re-fire must not write legacy grades into the mirror')
end)

h.test('continuous changes do not postpone the bound and the final change is announced', function()
    reset()
    itemDelta(1, 29)
    for i = 1, 20 do
        advance(50)
        itemDelta(i + 1, 29 - i)
    end
    h.assertEqual(#legacy, 4)
    for i, event in ipairs(legacy) do h.assertEqual(event.at, i * 250) end
    h.assertEqual(Core.replication.getData({ 'items', 1, 'info', 'ammo' }), 9)
    advance(250)
    h.assertEqual(#legacy, 5)
    h.assertEqual(legacy[5].data.items[1].info.ammo, 9)
    advance(1000)
    h.assertEqual(#legacy, 5, 'idle time must not generate notifications')
end)

h.test('non-inventory updates announce immediately and an old timer cannot flush a new pending update', function()
    reset()
    itemDelta(1, 29)
    advance(100)
    TriggerEvent('qbcore:rep:delta', 2, { { p = { 'money', 'cash' }, v = 200 } })
    h.assertEqual(#legacy, 1)
    h.assertEqual(legacy[1].data.items[1].info.ammo, 29)
    h.assertEqual(legacy[1].data.money.cash, 200)
    advance(50)
    itemDelta(3, 28)
    advance(100)
    h.assertEqual(#legacy, 1, 'the invalidated 250 ms timer must not emit the new pending change')
    advance(150)
    h.assertEqual(#legacy, 2)
    h.assertEqual(legacy[2].at, 400)
    h.assertEqual(legacy[2].data.items[1].info.ammo, 28)
end)

h.test('mixed inventory, job, and gang updates preserve immediate legacy event payloads', function()
    reset()
    itemDelta(1, 29)
    advance(100)
    TriggerEvent('qbcore:rep:delta', 2, {
        { p = { 'items', 1 }, v = weapon(28) },
        { p = { 'job' }, v = { name = 'ambulance', grade = { level = 4 } } },
        { p = { 'gang' }, v = { name = 'lostmc', grade = { level = 3 } } },
    })
    h.assertEqual(#legacy, 1)
    h.assertEqual(#jobs, 1)
    h.assertEqual(#gangs, 1)
    h.assertEqual(jobs[1].grade.level, 3)
    h.assertEqual(gangs[1].grade.level, 2)
    h.assertEqual(legacy[1].data.items[1].info.ammo, 28)
    advance(250)
    h.assertEqual(#legacy, 1)
    h.assertEqual(#jobs, 1)
    h.assertEqual(#gangs, 1)
end)

h.test('inventory deletion is immediately readable and the delayed payload retains the deletion', function()
    reset()
    itemDelta(1, 29)
    TriggerEvent('qbcore:rep:delta', 2, { { p = { 'items' }, d = true } })
    h.assertEqual(Core.replication.getData({ 'items' }), nil)
    h.assertEqual(QBCore.Functions.GetPlayerData().items, nil)
    advance(250)
    h.assertEqual(#legacy, 1)
    h.assertEqual(legacy[1].data.items, nil)
end)

h.test('explicit re-announcement and resync snapshots emit immediately and invalidate pending notifications', function()
    reset()
    itemDelta(1, 29)
    advance(100)
    h.assertTrue(Core.replication.reannounceFull())
    h.assertEqual(#legacy, 1)
    advance(150)
    h.assertEqual(#legacy, 1)
    itemDelta(2, 28)
    TriggerEvent('qbcore:rep:snapshot', 10, { citizenid = 'FIRST', items = { [1] = weapon(10) } })
    h.assertEqual(#legacy, 2)
    h.assertEqual(legacy[2].data.items[1].info.ammo, 10)
    h.assertEqual(Core.replication.getStats().seq, 10)
    advance(250)
    h.assertEqual(#legacy, 2)
end)

h.test('unload discards pending notifications and a delta before login still requests resync', function()
    reset()
    itemDelta(1, 29)
    TriggerEvent('QBCore:Client:OnPlayerUnload')
    h.assertEqual(Core.replication.getData(), nil)
    h.assertFalse(Core.replication.reannounceFull())
    local requests = #handle.serverEvents
    itemDelta(2, 28)
    h.assertEqual(#handle.serverEvents, requests + 1)
    h.assertEqual(handle.serverEvents[#handle.serverEvents].name, 'qbcore:rep:resync')
    advance(250)
    h.assertEqual(#legacy, 0)
end)

h.test('a previous character timer cannot emit or cancel a new character notification', function()
    reset()
    itemDelta(1, 29)
    advance(100)
    TriggerEvent('QBCore:Client:OnPlayerUnload')
    advance(50)
    TriggerEvent('qbcore:rep:snapshot', 0, { citizenid = 'SECOND', items = { [1] = weapon(20) } })
    h.assertEqual(#legacy, 1, 'new login announces immediately')
    itemDelta(1, 19)
    advance(100)
    h.assertEqual(#legacy, 1)
    advance(150)
    h.assertEqual(#legacy, 2)
    h.assertEqual(legacy[2].at, 400)
    h.assertEqual(legacy[2].data.citizenid, 'SECOND')
    h.assertEqual(legacy[2].data.items[1].info.ammo, 19)
end)

h.test('a sequence gap never applies or announces the missing state', function()
    reset()
    local before = Core.replication.getStats()
    itemDelta(1, 29)
    advance(100)
    itemDelta(3, 999)
    local stats = Core.replication.getStats()
    h.assertEqual(stats.seq, 1)
    h.assertEqual(stats.resyncs, before.resyncs + 1)
    h.assertEqual(stats.opsApplied, before.opsApplied + 1)
    h.assertEqual(Core.replication.getData({ 'items', 1, 'info', 'ammo' }), 29)
    advance(150)
    h.assertEqual(#legacy, 1)
    h.assertEqual(legacy[1].data.items[1].info.ammo, 29)
end)

h.test('zero interval restores every-delta notifications without a timer', function()
    reset()
    Config.compat.inventoryPlayerDataEventInterval = 0
    itemDelta(1, 29)
    itemDelta(2, 28)
    h.assertEqual(#legacy, 2)
    h.assertEqual(#timers, 0)
    h.assertEqual(legacy[2].data.items[1].info.ammo, 28)
end)

h.test('a configured interval controls the bound and the disabled legacy flag schedules no timer', function()
    reset()
    Config.compat.inventoryPlayerDataEventInterval = 100
    itemDelta(1, 29)
    advance(99)
    h.assertEqual(#legacy, 0)
    advance(1)
    h.assertEqual(#legacy, 1)
    Config.compat.fireLegacyPlayerDataEvent = false
    itemDelta(2, 28)
    h.assertEqual(#timers, 0)
    h.assertEqual(QBCore.Functions.GetPlayerData().items[1].info.ammo, 28)
    h.assertEqual(#legacy, 1)
end)

h.test('disabling legacy events cancels a pending notification', function()
    reset()
    itemDelta(1, 29)
    Config.compat.fireLegacyPlayerDataEvent = false
    advance(250)
    h.assertEqual(#legacy, 0)
    Config.compat.fireLegacyPlayerDataEvent = true
    itemDelta(2, 28)
    advance(250)
    h.assertEqual(#legacy, 1)
    h.assertEqual(legacy[1].data.items[1].info.ammo, 28)
end)

h.test('a foreign full legacy write invalidates the pending re-fire without overwriting accepted data', function()
    reset()
    itemDelta(1, 29)
    local originalPrint = print
    local warnings = {}
    print = function(message) warnings[#warnings + 1] = message end
    TriggerEvent('QBCore:Player:SetPlayerData', { citizenid = 'FIRST', items = { [1] = weapon(12) } })
    print = originalPrint
    h.assertEqual(#warnings, 1)
    h.assertEqual(Core.replication.getData({ 'items', 1, 'info', 'ammo' }), 12)
    h.assertEqual(#legacy, 1, 'the foreign event already notified listeners')
    advance(250)
    h.assertEqual(#legacy, 1)
end)

h.report('inventory_legacy_notifications')
