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

TriggerEvent('qbcore:rep:snapshot', 1, {
    citizenid = 'CID1', money = { cash = 500 },
    job = { name = 'police', label = 'Police', grade = { level = 3, name = 'Sergeant' }, onduty = true },
    gang = { name = 'none', label = 'None', grade = { level = 1, name = 'None' } },
})

h.test('a captured QBCore.PlayerData reference follows later changes', function()
    local captured = QBCore.PlayerData
    h.assertTrue(captured ~= nil)
    TriggerEvent('qbcore:rep:delta', 2, { { p = { 'money', 'cash' }, v = 900 } })
    h.assertEqual(QBCore.PlayerData, captured, 'the table identity is kept')
    h.assertEqual(captured.money.cash, 900)
    TriggerEvent('qbcore:rep:delta', 3, { { p = { 'job', 'name' }, v = 'ambulance' } })
    h.assertEqual(captured.job.name, 'ambulance')
end)

h.test('keys removed from the mirror disappear from the captured table', function()
    local captured = QBCore.PlayerData
    TriggerEvent('qbcore:rep:delta', 4, { { p = { 'metadata' }, v = { hunger = 5 } } })
    h.assertEqual(captured.metadata.hunger, 5)
    TriggerEvent('qbcore:rep:delta', 5, { { p = { 'metadata' }, d = true } })
    h.assertEqual(captured.metadata, nil)
    h.assertEqual(QBCore.PlayerData, captured)
end)

h.test('unload empties QBCore.PlayerData so the next character starts clean', function()
    local captured = QBCore.PlayerData
    TriggerEvent('qbcore:rep:delta', 6, { { p = { 'metadata' }, v = { ishandcuffed = true, isdead = true } } })
    h.assertEqual(captured.metadata.ishandcuffed, true)
    TriggerEvent('QBCore:Client:OnPlayerUnload')
    h.assertEqual(next(captured), nil, 'no field of the previous character survives unload')
    h.assertEqual(QBCore.PlayerData, captured)
    TriggerEvent('qbcore:rep:snapshot', 0, {
        citizenid = 'CID2', money = { cash = 10 },
        job = { name = 'unemployed', label = 'Civilian', grade = { level = 1, name = 'Freelancer' }, onduty = true },
        gang = { name = 'none', label = 'None', grade = { level = 1, name = 'None' } },
    })
    h.assertEqual(captured.citizenid, 'CID2')
    h.assertEqual(captured.metadata, nil, 'the old metadata is not carried over')
end)

h.report('client_playerdata_inplace')
