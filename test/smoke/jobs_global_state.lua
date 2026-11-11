local h = dofile('test/harness.lua')
local handle = dofile('test/mocks.lua').install()
dofile('config.lua')
dofile('shared/items.lua'); dofile('shared/jobs.lua'); dofile('shared/gangs.lua')
dofile('shared/vehicles.lua'); dofile('shared/weapons.lua'); dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua'); dofile('modules/registry/server.lua')
dofile('modules/player/shared.lua')
dofile('modules/replication/server.lua'); dofile('modules/persistence/server.lua')
dofile('modules/player/server.lua')

local PI = CoreInternal.player
local function loginAs(src, name)
    local data = PI.freshData('DUTY' .. src, 'license:duty' .. src, 1, {})
    data.job = PI.buildJob(name, 1)
    data.job.onduty = true
    assert(Core.player.login(src, data.citizenid, data))
end

loginAs(1, 'police')
local verifyThread
local createThread = CreateThread
CreateThread = function(fn) verifyThread = coroutine.create(fn) end
dofile('modules/jobs/server.lua')
CreateThread = createThread

local function stepVerification(expectedDelay)
    local wait = Wait
    Wait = coroutine.yield
    local ok, delay = coroutine.resume(verifyThread)
    Wait = wait
    assert(ok, delay)
    h.assertEqual(delay, expectedDelay, 'verification waits for the expected interval')
end

h.test('startup reconciliation seeds players already online and skips missing handles', function()
    handle.setPlayers({ '1', '999', 'invalid' })
    h.assertEqual(Core.jobs.getDutyCount('police'), 0, 'load event preceded the jobs module')
    stepVerification(2000)
    local previous = GlobalState.OnDuty
    stepVerification(5 * 60 * 1000)
    h.assertEqual(GlobalState.OnDuty, previous, 'rebuild uses the coalesced publication path')
    handle.drainTimeouts()
    h.assertEqual(Core.jobs.getDutyCount('police'), 1, 'startup rebuild seeds the counter')
    h.assertEqual(GlobalState.OnDuty.police, 1, 'job count is published')
    h.assertEqual(GlobalState.OnDuty.leo, 1, 'type count is published')
    local published = GlobalState.OnDuty
    handle.drainTimeouts()
    h.assertEqual(GlobalState.OnDuty, published, 'rebuild leaves no second publication queued')
    Core.player.dropPlayer(1)
    handle.drainTimeouts()
end)

h.test('duty writes publish fresh snapshots and repeated membership changes do not double count', function()
    local previous = GlobalState.OnDuty
    loginAs(2, 'police')
    Core.jobs.setJobDuty(2, true)
    Core.jobs.setJobDuty(2, true)
    h.assertEqual(GlobalState.OnDuty, previous, 'publication waits for the coalesced callback')
    handle.drainTimeouts()
    h.assertTrue(GlobalState.OnDuty ~= previous, 'publication replaces the entire table')
    h.assertEqual(previous.police, nil, 'previous snapshot is not mutated')
    h.assertEqual(GlobalState.OnDuty.police, 1, 'repeated writes count one officer')
    Core.player.setPath(2, { 'job', 'onduty' }, false)
    handle.drainTimeouts()
    h.assertEqual(GlobalState.OnDuty.police or 0, 0, 'direct funnel writes update publication')
    Core.player.dropPlayer(2)
end)

h.test('job changes move published counts between jobs and types', function()
    loginAs(3, 'police')
    handle.drainTimeouts()
    Core.jobs.setJob(3, 'ambulance', 1)
    Core.jobs.setJobDuty(3, true)
    handle.drainTimeouts()
    h.assertEqual(GlobalState.OnDuty.police or 0, 0, 'old job has no on-duty holders')
    h.assertEqual(GlobalState.OnDuty.leo or 0, 0, 'old type has no on-duty holders')
    h.assertEqual(GlobalState.OnDuty.ambulance, 1, 'new job counts the player once')
    h.assertEqual(GlobalState.OnDuty.ems, 1, 'new type counts the player once')
    Core.player.dropPlayer(3)
    handle.drainTimeouts()
end)

h.test('registered job names keep precedence at zero, after logout and after rebuild', function()
    Core.registry.registerShared('jobs', 'ems', {
        name = 'ems', label = 'EMS', type = 'ems', defaultDuty = false,
        grades = { { name = 'Worker', payment = 10 } },
    })
    loginAs(4, 'ambulance')
    handle.drainTimeouts()
    h.assertEqual(GlobalState.OnDuty.ems, 0, 'an unoccupied registered job masks the type total')
    loginAs(5, 'ems')
    handle.drainTimeouts()
    h.assertEqual(GlobalState.OnDuty.ems, 1, 'occupied job overrides the two-person type count')
    Core.jobs.setJobDuty(5, false)
    handle.drainTimeouts()
    h.assertEqual(GlobalState.OnDuty.ems, 0, 'last employee going off duty cannot expose the type total')
    Core.jobs.setJobDuty(5, true)
    Core.player.logout(5)
    handle.drainTimeouts()
    h.assertEqual(GlobalState.OnDuty.ems, 0, 'logout preserves job-name precedence')
    handle.setPlayers({ '4', '5' })
    stepVerification(5 * 60 * 1000)
    handle.drainTimeouts()
    h.assertEqual(GlobalState.OnDuty.ems, 0, 'rebuilding without any job holders preserves precedence')
    h.assertEqual(Core.jobs.getDutyCountByType('ems'), 1, 'server type total remains available')
    Core.player.dropPlayer(4)
    handle.drainTimeouts()
end)

h.test('duplicate unload and drop events clear publication without negative counters', function()
    loginAs(6, 'police')
    handle.drainTimeouts()
    Core.player.dropPlayer(6)
    TriggerEvent('QBCore:Server:OnPlayerUnload', 6)
    TriggerEvent('kora_core:server:playerDropped', 6)
    handle.drainTimeouts()
    h.assertEqual(Core.jobs.getDutyCount('police'), 0, 'duplicate cleanup never decrements twice')
    h.assertEqual(Core.jobs.getDutyCountByType('leo'), 0, 'type cleanup is also idempotent')
    h.assertEqual(GlobalState.OnDuty.police or 0, 0, 'published job count is cleared')
    h.assertEqual(GlobalState.OnDuty.leo or 0, 0, 'published type count is cleared')
end)

h.test('periodic verification repairs direct data drift and clears disconnected players', function()
    loginAs(7, 'police')
    handle.drainTimeouts()
    local job = PI.buildJob('ambulance', 1)
    job.onduty = true
    PI.handle(7).PlayerData.job = job
    handle.setPlayers({ '7' })
    stepVerification(5 * 60 * 1000)
    handle.drainTimeouts()
    h.assertEqual(Core.jobs.getDutyCount('police'), 0, 'stale membership is removed')
    h.assertEqual(Core.jobs.getDutyCount('ambulance'), 1, 'actual job is indexed')
    h.assertEqual(Core.jobs.getPlayersByJob('ambulance', true)[1], 7, 'job roster agrees')
    h.assertEqual(Core.jobs.getPlayersByJobType('ems', true)[1], 7, 'type roster agrees')
    h.assertEqual(GlobalState.OnDuty.ambulance, 1, 'corrected count is published')
    handle.setPlayers({})
    stepVerification(5 * 60 * 1000)
    handle.drainTimeouts()
    h.assertEqual(next(GlobalState.OnDuty), nil, 'an empty rebuild clears stale publication')
    h.assertEqual(Core.jobs.getDutyCountByType('ems'), 0, 'disconnected type count is cleared')
    Core.player.dropPlayer(7)
end)

h.report('jobs_global_state')
