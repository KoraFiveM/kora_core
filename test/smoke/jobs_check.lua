-- Core.jobs.checkJob smoke test -- the shared job-rule matcher (K2) read
-- against the live PlayerData.job, with every failure reason.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); mocks.install()
dofile('config.lua')
dofile('shared/items.lua'); dofile('shared/jobs.lua'); dofile('shared/gangs.lua')
dofile('shared/vehicles.lua'); dofile('shared/weapons.lua'); dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua'); dofile('modules/registry/server.lua')
dofile('modules/player/shared.lua')
local matchRule = dofile('modules/jobs/shared.lua')
dofile('modules/replication/server.lua'); dofile('modules/persistence/server.lua')
dofile('modules/player/server.lua')
dofile('modules/jobs/server.lua')

local PI = CoreInternal.player
for src, cid in ipairs({ 'COP1', 'EMS1', 'CIV1' }) do
    Core.player.login(src, cid, PI.freshData(cid, 'license:' .. cid, 1, { firstname = 'F', lastname = 'L' }))
end
Core.jobs.setJob(1, 'police', 3)
Core.jobs.setJob(2, 'ambulance', 5)

h.test('the shared file returns the same matcher it publishes on CoreInternal', function()
    h.assertEqual(type(matchRule), 'function')
    h.assertTrue(CoreInternal.jobs.matchRule == matchRule)
end)

h.test('off-duty players fail by default and pass with onDuty = false', function()
    Core.jobs.setJobDuty(1, false)
    local ok, reason = Core.jobs.checkJob(1, { name = 'police' })
    h.assertFalse(ok); h.assertEqual(reason, 'off_duty')
    h.assertTrue(Core.jobs.checkJob(1, { name = 'police', onDuty = false }))
    Core.jobs.setJobDuty(1, true)
    h.assertTrue(Core.jobs.checkJob(1, { name = 'police' }), 'reads the live duty flag')
end)

h.test('name and type accept a string or a list', function()
    h.assertTrue(Core.jobs.checkJob(1, { name = { 'sheriff', 'police' } }))
    h.assertTrue(Core.jobs.checkJob(1, { type = 'leo' }))
    Core.jobs.setJobDuty(2, true)
    h.assertTrue(Core.jobs.checkJob(2, { type = { 'leo', 'ems' } }))
    local ok, reason = Core.jobs.checkJob(2, { type = 'leo' })
    h.assertFalse(ok); h.assertEqual(reason, 'wrong_job')
    ok, reason = Core.jobs.checkJob(1, { name = 'police', type = 'ems' })
    h.assertFalse(ok, 'name and type must both match'); h.assertEqual(reason, 'wrong_job')
    ok, reason = Core.jobs.checkJob(3, { name = 'police', onDuty = false })
    h.assertFalse(ok); h.assertEqual(reason, 'wrong_job')
end)

h.test('minGrade uses one-based grade levels', function()
    h.assertTrue(Core.jobs.checkJob(1, { name = 'police', minGrade = 3 }))
    local ok, reason = Core.jobs.checkJob(1, { name = 'police', minGrade = 4 })
    h.assertFalse(ok); h.assertEqual(reason, 'grade_too_low')
end)

h.test('boss requires a boss grade', function()
    local ok, reason = Core.jobs.checkJob(1, { name = 'police', boss = true })
    h.assertFalse(ok); h.assertEqual(reason, 'not_boss')
    Core.jobs.setJobDuty(2, true)
    h.assertTrue(Core.jobs.checkJob(2, { type = 'ems', boss = true }))
end)

h.test('reason order: wrong_job before off_duty before grade before boss', function()
    Core.jobs.setJobDuty(1, false)
    local _, reason = Core.jobs.checkJob(1, { name = 'ambulance', minGrade = 9, boss = true })
    h.assertEqual(reason, 'wrong_job')
    _, reason = Core.jobs.checkJob(1, { name = 'police', minGrade = 9, boss = true })
    h.assertEqual(reason, 'off_duty')
    _, reason = Core.jobs.checkJob(1, { name = 'police', onDuty = false, minGrade = 9, boss = true })
    h.assertEqual(reason, 'grade_too_low')
    Core.jobs.setJobDuty(1, true)
end)

h.test('unknown or string sources return no_player; a nil rule means any job on duty', function()
    local ok, reason = Core.jobs.checkJob(99, { name = 'police' })
    h.assertFalse(ok); h.assertEqual(reason, 'no_player')
    h.assertTrue(Core.jobs.checkJob('1', { name = 'police' }), 'an export caller may pass a string id')
    h.assertTrue(Core.jobs.checkJob(1))
end)

h.test('a malformed rule is a programmer error', function()
    h.assertFalse(pcall(Core.jobs.checkJob, 1, 'police'))
    h.assertFalse(pcall(Core.jobs.checkJob, 1, { name = 5 }))
    h.assertFalse(pcall(Core.jobs.checkJob, 1, { minGrade = '3' }))
    h.assertFalse(pcall(Core.jobs.checkJob, 1, { onDuty = 'yes' }))
end)

h.test('checks read the live job and allocate nothing (no PlayerData copy)', function()
    local rule = { type = { 'leo', 'ems' }, minGrade = 2 }
    Core.jobs.checkJob(1, rule)
    collectgarbage('collect'); collectgarbage('stop')
    local before = collectgarbage('count')
    for _ = 1, 10000 do Core.jobs.checkJob(1, rule) end
    local grownKb = collectgarbage('count') - before
    collectgarbage('restart')
    h.assertTrue(grownKb < 1, ('10000 checks allocated %.1f KB'):format(grownKb))
end)

h.report('jobs_check')
