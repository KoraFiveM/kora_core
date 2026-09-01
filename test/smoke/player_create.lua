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
local LIST_SQL = 'SELECT `citizenid`,`cid`,`name`,`charinfo`,`money`,`job`,`gang` FROM `players` WHERE `license` = ? AND `deleted_at` IS NULL ORDER BY `cid`'
local MAXCHAR_SQL = 'SELECT `max_characters` FROM `users` WHERE `license` = ?'

---Fakes N existing character rows (cid 1..n) for the next _listCharacters call.
local function withExistingCount(n)
    local rows = {}
    for cid = 1, n do
        rows[cid] = { citizenid = 'CID' .. cid, cid = cid, name = 'X', charinfo = '{}', money = '{}', job = '{}', gang = '{}' }
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

h.test('new-character insert binds SQL NULL when phone allocation is unavailable', function()
    local data = CoreInternal.player.freshData('CID-no-phone', LICENSE, 1, { firstname = 'No', lastname = 'Phone' })
    local ok, err = Core.persistence._insertNew('CID-no-phone', LICENSE, 1, data)
    h.assertTrue(ok, err)
    h.assertEqual(lastInsertParams()[12], QB.sql.NULL, 'the final placeholder must not be dropped by a trailing Lua nil')
end)

h.test('normalizes identity fields and generates phone server-side', function()
    withExistingCount(0)
    local citizenid, err = Core.player.createCharacter(21, {
        firstname = '  Jane  ', lastname = ' Doe ', birthdate = '2000-02-29',
        gender = 1, nationality = '  Canada ', phone = 'client-controlled', job = 'police',
    })
    h.assertTrue(citizenid ~= nil, err)
    local params = lastInsertParams()
    local charinfo = json.decode(params[6])
    h.assertEqual(charinfo.firstname, 'Jane')
    h.assertEqual(charinfo.lastname, 'Doe')
    h.assertEqual(charinfo.gender, 1)
    h.assertEqual(charinfo.nationality, 'Canada')
    h.assertTrue(charinfo.phone ~= 'client-controlled')
    h.assertEqual(charinfo.job, nil)
end)

h.test('rejects invalid or future birth dates', function()
    withExistingCount(0)
    local citizenid, err = Core.player.createCharacter(22, {
        firstname = 'Jane', lastname = 'Doe', birthdate = '2001-02-29',
    })
    h.assertEqual(citizenid, nil)
    h.assertTrue(type(err) == 'string' and err:find('birth date', 1, true) ~= nil)
    citizenid, err = Core.player.createCharacter(23, {
        firstname = 'Jane', lastname = 'Doe', birthdate = '2099-01-01',
    })
    h.assertEqual(citizenid, nil)
    h.assertTrue(type(err) == 'string' and err:find('birth date', 1, true) ~= nil)
end)

h.test('rejects control characters, unsupported gender, and unbounded nationality', function()
    withExistingCount(0)
    local citizenid = Core.player.createCharacter(24, { firstname = 'Jane\nAdmin', lastname = 'Doe' })
    h.assertEqual(citizenid, nil)
    citizenid = Core.player.createCharacter(25, { firstname = 'Jane', lastname = 'Doe', gender = 9 })
    h.assertEqual(citizenid, nil)
    citizenid = Core.player.createCharacter(26, { firstname = 'Jane', lastname = 'Doe', nationality = 'X' })
    h.assertEqual(citizenid, nil)
end)

h.test('assigns the next free slot when slot 1 is already taken', function()
    withExistingCount(1)
    local citizenid = Core.player.createCharacter(2, { firstname = 'A', lastname = 'B' })
    h.assertTrue(citizenid ~= nil)
    h.assertEqual(lastInsertParams()[3], 2)
end)

h.test('honours an explicit free cid from an admin-style caller', function()
    withExistingCount(1) -- slot 1 taken
    local citizenid = Core.player.createCharacter(3, { firstname = 'A', lastname = 'B' }, 3)
    h.assertTrue(citizenid ~= nil)
    h.assertEqual(lastInsertParams()[3], 3)
end)

h.test('rejects an explicit cid that is already taken', function()
    withExistingCount(1) -- slot 1 taken
    local citizenid, err = Core.player.createCharacter(10, { firstname = 'A', lastname = 'B' }, 1)
    h.assertTrue(citizenid == nil)
    h.assertEqual(err, 'requested character slot is unavailable')
end)

h.test('rejects an explicit cid out of bounds', function()
    withExistingCount(0)
    local citizenid, err = Core.player.createCharacter(11, { firstname = 'A', lastname = 'B' }, 99)
    h.assertTrue(citizenid == nil)
    h.assertEqual(err, 'requested character slot is unavailable')
end)

h.test('rejects creation once the configured limit is reached', function()
    withExistingCount(Config.identity.maxCharacters)
    local citizenid, err = Core.player.createCharacter(12, { firstname = 'A', lastname = 'B' })
    h.assertTrue(citizenid == nil)
    h.assertEqual(err, 'character limit reached')
end)

h.test('a per-license users.max_characters override raises the limit', function()
    handle.sqlResponses.single[MAXCHAR_SQL] = { max_characters = Config.identity.maxCharacters + 1 }
    withExistingCount(Config.identity.maxCharacters) -- at the GLOBAL default, but under the override
    local citizenid, err = Core.player.createCharacter(4, { firstname = 'A', lastname = 'B' })
    h.assertTrue(citizenid ~= nil, err)
    h.assertEqual(lastInsertParams()[3], Config.identity.maxCharacters + 1)
    handle.sqlResponses.single[MAXCHAR_SQL] = nil
end)

h.test('a per-license users.max_characters override can also lower the limit', function()
    handle.sqlResponses.single[MAXCHAR_SQL] = { max_characters = 1 }
    withExistingCount(1)
    local citizenid, err = Core.player.createCharacter(13, { firstname = 'A', lastname = 'B' })
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

h.test('freshData seeds metadata.fingerprint and metadata.walletid, matching real qb-core\'s PlayerDefaults', function()
    -- Real qb-core's config.lua seeds both on every new character
    -- (fingerprint = QBCore.Player.CreateFingerId(), walletid =
    -- QBCore.Player.CreateWalletId()) -- confirmed missing entirely from
    -- this rebuild while auditing real qb-policejob's fingerprint-scan
    -- feature, which reads metadata.fingerprint directly.
    local data = CoreInternal.player.freshData('CID-finger', LICENSE, 1, { firstname = 'Finger', lastname = 'Print' })

    h.assertTrue(type(data.metadata.fingerprint) == 'string' and #data.metadata.fingerprint > 0,
        'metadata.fingerprint must be a non-empty string')
    h.assertTrue(type(data.metadata.walletid) == 'string' and data.metadata.walletid:find('^QB%-'),
        'metadata.walletid must be a non-empty string in the QB-###... shape')

    local other = CoreInternal.player.freshData('CID-finger2', LICENSE, 2, { firstname = 'Finger', lastname = 'Print' })
    h.assertTrue(data.metadata.fingerprint ~= other.metadata.fingerprint,
        'two freshly generated fingerprints should not collide in practice (random, not a hard guarantee)')
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
    -- Legacy mirror: real qb-core sets a bare 'isLoggedIn' key, and legacy
    -- consumers (real qb-doorlock's client.lua gates its entire main loop on
    -- it) read LocalPlayer.state['isLoggedIn'] directly rather than the
    -- namespaced key above. Without this alias they permanently read nil and
    -- behave as though the player never logged in.
    h.assertEqual(handle.playerStates[42]['isLoggedIn'], true, 'login should also replicate the legacy bare isLoggedIn key')

    h.assertTrue(Core.player.logout(42))
    h.assertEqual(handle.playerStates[42]['qbcore:loggedIn'], false, 'logout should replicate qbcore:loggedIn=false')
    h.assertEqual(handle.playerStates[42]['isLoggedIn'], false, 'logout should also clear the legacy bare isLoggedIn key')
end)

h.test('a hard disconnect fires the modern event plus BOTH legacy-named events', function()
    local data = CoreInternal.player.freshData('CID-drop', LICENSE, 1, { firstname = 'Drop', lastname = 'Path' })
    h.assertTrue(Core.player.login(43, 'CID-drop', data))

    local modernFired, legacyDropped, legacyUnload
    local modernArgs, legacyDroppedArgs
    AddEventHandler('qbcore:server:playerDropped', function(src, citizenid, reason)
        modernFired = true
        modernArgs = { src = src, citizenid = citizenid, reason = reason }
    end)
    AddEventHandler('QBCore:Server:PlayerDropped', function(src, reason)
        legacyDropped = true
        legacyDroppedArgs = { src = src, reason = reason }
    end)
    AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
        legacyUnload = true
    end)

    handle.fireEvent('playerDropped', 43, 'reason text')

    h.assertTrue(modernFired, 'the modern qbcore:server:playerDropped event must fire')
    h.assertEqual(modernArgs.src, 43)
    h.assertEqual(modernArgs.citizenid, 'CID-drop')
    h.assertEqual(modernArgs.reason, 'reason text')

    h.assertTrue(legacyDropped, 'QBCore:Server:PlayerDropped must fire on the same disconnect path')
    h.assertEqual(legacyDroppedArgs.src, 43)
    h.assertEqual(legacyDroppedArgs.reason, 'reason text', 'the disconnect reason must be forwarded')

    h.assertTrue(legacyUnload, 'QBCore:Server:OnPlayerUnload must fire on the same disconnect path')
end)

h.report('player_create')
