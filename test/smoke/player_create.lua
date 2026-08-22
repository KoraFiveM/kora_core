-- Core.player.createCharacter smoke test: per-license character-slot limit
-- enforcement (Core.users.getMaxCharacters) and authoritative slot
-- assignment -- a client-supplied cid must never bypass the limit or collide
-- with an existing slot. Server realm (identity + users + player).

local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua')
local handle = mocks.install()

-- Core.identity.primary needs real identifier natives; no existing smoke
-- test exercises identity, so these are defined locally here rather than in
-- the shared mocks (every source resolves to the same fixed license, which
-- is all this test needs).
_G.GetNumPlayerIdentifiers = function() return 1 end
_G.GetPlayerIdentifier = function() return 'license:test-license' end
_G.GetPlayerEndpoint = function() return '127.0.0.1' end

dofile('config.lua')
dofile('shared/items.lua'); dofile('shared/jobs.lua'); dofile('shared/gangs.lua')
dofile('shared/vehicles.lua'); dofile('shared/weapons.lua'); dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua'); dofile('modules/registry/server.lua')
dofile('modules/identity/server.lua')
dofile('modules/users/server.lua')
dofile('modules/player/shared.lua')
dofile('modules/replication/server.lua')
dofile('modules/persistence/server.lua')
dofile('modules/player/server.lua')

local LICENSE = 'test-license'
local LIST_SQL = 'SELECT `citizenid`,`cid`,`name`,`charinfo`,`money`,`job` FROM `players` WHERE `license` = ? AND `deleted_at` IS NULL ORDER BY `cid`'
local MAXCHAR_SQL = 'SELECT `max_characters` FROM `users` WHERE `license` = ?'

---Fakes N existing character rows (cid 1..n) for the next _listCharacters call.
local function withExistingCount(n)
    local rows = {}
    for cid = 1, n do
        rows[cid] = { citizenid = 'CID' .. cid, cid = cid, name = 'X', charinfo = '{}', money = '{}', job = '{}' }
    end
    handle.sqlResponses.query[LIST_SQL] = rows
end

local function lastInsertParams()
    local calls = handle.sqlCalls.execute
    return calls[#calls].params
end

h.test('creates the first character in slot 1 with no cid given', function()
    withExistingCount(0)
    local citizenid, err = Core.player.createCharacter(1, { firstname = 'A', lastname = 'B' })
    h.assertTrue(citizenid ~= nil, err)
    h.assertEqual(lastInsertParams()[3], 1, 'cid should be the third bound param')
end)

h.test('assigns the next free slot when slot 1 is already taken', function()
    withExistingCount(1)
    local citizenid = Core.player.createCharacter(1, { firstname = 'A', lastname = 'B' })
    h.assertTrue(citizenid ~= nil)
    h.assertEqual(lastInsertParams()[3], 2)
end)

h.test('honours an explicit free cid from an admin-style caller', function()
    withExistingCount(1) -- slot 1 taken
    local citizenid = Core.player.createCharacter(1, { firstname = 'A', lastname = 'B' }, 3)
    h.assertTrue(citizenid ~= nil)
    h.assertEqual(lastInsertParams()[3], 3)
end)

h.test('rejects an explicit cid that is already taken', function()
    withExistingCount(1) -- slot 1 taken
    local citizenid, err = Core.player.createCharacter(1, { firstname = 'A', lastname = 'B' }, 1)
    h.assertTrue(citizenid == nil)
    h.assertEqual(err, 'requested character slot is unavailable')
end)

h.test('rejects an explicit cid out of bounds', function()
    withExistingCount(0)
    local citizenid, err = Core.player.createCharacter(1, { firstname = 'A', lastname = 'B' }, 99)
    h.assertTrue(citizenid == nil)
    h.assertEqual(err, 'requested character slot is unavailable')
end)

h.test('rejects creation once the configured limit is reached', function()
    withExistingCount(Config.identity.maxCharacters)
    local citizenid, err = Core.player.createCharacter(1, { firstname = 'A', lastname = 'B' })
    h.assertTrue(citizenid == nil)
    h.assertEqual(err, 'character limit reached')
end)

h.test('a per-license users.max_characters override raises the limit', function()
    handle.sqlResponses.single[MAXCHAR_SQL] = { max_characters = Config.identity.maxCharacters + 1 }
    withExistingCount(Config.identity.maxCharacters) -- at the GLOBAL default, but under the override
    local citizenid, err = Core.player.createCharacter(1, { firstname = 'A', lastname = 'B' })
    h.assertTrue(citizenid ~= nil, err)
    h.assertEqual(lastInsertParams()[3], Config.identity.maxCharacters + 1)
    handle.sqlResponses.single[MAXCHAR_SQL] = nil
end)

h.test('a per-license users.max_characters override can also lower the limit', function()
    handle.sqlResponses.single[MAXCHAR_SQL] = { max_characters = 1 }
    withExistingCount(1)
    local citizenid, err = Core.player.createCharacter(1, { firstname = 'A', lastname = 'B' })
    h.assertTrue(citizenid == nil)
    h.assertEqual(err, 'character limit reached')
    handle.sqlResponses.single[MAXCHAR_SQL] = nil
end)

h.test('getMaxCharacters ensures a users row exists on first read', function()
    handle.sqlResponses.single[MAXCHAR_SQL] = nil
    local before = #handle.sqlCalls.execute
    local result = Core.users.getMaxCharacters(LICENSE)
    h.assertEqual(result, Config.identity.maxCharacters)
    h.assertTrue(#handle.sqlCalls.execute > before, 'expected an INSERT IGNORE ensuring the users row')
end)

h.test('setMaxCharacters issues an upsert with the license and value', function()
    Core.users.setMaxCharacters(LICENSE, 8)
    local call = handle.sqlCalls.execute[#handle.sqlCalls.execute]
    h.assertTrue(call.sql:find('ON DUPLICATE KEY UPDATE', 1, true) ~= nil)
    h.assertEqual(call.params[1], LICENSE)
    h.assertEqual(call.params[2], 8)
end)

h.test('the replicated login state bag follows the initial player snapshot and clears on logout', function()
    local start = #handle.lifecycleTrace
    local data = CoreInternal.player.freshData('CID-state', LICENSE, 1, { firstname = 'State', lastname = 'Bag' })
    h.assertTrue(Core.player.login(42, 'CID-state', data))

    local snapshotIndex, loginStateIndex
    for index = start + 1, #handle.lifecycleTrace do
        local entry = handle.lifecycleTrace[index]
        if entry.kind == 'client' and entry.name == 'qbcore:rep:snapshot' and entry.target == 42 then snapshotIndex = index end
        if entry.kind == 'state' and entry.source == 42 and entry.key == 'qbcore:loggedIn' and entry.value == true then loginStateIndex = index end
    end
    h.assertTrue(snapshotIndex ~= nil, 'login should send the initial PlayerData snapshot')
    h.assertTrue(loginStateIndex ~= nil, 'login should replicate qbcore:loggedIn=true')
    h.assertTrue(loginStateIndex > snapshotIndex, 'login state must follow the initial snapshot')
    h.assertEqual(handle.playerStates[42]['qbcore:loggedIn'], true, 'Player state should expose logged-in status')

    h.assertTrue(Core.player.logout(42))
    h.assertEqual(handle.playerStates[42]['qbcore:loggedIn'], false, 'logout should replicate qbcore:loggedIn=false')
end)

h.report('player_create')
