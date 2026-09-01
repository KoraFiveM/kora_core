local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua')
mocks.install()

local rows = {
    {
        citizenid = 'OWN1', cid = 1, name = 'Test Person',
        charinfo = '{"firstname":"Test"}', money = '{"cash":50}',
        job = '{"name":"police"}', gang = '{"name":"ballas"}',
    },
}
local stored = {
    OWN1 = { citizenid = 'OWN1', license = 'license:owner' },
    OTHER1 = { citizenid = 'OTHER1', license = 'license:someone-else' },
    -- A soft-deleted row is represented exactly as persistence._load does:
    -- absent, because its SQL query requires deleted_at IS NULL.
}

_G.Core = {
    multichar = {},
    identity = { primary = function(src) return src == 1 and 'license:owner' or 'license:other' end },
    persistence = {
        _listCharacters = function(license) return license == 'license:owner' and rows or {} end,
        _load = function(citizenid) return stored[citizenid] end,
        _deleteCharacterRow = function() return true end,
    },
    player = {
        login = function() return true end,
        logout = function() return true end,
        createCharacter = function() return 'CREATED' end,
    },
}
_G.CoreInternal = { player = { byCitizenId = {} } }

dofile('modules/multichar/server.lua')

h.test('character summaries decode gang alongside job and money', function()
    local characters = Core.multichar.getCharacters(1)
    h.assertEqual(characters[1].job.name, 'police')
    h.assertEqual(characters[1].gang.name, 'ballas')
    h.assertEqual(characters[1].money.cash, 50)
end)

h.test('ownsCharacter accepts only an active row under the requesting license', function()
    h.assertTrue(Core.multichar.ownsCharacter(1, 'OWN1'), 'owned active character should pass')
    h.assertFalse(Core.multichar.ownsCharacter(1, 'OTHER1'), 'another license must fail')
    h.assertFalse(Core.multichar.ownsCharacter(1, 'DELETED1'), 'soft-deleted character must fail')
    h.assertFalse(Core.multichar.ownsCharacter(1, ''), 'empty citizen id must fail')
end)

h.report('multichar')
