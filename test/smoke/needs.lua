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

h.test('_tick fires hud:client:UpdateNeeds once with the post-decay values', function()
    Core.metadata.setMetaData(1, 'hunger', 50)
    Core.metadata.setMetaData(1, 'thirst', 60)
    local before = #handle.clientEvents
    Core.needs._tick()

    local calls = {}
    for i = before + 1, #handle.clientEvents do
        local evt = handle.clientEvents[i]
        if evt.name == 'hud:client:UpdateNeeds' then calls[#calls + 1] = evt end
    end
    h.assertEqual(#calls, 1, '_tick should fire hud:client:UpdateNeeds exactly once per player per tick')
    local evt = calls[1]
    h.assertEqual(evt.target, 1)
    h.assertEqual(evt.args[1], 50 - Config.needs.hungerDecay, 'should carry the resulting (post-decay) hunger')
    h.assertEqual(evt.args[2], 60 - Config.needs.thirstDecay, 'should carry the resulting (post-decay) thirst')
end)

h.test('startNeedsDecay/stopNeedsDecay do not error', function()
    Core.needs.startNeedsDecay()
    Core.needs.stopNeedsDecay()
    h.assertTrue(true, 'reaching this line means neither call errored')
end)

-- Exercise the CLIENT realm in a fresh Core table: server/client needs modules
-- share the same module namespace in production but load in separate VMs.
_G.Core = setmetatable({}, { __index = function(self, key)
    local module = {}
    rawset(self, key, module)
    return module
end })

local needHandlers = {}
local metadata = { hunger = 100, thirst = 100, isdead = false, inlaststand = false }
local pedDead = false
local damageCalls = {}

Core.player.onPlayerDataChange = function(path, handler)
    needHandlers[path[2]] = handler
end
Core.player.getPlayerData = function() return metadata end
_G.PlayerPedId = function() return 42 end
_G.QB = { cache = { ped = function() return 42 end } }
_G.IsEntityDead = function() return pedDead end
_G.ApplyDamageToPed = function(ped, damage, armourFirst)
    damageCalls[#damageCalls + 1] = { ped = ped, damage = damage, armourFirst = armourFirst }
end

dofile('modules/needs/client.lua')

h.test('empty hunger and thirst apply their configured damage independently', function()
    damageCalls = {}
    needHandlers.hunger({ 'metadata', 'hunger' }, 0)
    needHandlers.thirst({ 'metadata', 'thirst' }, 0)

    h.assertEqual(#damageCalls, 2, 'both empty needs should produce separate damage calls')
    h.assertEqual(damageCalls[1].damage, Config.needs.hungerDamage)
    h.assertEqual(damageCalls[2].damage, Config.needs.thirstDamage)
    h.assertEqual(damageCalls[1].damage + damageCalls[2].damage,
        Config.needs.hungerDamage + Config.needs.thirstDamage, 'combined empty needs should stack damage')
end)

h.test('positive needs and dead/last-stand players do not take needs damage', function()
    damageCalls = {}
    needHandlers.hunger({ 'metadata', 'hunger' }, 1)
    h.assertEqual(#damageCalls, 0, 'positive hunger should not damage')

    pedDead = true
    needHandlers.hunger({ 'metadata', 'hunger' }, 0)
    pedDead = false
    metadata.inlaststand = true
    needHandlers.thirst({ 'metadata', 'thirst' }, 0)
    metadata.inlaststand = false
    metadata.isdead = true
    needHandlers.hunger({ 'metadata', 'hunger' }, 0)
    metadata.isdead = false
    h.assertEqual(#damageCalls, 0, 'dead and last-stand states should suppress needs damage')
end)

h.report('needs')
