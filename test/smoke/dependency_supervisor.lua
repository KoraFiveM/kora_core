-- dependencySupervisor smoke test -- enabled gating, restart-on-provider-start,
-- per-resource cooldown, "not currently started" skip, and "provider not in
-- map" no-op. Server realm.

local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua')
local handle = mocks.install()

dofile('config.lua')
dofile('modules/dependencySupervisor/server.lua')

local function restartCallsFor(resource)
    local n = 0
    for _, cmd in ipairs(handle.executeCommandCalls) do
        if cmd == ('restart %s'):format(resource) then n = n + 1 end
    end
    return n
end

h.test('enabled + mapped provider restarts a currently-started dependent', function()
    Config.dependencySupervisor.enabled = true
    Config.dependencySupervisor.map = { qbinventory = { 'qb-banking' } }
    Config.dependencySupervisor.cooldownMs = 15000
    handle.resourceStates['qb-banking'] = 'started'

    TriggerEvent('onResourceStart', 'qbinventory')

    h.assertEqual(restartCallsFor('qb-banking'), 1, 'qb-banking restarted exactly once')
end)

h.test('cooldown blocks a second restart of the same resource in quick succession', function()
    -- A resource name unused by any earlier test, so its cooldown state
    -- starts fresh regardless of test order within this file.
    Config.dependencySupervisor.enabled = true
    Config.dependencySupervisor.map = { qbtarget = { 'qb-test-dependent' } }
    Config.dependencySupervisor.cooldownMs = 15000
    handle.resourceStates['qb-test-dependent'] = 'started'

    TriggerEvent('onResourceStart', 'qbtarget')
    TriggerEvent('onResourceStart', 'qbtarget')

    h.assertEqual(restartCallsFor('qb-test-dependent'), 1, 'only one restart issued across two rapid triggers')
end)

h.test('a dependent that is not currently started is never restarted', function()
    Config.dependencySupervisor.enabled = true
    Config.dependencySupervisor.map = { qbinventory = { 'qb-test-stopped' } }
    Config.dependencySupervisor.cooldownMs = 15000
    handle.resourceStates['qb-test-stopped'] = 'stopped'

    local before = restartCallsFor('qb-test-stopped')
    TriggerEvent('onResourceStart', 'qbinventory')
    local after = restartCallsFor('qb-test-stopped')

    h.assertEqual(after - before, 0, 'not-started dependent left alone')
end)

h.test('disabled supervisor never restarts anything', function()
    -- Fresh dependent name, never touched by an earlier test in this file --
    -- otherwise a leftover cooldown from an earlier restart could mask a
    -- broken enabled-check (it would block the restart for the wrong reason).
    Config.dependencySupervisor.enabled = false
    Config.dependencySupervisor.map = { qbinventory = { 'qb-disabled-check-dep' } }
    Config.dependencySupervisor.cooldownMs = 15000
    handle.resourceStates['qb-disabled-check-dep'] = 'started'

    TriggerEvent('onResourceStart', 'qbinventory')

    h.assertEqual(restartCallsFor('qb-disabled-check-dep'), 0, 'no ExecuteCommand calls while disabled')
end)

h.test('a provider not present in the map triggers nothing', function()
    -- Also a fresh dependent name for the same reason as above.
    Config.dependencySupervisor.enabled = true
    Config.dependencySupervisor.map = { qbinventory = { 'qb-unmapped-check-dep' } }
    Config.dependencySupervisor.cooldownMs = 15000
    handle.resourceStates['qb-unmapped-check-dep'] = 'started'

    TriggerEvent('onResourceStart', 'some-other-resource')

    h.assertEqual(restartCallsFor('qb-unmapped-check-dep'), 0, 'unmapped provider is a no-op')
end)

h.report('dependencySupervisor')
