-- Core.dispatch smoke test -- job-filtered fan-out + legacy compat events.
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
dofile('modules/dispatch/server.lua')

local function loginAs(src, cid)
    local data = CoreInternal.player.freshData(cid, 'license:' .. cid, 1, { firstname = 'A', lastname = 'B' })
    Core.player.login(src, cid, data)
end

loginAs(1, 'COP1')
loginAs(2, 'COP2')
loginAs(3, 'EMS1')
loginAs(4, 'CIV1')

Core.jobs.setJob(1, 'police', 1)
Core.jobs.setJobDuty(1, true)
Core.jobs.setJob(2, 'police', 1)
Core.jobs.setJobDuty(2, false) -- off duty, should NOT receive the alert
Core.jobs.setJob(3, 'ambulance', 1)
Core.jobs.setJobDuty(3, true)

local function eventsFor(name)
    local out = {}
    for _, e in ipairs(handle.clientEvents) do if e.name == name then out[#out + 1] = e end end
    return out
end

h.test('alert reaches only on-duty members of the requested job(s)', function()
    local count = Core.dispatch.alert({ jobs = { 'police' }, title = 'Robbery', message = '10-90 in progress' })
    h.assertEqual(count, 1, 'only the one on-duty cop should be notified')

    local hits = eventsFor('qbcore:client:dispatchAlert')
    h.assertEqual(#hits, 1, 'exactly one dispatchAlert should have been sent')
    h.assertEqual(hits[1].target, 1, 'it should be addressed to the on-duty cop')
    h.assertEqual(hits[1].args[1].title, 'Robbery', 'the payload should be forwarded intact')
end)

h.test('alert fans out across multiple requested jobs, deduplicated', function()
    local count = Core.dispatch.alert({ jobs = { 'police', 'ambulance' }, message = 'multi-job incident' })
    h.assertEqual(count, 2, 'one on-duty cop plus one on-duty EMS')
end)

h.test('legacy police compat events fire alongside the modern alert', function()
    local localFired = false
    handle.eventHandlers['police:server:policeAlert'] = handle.eventHandlers['police:server:policeAlert'] or {}
    table.insert(handle.eventHandlers['police:server:policeAlert'], function() localFired = true end)

    local before = #eventsFor('police:client:policeAlert')
    Core.dispatch.alert({ jobs = { 'police' }, message = 'legacy check' })

    h.assertTrue(localFired, 'the local police:server:policeAlert TriggerEvent should have fired')
    h.assertTrue(#eventsFor('police:client:policeAlert') > before, 'police:client:policeAlert should have reached the on-duty cop')
end)

h.test('legacy ambulance compat event fires for an ambulance/ems alert', function()
    local before = #eventsFor('hospital:client:ambulanceAlert')
    Core.dispatch.alert({ jobs = { 'ambulance' }, message = 'legacy ems check' })
    h.assertTrue(#eventsFor('hospital:client:ambulanceAlert') > before, 'hospital:client:ambulanceAlert should have fired for the on-duty EMS')
end)

h.test('legacy events are suppressed when Config.dispatch.legacyEvents is false', function()
    Config.dispatch.legacyEvents = false
    local before = #eventsFor('police:client:policeAlert')
    Core.dispatch.alert({ jobs = { 'police' }, message = 'no legacy this time' })
    h.assertEqual(#eventsFor('police:client:policeAlert'), before, 'no additional legacy event should have fired')
    Config.dispatch.legacyEvents = true
end)

h.test('alert requires a non-empty jobs array', function()
    local ok = pcall(Core.dispatch.alert, { jobs = {} })
    h.assertFalse(ok, 'an empty jobs array should be rejected')
end)

h.report('dispatch')
