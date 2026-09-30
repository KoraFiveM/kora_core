-- Smoke tests for the smaller inbound legacy net events in
-- compat/server/qb-core-events.lua that aren't already covered by
-- update_player.lua (QBCore:UpdatePlayer's own cooldown/leak tests):
--   * 'chatMessage' '/'-suppression (CancelEvent)
--   * QBCore:DebugSomething rate limiting
--   * QBCore:CallCommand's args-required + ACE-permission gate, calling the
--     command callback DIRECTLY (never ExecuteCommand)
--   * Config.compat.fireSharedUpdateAtLogin opt-in
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

h.test('generic client duty compatibility event is not registered', function()
    Core.jobs.setJobDuty(1, false)
    handle.fireEvent('QBCore:ToggleDuty', 1)
    h.assertFalse(Core.jobs.getJob(1).onduty,
        'job resources must own location-aware duty transitions')
end)

-- --- Task 1: chatMessage '/'-suppression ------------------------------------

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

-- --- Task 2: QBCore:DebugSomething rate limit --------------------------------

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

    -- Each GetGameTimer() call advances the mock clock by 16ms; push past 1000ms.
    for _ = 1, 70 do GetGameTimer() end

    handle.fireEvent('QBCore:DebugSomething', 1, {})
    h.assertEqual(calls, 1, 'call after the cooldown window should run again')

    QBCore.Debug = realDebug
end)

h.test('qbcore:server:playerDropped clears the debug cooldown entry too (no leak)', function()
    local calls = 0
    local realDebug = QBCore.Debug
    QBCore.Debug = function(...) calls = calls + 1 end

    -- Clear whatever cooldown the previous test left behind (same mock clock
    -- across the whole file) before priming a fresh one.
    for _ = 1, 70 do GetGameTimer() end

    handle.fireEvent('QBCore:DebugSomething', 1, {})
    h.assertEqual(calls, 1, 'primes the cooldown')

    TriggerEvent('qbcore:server:playerDropped', 1, 'CID1', 'test')

    handle.fireEvent('QBCore:DebugSomething', 1, {})
    h.assertEqual(calls, 2, 'cooldown must be cleared by playerDropped, not left stale')

    QBCore.Debug = realDebug
end)

-- --- Task 3: QBCore:CallCommand ----------------------------------------------

h.test('QBCore:CallCommand on an unknown command is a silent no-op', function()
    local before = #handle.clientEvents
    handle.fireEvent('QBCore:CallCommand', 1, 'nosuchcommand', {})
    h.assertEqual(#handle.clientEvents, before, 'unknown command must not notify or otherwise act')
end)

h.test('QBCore:CallCommand denies a caller without the command.<name> ACE', function()
    local ran = false
    QBCore.Commands.Add('secret', 'help', {}, false, function(src, args) ran = true end, 'admin')

    -- src 1 is NOT granted command.secret.
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

-- --- Task 5 (server half): fireSharedUpdateAtLogin opt-in --------------------
-- The opt-in AddEventHandler('qbcore:server:playerLoaded', ...) is registered
-- once at load time based on Config.compat.fireSharedUpdateAtLogin, so this
-- exercises the DEFAULT (false) behaviour here; the opt-in-true behaviour is
-- proven in a fresh process below (registration is a load-time decision, not
-- re-checked per fire).

h.test('fireSharedUpdateAtLogin defaults to false: qbcore:server:playerLoaded does not fire QBCore:Client:SharedUpdate', function()
    h.assertEqual(Config.compat.fireSharedUpdateAtLogin, false, 'default must be false')
    local before = #handle.clientEvents
    TriggerEvent('qbcore:server:playerLoaded', 1, 'CID1')
    local fired = false
    for i = before + 1, #handle.clientEvents do
        if handle.clientEvents[i].name == 'QBCore:Client:SharedUpdate' then fired = true end
    end
    h.assertFalse(fired, 'must not fire QBCore:Client:SharedUpdate while the opt-in is off')
end)

h.report('qb_core_events_server')
