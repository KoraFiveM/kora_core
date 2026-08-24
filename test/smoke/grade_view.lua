-- Pins the legacy zero-based grade VIEW (Track 1 of the qb-core drag-and-drop
-- compat work). Internal grade numbering stays ONE-based throughout qbcore
-- (registry, persistence, replication, our own qb* resources) -- per an
-- explicit decision, nothing internal is renumbered. Only the legacy
-- QBCore.* surface and QBCore:*-named event payloads present real qb-core's
-- ZERO-based grade.level. See compat/shared/coreobject.lua's
-- toLegacyPlayerData/toLegacyJobOrGang and Core.player.setPath's
-- onPlayerDataChanged hook (modules/player/server.lua).
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua')
local handle = mocks.install()

dofile('config.lua')
dofile('shared/items.lua'); dofile('shared/jobs.lua'); dofile('shared/gangs.lua')
dofile('shared/vehicles.lua'); dofile('shared/weapons.lua'); dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua'); dofile('modules/registry/server.lua')
dofile('modules/player/shared.lua')
dofile('modules/replication/server.lua')
dofile('modules/persistence/server.lua')
dofile('modules/player/server.lua')
dofile('modules/money/server.lua')
dofile('modules/jobs/server.lua')
dofile('modules/metadata/server.lua')
dofile('modules/inventory/shared.lua'); dofile('modules/inventory/server.lua')
dofile('modules/inventory/gateway.lua')
dofile('modules/multichar/server.lua')
dofile('modules/permissions/server.lua')
dofile('modules/commands/server.lua')
dofile('modules/logging/server.lua')
dofile('compat/shared/coreobject.lua')
dofile('compat/server/qb-core.lua')

local data = CoreInternal.player.freshData('CID1', 'license:abc', 1, { firstname = 'A', lastname = 'B' })
Core.player.login(1, 'CID1', data)

-- police has 5 seed grades (shared/jobs.lua): internal 1..5 = Cadet..Chief,
-- legacy 0..4 = the same records. Internal grade 3 = Sergeant = legacy 2.
Core.jobs.setJob(1, 'police', 3)

h.test('the legacy PlayerData view exposes a zero-based grade.level', function()
    local Player = QBCore.Functions.GetPlayer(1)
    h.assertEqual(Player.PlayerData.job.grade.level, 2, 'internal grade 3 (Sergeant) must present as legacy level 2')
    h.assertEqual(Player.PlayerData.job.grade.name, 'Sergeant', 'grade name is untouched by translation')
end)

h.test('the legacy view and QBCore.Shared.Jobs grades agree on the same record', function()
    local Player = QBCore.Functions.GetPlayer(1)
    local level = Player.PlayerData.job.grade.level
    local sharedGrade = QBCore.Shared.Jobs.police.grades[tostring(level)]
    h.assertTrue(sharedGrade ~= nil, 'Shared.Jobs.police.grades[tostring(level)] must resolve')
    h.assertEqual(sharedGrade.name, 'Sergeant', 'the idiomatic legacy read Jobs[name].grades[tostring(level)] must hit the SAME grade the player is on')
end)

h.test('the modern internal surface is untouched by the legacy view', function()
    h.assertEqual(Core.jobs.getJob(1).grade.level, 3, 'internal grade.level stays one-based')
end)

h.test('a legacy SetJob(name, zeroBasedLevel) call lands on the correct internal grade', function()
    local Player = QBCore.Functions.GetPlayer(1)
    -- Legacy level 4 = Chief (the top grade, internal index 5).
    local ok = Player.Functions.SetJob('police', 4)
    h.assertTrue(ok, 'SetJob must succeed')
    h.assertEqual(Core.jobs.getJob(1).grade.level, 5, 'internal grade must be 5 (Chief), not 4')
    h.assertEqual(Player.PlayerData.job.grade.level, 4, 'the legacy view must read back the same level that was set')
    h.assertEqual(Player.PlayerData.job.grade.name, 'Chief')
    h.assertTrue(Player.PlayerData.job.isboss, 'isboss (a job-level field) must survive the shallow copy untouched')
end)

h.test('QBCore:Server:OnJobUpdate fires with a legacy-shaped (zero-based) payload', function()
    local captured
    AddEventHandler('QBCore:Server:OnJobUpdate', function(src, job) captured = job end)
    Core.jobs.setJob(1, 'police', 2) -- internal grade 2 = Officer = legacy level 1
    h.assertTrue(captured ~= nil, 'the event must fire')
    h.assertEqual(captured.grade.level, 1, 'the event payload must already be legacy-shaped')
    h.assertEqual(captured.grade.name, 'Officer')
end)

h.test('the legacy view stays live for non-job fields (money) after job changes', function()
    local Player = QBCore.Functions.GetPlayer(1)
    local before = Player.PlayerData.money.cash
    Core.money.addMoney(1, 'cash', 500, 'test')
    h.assertEqual(Player.PlayerData.money.cash, before + 500,
        'the SAME cached Player object must reflect a later money change -- proves the view is kept in sync, not a one-shot snapshot')
end)

h.test('SetJobDuty toggling onduty is reflected in the legacy view (a sub-field patch, not a whole-job replace)', function()
    local Player = QBCore.Functions.GetPlayer(1)
    Core.jobs.setJobDuty(1, true)
    h.assertEqual(Player.PlayerData.job.onduty, true, 'onduty must propagate through the same incremental-sync path as full job replacement')
    Core.jobs.setJobDuty(1, false)
    h.assertEqual(Player.PlayerData.job.onduty, false)
end)

h.test('F.GetPlayerData() also returns a translated, independent snapshot', function()
    local Player = QBCore.Functions.GetPlayer(1)
    local snapshot = Player.Functions.GetPlayerData()
    h.assertEqual(snapshot.job.grade.level, Player.PlayerData.job.grade.level, 'GetPlayerData must agree with the PlayerData field')
    snapshot.job.grade.level = 999
    h.assertTrue(Player.PlayerData.job.grade.level ~= 999, 'the snapshot must be independent -- mutating it must not corrupt the live view')
end)

h.report('grade_view')
