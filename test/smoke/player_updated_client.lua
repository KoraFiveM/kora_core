_G.IsDuplicityVersion = function() return false end

local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua')
local handle = mocks.install()

dofile('config.lua')
dofile('shared/items.lua'); dofile('shared/jobs.lua'); dofile('shared/gangs.lua')
dofile('shared/vehicles.lua'); dofile('shared/weapons.lua'); dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua')
dofile('modules/replication/client.lua')
dofile('compat/shared/coreobject.lua')
dofile('compat/client/qb-core-events.lua')

TriggerEvent('kora_core:rep:snapshot', 1, {
    citizenid = 'CID1',
    money = { cash = 500 },
    job = { name = 'police', label = 'Police', grade = { level = 3, name = 'Sergeant' }, onduty = true },
    gang = { name = 'ballas', label = 'Ballas', grade = { level = 2, name = 'Boss', isboss = true } },
})

h.test('QBCore:Client:OnPlayerUpdated with key=="all" and a malicious val does NOT touch the mirror', function()
    local before = Core.util.deepClone(Core.replication.getData())
    TriggerEvent('QBCore:Client:OnPlayerUpdated', 'all', { money = { cash = 999999999 }, job = { name = 'HACKED' } })
    local after = Core.replication.getData()
    h.assertEqual(after.money.cash, before.money.cash, 'money must be untouched by the pushed val')
    h.assertEqual(after.job.name, before.job.name, 'job must be untouched by the pushed val')
    h.assertEqual(after.job.grade.level, before.job.grade.level, 'the INTERNAL (one-based) grade.level must be untouched -- '
        .. 'a naive re-fire without REFIRE_TOKEN would get merged back into the mirror by the foreign-write acceptor '
        .. 'in modules/replication/client.lua, corrupting it with the legacy (zero-based) shape')
    h.assertEqual(after.gang.name, before.gang.name, 'gang must be untouched by the pushed val')
end)

h.test('QBCore:Client:OnPlayerUpdated with key==nil re-fires SetPlayerData with the CURRENT legacy-shaped mirror', function()
    local captured
    AddEventHandler('QBCore:Player:SetPlayerData', function(data) captured = data end)
    TriggerEvent('QBCore:Client:OnPlayerUpdated', nil, 'garbage-ignored')
    h.assertTrue(captured ~= nil, 'SetPlayerData must re-fire')
    h.assertEqual(captured.money.cash, 500, 'payload must be the mirror\'s real current data')
    h.assertEqual(captured.job.grade.level, 2, 'payload must be legacy-shaped (zero-based grade.level, internal 3 -> legacy 2)')
end)

h.test('QBCore:Client:OnPlayerUpdated with key=="job" re-fires OnJobUpdate with the CURRENT legacy-shaped job, ignoring val', function()
    local captured
    AddEventHandler('QBCore:Client:OnJobUpdate', function(job) captured = job end)
    TriggerEvent('QBCore:Client:OnPlayerUpdated', 'job', { name = 'HACKED', grade = { level = 99 } })
    h.assertTrue(captured ~= nil, 'OnJobUpdate must re-fire')
    h.assertEqual(captured.name, 'police', 'must use the mirror\'s real job, not the pushed val')
    h.assertEqual(captured.grade.level, 2, 'legacy-shaped grade.level')
end)

h.test('QBCore:Client:OnPlayerUpdated with key=="gang" re-fires OnGangUpdate with the CURRENT legacy-shaped gang, ignoring val', function()
    local captured
    AddEventHandler('QBCore:Client:OnGangUpdate', function(gang) captured = gang end)
    TriggerEvent('QBCore:Client:OnPlayerUpdated', 'gang', { name = 'HACKED' })
    h.assertTrue(captured ~= nil, 'OnGangUpdate must re-fire')
    h.assertEqual(captured.name, 'ballas', 'must use the mirror\'s real gang, not the pushed val')
    h.assertEqual(captured.grade.level, 1, 'legacy-shaped grade.level (internal 2 -> legacy 1)')
end)

h.test('QBCore:Client:OnPlayerUpdated with an unrelated key is a no-op', function()
    local jobFired, gangFired, setDataFired = false, false, false
    AddEventHandler('QBCore:Client:OnJobUpdate', function() jobFired = true end)
    AddEventHandler('QBCore:Client:OnGangUpdate', function() gangFired = true end)
    AddEventHandler('QBCore:Player:SetPlayerData', function() setDataFired = true end)
    TriggerEvent('QBCore:Client:OnPlayerUpdated', 'somethingElse', 'val')
    h.assertFalse(jobFired, 'no re-fire expected for an unrelated key')
    h.assertFalse(gangFired, 'no re-fire expected for an unrelated key')
    h.assertFalse(setDataFired, 'no re-fire expected for an unrelated key')
end)

h.report('player_updated_client')
