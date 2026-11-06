local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local H = require('harness')
local mocks = require('mocks')
mocks.install({ client = true })

-- modules/locales/client.lua reads Config.locales at load; in game config.lua is
-- the first shared_script, so load it the same way here.
dofile(repoRoot .. 'config.lua')

local commands, notices, keyMappings = {}, {}, {}
local selected = 'en'
Kora.locale = {
    getLanguage = function() return selected end,
    getLanguages = function() return { 'de', 'en' } end,
    setLanguage = function(language) selected = language; return true end,
}
Kora.nui = {
    openMenu = function(items, title)
        return { selectedId = items[1].id, title = title }
    end,
}
Kora.notify = { send = function(payload) notices[#notices + 1] = payload end }
_G.RegisterCommand = function(name, handler) commands[name] = handler end
_G.RegisterKeyMapping = function(command, _, _, key) keyMappings[command] = key end

dofile(repoRoot .. 'modules/locales/client.lua')

H.test('registers the player language command', function()
    H.assertTrue(type(commands.language) == 'function')
end)

H.test('selector saves a language through kora_lib rather than PlayerData', function()
    commands.language()
    H.assertEqual(selected, 'de')
    H.assertEqual(notices[#notices].type, 'success')
end)

H.test('the press-only keybind uses the configured default key', function()
    H.assertTrue(type(commands['+language']) == 'function')
    H.assertTrue(type(commands['-language']) == 'function')
    H.assertEqual(keyMappings['+language'], Config.locales.defaultKey)
end)

H.report('locales')
