local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('shared/items.lua'); dofile('shared/jobs.lua'); dofile('shared/gangs.lua')
dofile('shared/vehicles.lua'); dofile('shared/weapons.lua'); dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua'); dofile('modules/registry/server.lua')
dofile('modules/player/shared.lua')
dofile('modules/replication/server.lua'); dofile('modules/persistence/server.lua')
dofile('modules/player/server.lua'); dofile('modules/money/server.lua')
dofile('modules/jobs/server.lua'); dofile('modules/metadata/server.lua')
dofile('modules/inventory/shared.lua'); dofile('modules/inventory/server.lua')
dofile('modules/inventory/gateway.lua')
dofile('modules/multichar/server.lua'); dofile('modules/permissions/server.lua')
dofile('modules/commands/server.lua'); dofile('modules/logging/server.lua')
dofile('compat/shared/coreobject.lua')
dofile('compat/server/qb-core.lua')

local data = CoreInternal.player.freshData('PD1', 'license:pd1', 1, { firstname = 'A', lastname = 'B' })
data.metadata.licences = { driver = false, weapon = true }
assert(Core.player.login(1, 'PD1', data))
local p = QBCore.Functions.GetPlayer(1)

h.test('stock metadata defaults are filled for a native character', function()
    local m = p.PlayerData.metadata
    h.assertEqual(m.criminalrecord.hasRecord, false)
    h.assertEqual(m.callsign, 'NO CALLSIGN')
    h.assertEqual(m.tracker, false)
    h.assertEqual(type(m.status), 'table'); h.assertEqual(type(m.jailitems), 'table'); h.assertEqual(type(m.rep), 'table')
    h.assertEqual(type(m.inside.apartment), 'table')
    h.assertEqual(type(m.phonedata.InstalledApps), 'table')
    h.assertEqual(#m.phonedata.SerialNumber, 9)
    h.assertEqual(m.licences.business, false, 'missing licence key is filled')
end)

h.test('existing metadata values are never overwritten', function()
    local m = p.PlayerData.metadata
    h.assertEqual(m.licences.driver, false)
    h.assertEqual(m.licences.weapon, true)
    h.assertEqual(m.hunger, 100)
    h.assertEqual(m.bloodtype, 'O+')
end)

h.test('defaults are view-only: authoritative metadata and dirty set are untouched', function()
    local raw = Core.player.getPlayerData(1, { 'metadata' })
    h.assertEqual(raw.criminalrecord, nil)
    h.assertEqual(raw.phonedata, nil)
end)

h.test('serial number is stable across reads', function()
    h.assertEqual(p.Functions.GetPlayerData().metadata.phonedata.SerialNumber, p.PlayerData.metadata.phonedata.SerialNumber)
end)

h.test('SetMetaData keeps defaults and the written value', function()
    h.assertTrue(p.Functions.SetMetaData('callsign', 'ALPHA'))
    h.assertEqual(p.PlayerData.metadata.callsign, 'ALPHA')
    h.assertEqual(p.PlayerData.metadata.criminalrecord.hasRecord, false)
end)

h.test('job.grade carries payment and isboss from the job definition', function()
    h.assertTrue(p.Functions.SetJob('police', 2))
    local job = QBCore.Functions.GetPlayer(1).PlayerData.job
    h.assertEqual(job.name, 'police')
    h.assertEqual(job.grade.level, 2)
    h.assertEqual(job.grade.payment, QBCoreSeed.jobs[2].grades[3].payment)
    h.assertEqual(job.grade.isboss, false)
    local top = #QBCoreSeed.jobs[2].grades
    h.assertTrue(p.Functions.SetJob('police', top - 1))
    h.assertEqual(QBCore.Functions.GetPlayer(1).PlayerData.job.grade.isboss, QBCoreSeed.jobs[2].grades[top].isboss or false)
end)

h.test('SetJob and SetGang lower-case the name like stock', function()
    h.assertTrue(p.Functions.SetJob('POLICE', 0))
    h.assertEqual(QBCore.Functions.GetPlayer(1).PlayerData.job.name, 'police')
    local gang = QBCoreSeed.gangs[2] and QBCoreSeed.gangs[2].name
    if gang then
        h.assertTrue(p.Functions.SetGang(gang:upper(), 0))
        local g = QBCore.Functions.GetPlayer(1).PlayerData.gang
        h.assertEqual(g.name, gang)
        h.assertEqual(type(g.grade.isboss), 'boolean')
    end
end)

h.report('compat_playerdata_defaults')
