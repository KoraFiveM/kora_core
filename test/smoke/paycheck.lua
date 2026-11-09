local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('shared/items.lua'); dofile('shared/jobs.lua'); dofile('shared/gangs.lua')
dofile('shared/vehicles.lua'); dofile('shared/weapons.lua'); dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua'); dofile('modules/registry/server.lua')
dofile('modules/player/shared.lua')
dofile('modules/replication/server.lua'); dofile('modules/persistence/server.lua')
dofile('modules/player/server.lua')
dofile('modules/money/server.lua')
dofile('modules/jobs/server.lua')
dofile('modules/paycheck/server.lua')

local function loginAs(src, cid)
    local data = CoreInternal.player.freshData(cid, 'license:' .. cid, 1, { firstname = 'A', lastname = 'B' })
    Core.player.login(src, cid, data)
end

loginAs(1, 'ONDUTY')
loginAs(2, 'OFFDUTY')
loginAs(3, 'CIV')

Core.jobs.setJob(1, 'police', 1)
Core.jobs.setJobDuty(1, true)
Core.jobs.setJob(2, 'police', 1)
Core.jobs.setJobDuty(2, false)
Core.jobs.setJobDuty(3, false)

h.test('an on-duty player is paid their grade payment', function()
    local before = Core.money.getMoney(1, 'cash')
    Core.paycheck._tick()
    h.assertEqual(Core.money.getMoney(1, 'cash'), before + 50)
end)

h.test('an off-duty player with offDutyPay = false is not paid', function()
    local before = Core.money.getMoney(2, 'cash')
    Core.paycheck._tick()
    h.assertEqual(Core.money.getMoney(2, 'cash'), before, 'police.offDutyPay is false -- no paycheck while off duty')
end)

h.test('an off-duty employed player IS paid when offDutyPay is a number', function()
    Core.registry.registerShared('jobs', 'police', {
        name = 'police', label = 'Law Enforcement', defaultDuty = false, offDutyPay = 20,
        grades = { { name = 'Cadet', payment = 50 } },
    })

    local before = Core.money.getMoney(2, 'cash')
    Core.paycheck._tick()
    h.assertEqual(Core.money.getMoney(2, 'cash'), before + 20)
end)

h.test('an unemployed player (default job, payment = 10) is still paid on duty', function()
    Core.jobs.setJobDuty(3, true)
    local before = Core.money.getMoney(3, 'cash')
    Core.paycheck._tick()
    h.assertEqual(Core.money.getMoney(3, 'cash'), before + 10)
end)

h.test('startPaycheck/stopPaycheck toggle isPaycheckRunning without erroring', function()
    h.assertFalse(Core.paycheck.isPaycheckRunning())
    Core.paycheck.startPaycheck()
    h.assertTrue(Core.paycheck.isPaycheckRunning())
    Core.paycheck.stopPaycheck()
    h.assertFalse(Core.paycheck.isPaycheckRunning())
end)

h.report('paycheck')
