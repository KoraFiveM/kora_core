-- Core.needs smoke test -- Core.needs._tick is exercised directly, same
-- reasoning test/smoke/paycheck.lua documents for Core.paycheck._tick.
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
dofile('modules/metadata/server.lua')
dofile('modules/needs/server.lua')

local data = CoreInternal.player.freshData('CID1', 'license:abc', 1, { firstname = 'A', lastname = 'B' })
Core.player.login(1, 'CID1', data)

h.test('_tick decays hunger and thirst by the configured amount', function()
    Core.metadata.setMetaData(1, 'hunger', 50)
    Core.metadata.setMetaData(1, 'thirst', 50)
    Core.needs._tick()
    h.assertEqual(Core.metadata.getMetaData(1, 'hunger'), 50 - Config.needs.hungerDecay)
    h.assertEqual(Core.metadata.getMetaData(1, 'thirst'), 50 - Config.needs.thirstDecay)
end)

h.test('_tick does not decay stress', function()
    Core.metadata.setMetaData(1, 'stress', 10)
    Core.needs._tick()
    h.assertEqual(Core.metadata.getMetaData(1, 'stress'), 10, 'stress is never auto-decayed by Core.needs')
end)

h.test('_tick clamps hunger/thirst at zero, never going negative', function()
    Core.metadata.setMetaData(1, 'hunger', 0)
    Core.needs._tick()
    h.assertEqual(Core.metadata.getMetaData(1, 'hunger'), 0)
end)

h.test('reset restores hunger/thirst to 100 and stress to 0', function()
    Core.metadata.setMetaData(1, 'hunger', 20)
    Core.metadata.setMetaData(1, 'thirst', 20)
    Core.metadata.setMetaData(1, 'stress', 80)

    Core.needs.reset(1)

    h.assertEqual(Core.metadata.getMetaData(1, 'hunger'), 100)
    h.assertEqual(Core.metadata.getMetaData(1, 'thirst'), 100)
    h.assertEqual(Core.metadata.getMetaData(1, 'stress'), 0)
end)

h.test('startNeedsDecay/stopNeedsDecay do not error', function()
    Core.needs.startNeedsDecay()
    Core.needs.stopNeedsDecay()
    h.assertTrue(true, 'reaching this line means neither call errored')
end)

h.report('needs')
