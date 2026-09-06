local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local H = require('harness')
local mocks = require('mocks')
mocks.install({ client = true })

local commands, notices = {}, {}
local selected = 'en'
QB.locale = {
    getLanguage = function() return selected end,
    getLanguages = function() return { 'de', 'en' } end,
    setLanguage = function(language) selected = language; return true end,
}
QB.nui = {
    openMenu = function(items, title)
        return { selectedId = items[1].id, title = title }
    end,
}
QB.notify = { send = function(payload) notices[#notices + 1] = payload end }
_G.RegisterCommand = function(name, handler) commands[name] = handler end
_G.RegisterKeyMapping = function() end

dofile(repoRoot .. 'modules/locales/client.lua')

H.test('registers the player language command', function()
    H.assertTrue(type(commands.language) == 'function')
end)

H.test('selector saves a language through qblib rather than PlayerData', function()
    commands.language()
    H.assertEqual(selected, 'de')
    H.assertEqual(notices[#notices].type, 'success')
end)

H.report('locales')
