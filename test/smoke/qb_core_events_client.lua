local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install({ client = true })
dofile('config.lua')
dofile('modules/util/shared.lua')
dofile('compat/shared/coreobject.lua')
dofile('compat/client/qb-core-events.lua')

h.test('QBCore:Client:PvpHasToggled(true) calls SetCanAttackFriendly and NetworkSetFriendlyFireOption', function()
    handle.pvpNativeCalls = handle.pvpNativeCalls
    local before = #handle.pvpNativeCalls
    TriggerEvent('QBCore:Client:PvpHasToggled', true)

    local calls = {}
    for i = before + 1, #handle.pvpNativeCalls do calls[#calls + 1] = handle.pvpNativeCalls[i] end
    h.assertEqual(#calls, 2, 'must call exactly the two natives')

    h.assertEqual(calls[1].fn, 'SetCanAttackFriendly', 'first native must be SetCanAttackFriendly')
    h.assertEqual(calls[1].ped, 100, 'must pass PlayerPedId()')
    h.assertEqual(calls[1].toggle, true, 'must pass the enabled flag through')
    h.assertEqual(calls[1].arg3, false, 'third arg must be false, matching upstream')

    h.assertEqual(calls[2].fn, 'NetworkSetFriendlyFireOption', 'second native must be NetworkSetFriendlyFireOption')
    h.assertEqual(calls[2].toggle, true, 'must pass the enabled flag through')
end)

h.test('QBCore:Client:PvpHasToggled(false) passes false through to both natives', function()
    local before = #handle.pvpNativeCalls
    TriggerEvent('QBCore:Client:PvpHasToggled', false)

    local calls = {}
    for i = before + 1, #handle.pvpNativeCalls do calls[#calls + 1] = handle.pvpNativeCalls[i] end
    h.assertEqual(calls[1].toggle, false, 'SetCanAttackFriendly must receive false')
    h.assertEqual(calls[2].toggle, false, 'NetworkSetFriendlyFireOption must receive false')
end)

h.test('QBCore:Client:SharedUpdate is registered and does not error (no-op body)', function()
    local ok = pcall(TriggerEvent, 'QBCore:Client:SharedUpdate', QBCore.Shared)
    h.assertTrue(ok, 'firing the event must not error even though the body is a no-op')
end)

h.test('qb-core drawtext event aliases forward to the matching prompt exports', function()
    local calls = {}
    CoreInternal.compat = {
        drawText = function(text, position) calls[#calls + 1] = { 'DrawText', text, position } end,
        changeText = function(text, position) calls[#calls + 1] = { 'ChangeText', text, position } end,
        hideText = function() calls[#calls + 1] = { 'HideText' } end,
        keyPressed = function() calls[#calls + 1] = { 'KeyPressed' } end,
    }
    TriggerEvent('qb-core:client:DrawText', 'Open bank', 'left')
    TriggerEvent('qb-core:client:ChangeText', 'Close bank', 'right')
    TriggerEvent('qb-core:client:HideText')
    TriggerEvent('qb-core:client:KeyPressed')
    h.assertEqual(calls[1][1], 'DrawText')
    h.assertEqual(calls[1][2], 'Open bank')
    h.assertEqual(calls[2][1], 'ChangeText')
    h.assertEqual(calls[3][1], 'HideText')
    h.assertEqual(calls[4][1], 'KeyPressed')
end)

h.report('qb_core_events_client')
