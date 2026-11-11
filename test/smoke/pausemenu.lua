local H = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua')
mocks.install({ client = true })

Config = nil
dofile('config.lua')

local entries = {}
_G.AddTextEntry = function(key, value)
    entries[key] = value
end

dofile('modules/pausemenu/client.lua')

H.test('registers the configured server name as the native pause-menu title', function()
    H.assertEqual(entries.FE_THDR_GTAO, Config.server.name)
end)

H.test('an empty configured name leaves the native title unchanged', function()
    entries = {}
    Config.server.name = ''
    dofile('modules/pausemenu/client.lua')
    H.assertEqual(entries.FE_THDR_GTAO, nil)
end)

H.report('pausemenu')
