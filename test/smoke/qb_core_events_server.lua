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
dofile('modules/metadata/server.lua')
dofile('modules/permissions/server.lua')
dofile('modules/commands/server.lua')
dofile('compat/shared/coreobject.lua')
dofile('compat/server/qb-core.lua')
dofile('compat/server/qb-core-events.lua')

local data = CoreInternal.player.freshData('CID1', 'license:abc', 1, { firstname = 'A', lastname = 'B' })
Core.player.login(1, 'CID1', data)

h.test('client metadata writes cannot reopen starter entitlements even when allow-listed', function()
    Core.metadata.setMetaData(1, 'starterItems', { phone = false })
    Config.compat.clientMetadataKeys.starterItems = true
    handle.fireEvent('QBCore:Server:SetMetaData', 1, 'starterItems', { phone = true, forged = true })
    Config.compat.clientMetadataKeys.starterItems = nil
    local pending = Core.metadata.getMetaData(1, 'starterItems')
    h.assertEqual(pending.phone, false)
    h.assertEqual(pending.forged, nil)
end)

h.test('ordinary allow-listed metadata writes keep their existing behavior', function()
    Config.compat.clientMetadataKeys.testClientValue = true
    handle.fireEvent('QBCore:Server:SetMetaData', 1, 'testClientValue', 42)
    Config.compat.clientMetadataKeys.testClientValue = nil
    h.assertEqual(Core.metadata.getMetaData(1, 'testClientValue'), 42)
end)

h.test('default client metadata allow-list is hunger/thirst/stress only', function()
    local keys = {}
    for key, allowed in pairs(Config.compat.clientMetadataKeys) do if allowed then keys[#keys + 1] = key end end
    table.sort(keys)
    h.assertEqual(table.concat(keys, ','), 'hunger,stress,thirst')
end)

h.test('client hunger/thirst/stress writes are clamped to 0..100', function()
    handle.fireEvent('QBCore:Server:SetMetaData', 1, 'hunger', 5000)
    h.assertEqual(Core.metadata.getMetaData(1, 'hunger'), 100)
    handle.fireEvent('QBCore:Server:SetMetaData', 1, 'thirst', -20)
    h.assertEqual(Core.metadata.getMetaData(1, 'thirst'), 0)
    handle.fireEvent('QBCore:Server:SetMetaData', 1, 'stress', 42.5)
    h.assertEqual(Core.metadata.getMetaData(1, 'stress'), 42.5)
end)

h.test('client numeric metadata rejects non-numbers and non-finite values', function()
    handle.fireEvent('QBCore:Server:SetMetaData', 1, 'stress', 10)
    for _, bad in ipairs({ 'high', true, {}, 0 / 0, math.huge, -math.huge }) do
        handle.fireEvent('QBCore:Server:SetMetaData', 1, 'stress', bad)
        h.assertEqual(Core.metadata.getMetaData(1, 'stress'), 10)
    end
end)

h.test('sensitive metadata keys are not client-writable by default', function()
    for _, key in ipairs({ 'isdead', 'inlaststand', 'jailitems', 'injail', 'licences', 'criminalrecord',
        'callsign', 'money', 'bloodtype', 'inside' }) do
        Core.metadata.setMetaData(1, key, 'server')
        handle.fireEvent('QBCore:Server:SetMetaData', 1, key, 'client')
        h.assertEqual(Core.metadata.getMetaData(1, key), 'server', key)
    end
end)

local clock = 100000
local realTimer = GetGameTimer
GetGameTimer = function() return clock end

h.test('QBCore:ToggleDuty flips duty for a real job and fires SetDuty events', function()
    h.assertTrue(Core.jobs.setJob(1, 'police', 1))
    Core.jobs.setJobDuty(1, false)
    local fired = 0
    AddEventHandler('QBCore:Server:SetDuty', function() fired = fired + 1 end)
    clock = clock + 5000
    handle.fireEvent('QBCore:ToggleDuty', 1)
    h.assertTrue(Core.jobs.getJob(1).onduty)
    h.assertEqual(fired, 1)
    h.assertTrue(handle.lastClient('QBCore:Client:SetDuty') ~= nil)
end)

h.test('QBCore:ToggleDuty is rate-limited per source', function()
    clock = clock + 5000
    handle.fireEvent('QBCore:ToggleDuty', 1)
    local after = Core.jobs.getJob(1).onduty
    clock = clock + 100
    handle.fireEvent('QBCore:ToggleDuty', 1)
    h.assertEqual(Core.jobs.getJob(1).onduty, after, 'repeat inside the cooldown is dropped')
    clock = clock + 5000
    handle.fireEvent('QBCore:ToggleDuty', 1)
    h.assertEqual(Core.jobs.getJob(1).onduty, not after)
end)

h.test('QBCore:ToggleDuty ignores the default job and unknown sources', function()
    h.assertTrue(Core.jobs.setJob(1, Config.jobs.defaultJob, 1))
    Core.jobs.setJobDuty(1, false)
    clock = clock + 5000
    handle.fireEvent('QBCore:ToggleDuty', 1)
    h.assertFalse(Core.jobs.getJob(1).onduty, 'no real job, no toggle')
    clock = clock + 5000
    handle.fireEvent('QBCore:ToggleDuty', 999)
end)

h.test('QBCore:ToggleDuty can be disabled with Config.compat.toggleDutyEvent', function()
    h.assertTrue(Core.jobs.setJob(1, 'police', 1))
    Core.jobs.setJobDuty(1, false)
    Config.compat.toggleDutyEvent = false
    clock = clock + 5000
    handle.fireEvent('QBCore:ToggleDuty', 1)
    Config.compat.toggleDutyEvent = true
    h.assertFalse(Core.jobs.getJob(1).onduty)
end)
GetGameTimer = realTimer

h.test("chatMessage starting with '/' cancels the event", function()
    local before = handle.cancelEventCount()
    TriggerEvent('chatMessage', 1, 'Player', '/give item')
    h.assertEqual(handle.cancelEventCount(), before + 1, 'a leading / must CancelEvent')
end)

h.test("chatMessage NOT starting with '/' does not cancel the event", function()
    local before = handle.cancelEventCount()
    TriggerEvent('chatMessage', 1, 'Player', 'hello there')
    h.assertEqual(handle.cancelEventCount(), before, 'a normal chat line must not be cancelled')
end)

h.test('QBCore:DebugSomething runs once, then a repeat within 1s is dropped', function()
    local calls = 0
    local realDebug = QBCore.Debug
    QBCore.Debug = function(...) calls = calls + 1 end

    handle.fireEvent('QBCore:DebugSomething', 1, { foo = 'bar' })
    h.assertEqual(calls, 1, 'first call should run')

    handle.fireEvent('QBCore:DebugSomething', 1, { foo = 'bar' })
    h.assertEqual(calls, 1, 'repeat within the 1s cooldown must be dropped')

    QBCore.Debug = realDebug
end)

h.test('QBCore:DebugSomething runs again once the cooldown has elapsed', function()
    local calls = 0
    local realDebug = QBCore.Debug
    QBCore.Debug = function(...) calls = calls + 1 end

    for _ = 1, 70 do GetGameTimer() end

    handle.fireEvent('QBCore:DebugSomething', 1, {})
    h.assertEqual(calls, 1, 'call after the cooldown window should run again')

    QBCore.Debug = realDebug
end)

h.test('kora_core:server:playerDropped clears the debug cooldown entry too (no leak)', function()
    local calls = 0
    local realDebug = QBCore.Debug
    QBCore.Debug = function(...) calls = calls + 1 end

    for _ = 1, 70 do GetGameTimer() end

    handle.fireEvent('QBCore:DebugSomething', 1, {})
    h.assertEqual(calls, 1, 'primes the cooldown')

    TriggerEvent('kora_core:server:playerDropped', 1, 'CID1', 'test')

    handle.fireEvent('QBCore:DebugSomething', 1, {})
    h.assertEqual(calls, 2, 'cooldown must be cleared by playerDropped, not left stale')

    QBCore.Debug = realDebug
end)

h.test('QBCore:CallCommand on an unknown command is a silent no-op', function()
    local before = #handle.clientEvents
    handle.fireEvent('QBCore:CallCommand', 1, 'nosuchcommand', {})
    h.assertEqual(#handle.clientEvents, before, 'unknown command must not notify or otherwise act')
end)

h.test('QBCore:CallCommand denies a caller without the command.<name> ACE', function()
    local ran = false
    QBCore.Commands.Add('secret', 'help', {}, false, function(src, args) ran = true end, 'admin')

    handle.fireEvent('QBCore:CallCommand', 1, 'secret', {})
    h.assertFalse(ran, 'callback must not run without the ACE permission')
end)

h.test('QBCore:CallCommand with argsrequired and too few args notifies and does not run the callback', function()
    local ran = false
    QBCore.Commands.Add('needsargs', 'help', { { name = 'target' } }, true, function(src, args) ran = true end, 'user')
    handle.setAce(1, 'command.needsargs', true)

    local before = #handle.clientEvents
    handle.fireEvent('QBCore:CallCommand', 1, 'needsargs', {})
    h.assertFalse(ran, 'callback must not run when required args are missing')
    h.assertTrue(#handle.clientEvents > before, 'a notify (QBCore:Notify) must fire for missing args')
    local last = handle.lastClient('QBCore:Notify')
    h.assertTrue(last ~= nil, 'the notify must be QBCore:Notify')
end)

h.test('QBCore:CallCommand with sufficient args + ACE calls the callback directly (not ExecuteCommand)', function()
    local ranWith
    QBCore.Commands.Add('needsargs2', 'help', { { name = 'target' } }, true, function(src, args) ranWith = { src = src, args = args } end, 'user')
    handle.setAce(1, 'command.needsargs2', true)

    local beforeExec = #handle.executeCommandCalls
    handle.fireEvent('QBCore:CallCommand', 1, 'needsargs2', { 'someone' })

    h.assertTrue(ranWith ~= nil, 'callback must run when args + ACE are satisfied')
    h.assertEqual(ranWith.src, 1, 'callback must receive the invoking source')
    h.assertEqual(#handle.executeCommandCalls, beforeExec, 'must NEVER go through ExecuteCommand')
end)

h.test('QBCore:CallCommand without argsrequired runs even with zero args', function()
    local ran = false
    QBCore.Commands.Add('noargs', 'help', nil, false, function(src, args) ran = true end, 'user')
    handle.setAce(1, 'command.noargs', true)

    handle.fireEvent('QBCore:CallCommand', 1, 'noargs', {})
    h.assertTrue(ran, 'a command with no argsrequired must run regardless of arg count')
end)

h.test('fireSharedUpdateAtLogin defaults to false: kora_core:server:playerLoaded does not fire QBCore:Client:SharedUpdate', function()
    h.assertEqual(Config.compat.fireSharedUpdateAtLogin, false, 'default must be false')
    local before = #handle.clientEvents
    TriggerEvent('kora_core:server:playerLoaded', 1, 'CID1')
    local fired = false
    for i = before + 1, #handle.clientEvents do
        if handle.clientEvents[i].name == 'QBCore:Client:SharedUpdate' then fired = true end
    end
    h.assertFalse(fired, 'must not fire QBCore:Client:SharedUpdate while the opt-in is off')
end)

h.report('qb_core_events_server')
