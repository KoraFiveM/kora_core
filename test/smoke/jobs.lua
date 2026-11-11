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
dofile('modules/jobs/server.lua')

local PI = CoreInternal.player

local function loginAs(src, cid)
    local data = PI.freshData(cid, 'license:' .. cid, 1, { firstname = 'First' .. cid, lastname = 'Last' })
    Core.player.login(src, cid, data)
end

local function sorted(list)
    local copy = {}
    for i, v in ipairs(list) do copy[i] = v end
    table.sort(copy)
    return copy
end

local function equalSets(actual, expected, message)
    actual, expected = sorted(actual), sorted(expected)
    h.assertEqual(#actual, #expected, message .. ' (count)')
    for i = 1, #expected do
        h.assertEqual(actual[i], expected[i], message .. (' (entry %d)'):format(i))
    end
end

loginAs(1, 'COP1')
loginAs(2, 'COP2')
loginAs(3, 'EMS1')
loginAs(4, 'TOW1')
loginAs(5, 'CIV1')

h.test('buildJob copies the registry job type onto PlayerData.job', function()
    Core.jobs.setJob(1, 'police', 2)
    local job = Core.jobs.getJob(1)

    h.assertEqual(job.name, 'police', 'job name should be set')
    h.assertEqual(job.type, 'leo', 'the registry type must reach PlayerData.job')
    h.assertEqual(job.grade.level, 2, 'grade should be one-based internally')
end)

h.test('an unknown job type falls back to none rather than nil', function()
    Core.registry.registerShared('jobs', 'untyped', {
        name = 'untyped', label = 'Untyped', grades = { { name = 'Worker', payment = 10 } },
    })
    Core.jobs.setJob(5, 'untyped', 1)

    h.assertEqual(Core.jobs.getJob(5).type, 'none', "a job with no type reads back as 'none', never nil")
end)

h.test('setJob refuses a job that is not registered', function()
    local ok, err = Core.jobs.setJob(1, 'definitely_not_a_job', 1)
    h.assertFalse(ok, 'an unregistered job must be refused')
    h.assertEqual(err, 'unknown job', 'and say why')
end)

h.test('getPlayersByJob tracks membership and duty separately', function()
    Core.jobs.setJob(2, 'police', 1)

    equalSets(Core.jobs.getPlayersByJob('police'), { 1, 2 }, 'both officers hold the job')
    equalSets(Core.jobs.getPlayersByJob('police', true), {}, 'police defaultDuty is false, so nobody is on duty yet')

    Core.jobs.setJobDuty(1, true)

    equalSets(Core.jobs.getPlayersByJob('police', true), { 1 }, 'only the officer who went on duty')
    h.assertEqual(Core.jobs.getDutyCount('police'), 1, 'duty count should agree with the set')
end)

h.test('changing job moves a player out of the old job set', function()
    Core.jobs.setJob(2, 'ambulance', 1)

    equalSets(Core.jobs.getPlayersByJob('police'), { 1 }, 'the leaver must be gone from the old job')
    equalSets(Core.jobs.getPlayersByJob('ambulance'), { 2 }, 'and present in the new one')
end)

h.test('getPlayersByJobType spans every job carrying that type', function()
    Core.jobs.setJob(2, 'police', 1); Core.jobs.setJobDuty(2, true)
    Core.jobs.setJob(3, 'ambulance', 1); Core.jobs.setJobDuty(3, true)
    Core.jobs.setJob(4, 'tow', 1); Core.jobs.setJobDuty(4, true)

    equalSets(Core.jobs.getPlayersByJobType('leo', true), { 1, 2 }, 'both on-duty officers are leo')
    equalSets(Core.jobs.getPlayersByJobType('ems', true), { 3 }, 'the paramedic is ems')
    equalSets(Core.jobs.getPlayersByJobType('recovery', true), { 4 }, 'the tow driver is recovery')
    equalSets(Core.jobs.getPlayersByJobType('leo'), { 1, 2 }, 'membership ignores duty')
end)

h.test('a job change moves the player between type sets', function()
    Core.jobs.setJob(2, 'ambulance', 1)
    Core.jobs.setJobDuty(2, true)

    equalSets(Core.jobs.getPlayersByJobType('leo', true), { 1 }, 'the leaver must be out of the leo set')
    equalSets(Core.jobs.getPlayersByJobType('ems', true), { 2, 3 }, 'and inside the ems set')

    Core.jobs.setJob(2, 'police', 1)
    Core.jobs.setJobDuty(2, true)
end)

h.test('duty counts by type agree with the sets', function()
    h.assertEqual(Core.jobs.getDutyCountByType('leo'), 2, 'two on-duty leo')
    h.assertEqual(Core.jobs.getDutyCountByType('ems'), 1, 'one on-duty ems')
    h.assertEqual(Core.jobs.getDutyCountByType('nonexistent'), 0, 'an unknown type is zero, not an error')
end)

h.test('getJobTypeCounts omits types with nobody in them', function()
    local counts = Core.jobs.getJobTypeCounts(true)

    h.assertEqual(counts.leo, 2, 'two on-duty leo')
    h.assertEqual(counts.ems, 1, 'one on-duty ems')
    h.assertEqual(counts.recovery, 1, 'one on-duty recovery')
    h.assertEqual(counts.leo + counts.ems + counts.recovery, 4, 'the emergency services total four')
    h.assertEqual(counts.nonexistent, nil, 'a type nobody holds must be absent, not zero')
end)

h.test('getOnDutyRoster returns descriptive records, filtered by type', function()
    local roster = Core.jobs.getOnDutyRoster({ jobType = 'leo' })
    h.assertEqual(#roster, 2, 'both on-duty officers')

    local first = roster[1]
    h.assertTrue(first.src == 1 or first.src == 2, 'the record should carry its source')
    h.assertEqual(first.job, 'police', 'job name')
    h.assertEqual(first.jobType, 'leo', 'job type')
    h.assertEqual(first.jobLabel, 'Law Enforcement', 'human-readable job label')
    h.assertTrue(first.name:find('First', 1, true) ~= nil, 'the character name should be composed from charinfo')
    h.assertTrue(first.onDuty, 'an on-duty roster only contains on-duty players')
    h.assertTrue(first.citizenid ~= nil, 'citizenid should be present for MDT lookups')
end)

h.test('getOnDutyRoster narrows by job name, and by both at once', function()
    h.assertEqual(#Core.jobs.getOnDutyRoster({ job = 'ambulance' }), 1, 'one on-duty paramedic')
    h.assertEqual(#Core.jobs.getOnDutyRoster({ job = 'police', jobType = 'leo' }), 2, 'both filters agree')
    h.assertEqual(#Core.jobs.getOnDutyRoster({ job = 'police', jobType = 'ems' }), 0,
        'contradictory filters must intersect, not union')
end)

h.test('getOnDutyRoster with no filter covers every service, not just emergency ones', function()
    local roster = Core.jobs.getOnDutyRoster()

    local byType = {}
    for _, unit in ipairs(roster) do byType[unit.jobType] = (byType[unit.jobType] or 0) + 1 end

    h.assertEqual(byType.leo, 2, 'two on-duty leo')
    h.assertEqual(byType.ems, 1, 'one on-duty ems')
    h.assertEqual(byType.recovery, 1, 'one on-duty recovery -- a non-emergency service is a first-class citizen')
    h.assertEqual(byType.none, 1, "and the untyped worker reads back as 'none'")
end)

h.test('getOnDutyRoster can include off-duty players when asked', function()
    Core.jobs.setJobDuty(2, false)

    h.assertEqual(#Core.jobs.getOnDutyRoster({ job = 'police' }), 1, 'on-duty only by default')
    h.assertEqual(#Core.jobs.getOnDutyRoster({ job = 'police', onDutyOnly = false }), 2, 'both when asked')

    Core.jobs.setJobDuty(2, true)
end)

h.test('a direct setPath duty write is reconciled back into both indexes', function()
    Core.player.setPath(1, { 'job', 'onduty' }, false)

    equalSets(Core.jobs.getPlayersByJob('police', true), { 2 },
        'a raw duty write must still leave the name index correct')
    equalSets(Core.jobs.getPlayersByJobType('leo', true), { 2 },
        'and the type index correct')

    Core.jobs.setJobDuty(1, true)
    equalSets(Core.jobs.getPlayersByJobType('leo', true), { 1, 2 }, 'and recover when duty comes back')
end)

h.test('setJob does not double-handle its own write through the reconciler', function()
    Core.jobs.setJob(1, 'police', 3)

    equalSets(Core.jobs.getPlayersByJob('police'), { 1, 2 }, 'membership must not be duplicated or dropped')
    equalSets(Core.jobs.getPlayersByJobType('leo'), { 1, 2 }, 'nor in the type index')
    h.assertEqual(Core.jobs.getJob(1).grade.level, 3, 'the grade change still applied')
end)

h.test('dropping a player clears them from every index', function()
    local dutyBefore = Core.jobs.getDutyCountByType('leo')
    TriggerEvent('kora_core:server:playerDropped', 2, 'COP2', 'quit')

    h.assertEqual(Core.jobs.getDutyCountByType('leo'), dutyBefore - 1, 'the type duty count should drop')
    equalSets(Core.jobs.getPlayersByJob('police'), { 1 }, 'and the name index should forget them')
    equalSets(Core.jobs.getPlayersByJobType('leo'), { 1 }, 'and the type index too')
end)

h.test('character logout clears every index before a new character loads', function()
    Core.jobs.setJobDuty(1, true)
    loginAs(6, 'COP-SWITCH')
    Core.jobs.setJob(6, 'police', 1)
    Core.jobs.setJobDuty(6, true)
    equalSets(Core.jobs.getPlayersByJob('police', true), { 1, 6 }, 'the old character starts on duty')

    h.assertTrue(Core.player.logout(6), 'character logout succeeds without a disconnect')
    equalSets(Core.jobs.getPlayersByJob('police'), { 1 }, 'logout clears job membership')
    equalSets(Core.jobs.getPlayersByJob('police', true), { 1 }, 'logout clears job duty membership')
    equalSets(Core.jobs.getPlayersByJobType('leo'), { 1 }, 'logout clears type membership')
    equalSets(Core.jobs.getPlayersByJobType('leo', true), { 1 }, 'logout clears type duty membership')
    h.assertEqual(Core.jobs.getDutyCount('police'), 1, 'job duty count excludes the logged-out character')
    h.assertEqual(Core.jobs.getDutyCountByType('leo'), 1, 'type duty count excludes the logged-out character')

    loginAs(6, 'CIV-SWITCH')
    equalSets(Core.jobs.getPlayersByJob('police'), { 1 }, 'the new character does not inherit police membership')
    equalSets(Core.jobs.getPlayersByJobType('leo', true), { 1 }, 'the new character does not inherit leo duty')
    equalSets(Core.jobs.getPlayersByJob('unemployed'), { 6 }, 'load seeds the new character job')
    equalSets(Core.jobs.getPlayersByJob('unemployed', true), { 6 }, 'load seeds the new character duty')

    Core.player.logout(6)
end)

h.test('setGang sets a gang without touching the job indexes', function()
    local jobBefore = #Core.jobs.getPlayersByJob('police')
    local ok = Core.jobs.setGang(1, 'ballas', 1)

    h.assertTrue(ok, 'a registered gang should be accepted')
    h.assertEqual(Core.jobs.getGang(1).name, 'ballas', 'the gang should be set')
    h.assertEqual(#Core.jobs.getPlayersByJob('police'), jobBefore, 'gangs are not indexed with jobs')
end)

h.report('jobs')
