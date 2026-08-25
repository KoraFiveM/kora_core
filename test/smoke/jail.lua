-- Core.jail smoke test -- jail/release/getRemaining, rejoin re-teleport, and
-- deference to an external prison resource when one is detected running.
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
dofile('modules/permissions/server.lua')
dofile('modules/commands/server.lua')
dofile('modules/jail/server.lua')

local data = CoreInternal.player.freshData('CID1', 'license:abc', 1, { firstname = 'A', lastname = 'B' })
Core.player.login(1, 'CID1', data)

local function eventsFor(name)
    local out = {}
    for _, e in ipairs(handle.clientEvents) do if e.name == name then out[#out + 1] = e end end
    return out
end

h.test('jailPlayer teleports and sets a future release timestamp', function()
    local ok = Core.jail.jailPlayer(1, 10, 'testing')
    h.assertTrue(ok)
    h.assertTrue(Core.jail.isJailed(1))
    h.assertTrue(Core.jail.getRemaining(1) > 0 and Core.jail.getRemaining(1) <= 600)

    local hits = eventsFor('qbcore:client:jailTeleport')
    h.assertEqual(#hits, 1, 'exactly one jailTeleport push should have been sent')
    h.assertEqual(hits[1].target, 1)

    -- Legacy mirror: real qb-core's metadata key is `injail`, not `jailed` --
    -- real qb-ambulancejob reads it directly (metadata['injail'] > 0) rather
    -- than through any Core.jail accessor.
    local p = CoreInternal.player.handle(1)
    h.assertTrue(p.PlayerData.metadata.injail > 0, 'metadata.injail should mirror the release timestamp')
    h.assertEqual(p.PlayerData.metadata.injail, p.PlayerData.metadata.jailed, 'injail and jailed should always agree')
end)

h.test('release clears jailed state and notifies the client', function()
    local ok = Core.jail.release(1)
    h.assertTrue(ok)
    h.assertFalse(Core.jail.isJailed(1))
    h.assertEqual(Core.jail.getRemaining(1), 0)
    h.assertTrue(#eventsFor('qbcore:client:jailRelease') >= 1)

    local p = CoreInternal.player.handle(1)
    h.assertEqual(p.PlayerData.metadata.injail, 0, 'release should also clear the legacy injail mirror')
end)

h.test('release on a player who is not jailed reports false', function()
    h.assertFalse(Core.jail.release(1))
end)

h.test('jailPlayer rejects a non-positive duration', function()
    local ok, err = Core.jail.jailPlayer(1, 0)
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
end)

h.test('defers to an external prison resource when one is running, applying nothing itself', function()
    handle.resourceStates['xt-prison'] = 'started'

    local requested = false
    handle.eventHandlers['qbcore:server:onJailRequest'] = { function(src, minutes, reason, resourceName)
        requested = true
        h.assertEqual(src, 1)
        h.assertEqual(resourceName, 'xt-prison')
    end }

    local before = #eventsFor('qbcore:client:jailTeleport')
    local ok = Core.jail.jailPlayer(1, 15)
    h.assertTrue(ok, 'jailPlayer still reports success -- the external resource is expected to have handled it')
    h.assertTrue(requested, 'onJailRequest should have fired for the external resource')
    h.assertEqual(#eventsFor('qbcore:client:jailTeleport'), before, 'Core.jail must not apply its own teleport when deferring')
    h.assertFalse(Core.jail.isJailed(1), 'Core.jail must not set its own metadata.jailed when deferring')

    handle.resourceStates['xt-prison'] = 'missing'
end)

h.test('rejoin re-applies the teleport if still jailed, but not once released', function()
    Core.jail.jailPlayer(1, 10)
    local before = #eventsFor('qbcore:client:jailTeleport')

    handle.fireEvent('qbcore:server:playerLoaded', 1, 1)
    h.assertTrue(#eventsFor('qbcore:client:jailTeleport') > before, 'still jailed -- should re-teleport on rejoin')

    Core.jail.release(1)
    local afterRelease = #eventsFor('qbcore:client:jailTeleport')
    handle.fireEvent('qbcore:server:playerLoaded', 1, 1)
    h.assertEqual(#eventsFor('qbcore:client:jailTeleport'), afterRelease, 'no longer jailed -- rejoin should not re-teleport')
end)

h.report('jail')
