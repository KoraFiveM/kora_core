local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
local realTime = os.time
local now = 1800000000
os.time = function() return now end

local scheduled = {}
local originalSetTimeout = SetTimeout
SetTimeout = function(delay, callback)
    if delay == 0 then return originalSetTimeout(delay, callback) end
    scheduled[#scheduled + 1] = { delay = delay, callback = callback }
end

local releases = {}
AddEventHandler('kora_core:server:playerReleased', function(src)
    releases[src] = (releases[src] or 0) + 1
end)

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

local function eventsFor(name, src)
    local out = {}
    for _, e in ipairs(handle.clientEvents) do
        if e.name == name and (not src or e.target == src) then out[#out + 1] = e end
    end
    return out
end

local function loginAs(src, cid, releaseAt)
    local playerData = CoreInternal.player.freshData(cid, 'license:' .. cid, 1, { firstname = 'Jail', lastname = 'Test' })
    playerData.metadata.jailed = releaseAt or 0
    playerData.metadata.injail = releaseAt or 0
    h.assertTrue(Core.player.login(src, cid, playerData))
    return CoreInternal.player.handle(src)
end

h.test('jailPlayer teleports and sets a future release timestamp', function()
    local ok = Core.jail.jailPlayer(1, 10, 'testing')
    h.assertTrue(ok)
    h.assertTrue(Core.jail.isJailed(1))
    h.assertTrue(Core.jail.getRemaining(1) > 0 and Core.jail.getRemaining(1) <= 600)

    local hits = eventsFor('kora_core:client:jailTeleport')
    h.assertEqual(#hits, 1, 'exactly one jailTeleport push should have been sent')
    h.assertEqual(hits[1].target, 1)

    local p = CoreInternal.player.handle(1)
    h.assertTrue(p.PlayerData.metadata.injail > 0, 'metadata.injail should mirror the release timestamp')
    h.assertEqual(p.PlayerData.metadata.injail, p.PlayerData.metadata.jailed, 'injail and jailed should always agree')
end)

h.test('release clears jailed state and notifies the client', function()
    local ok = Core.jail.release(1)
    h.assertTrue(ok)
    h.assertFalse(Core.jail.isJailed(1))
    h.assertEqual(Core.jail.getRemaining(1), 0)
    h.assertTrue(#eventsFor('kora_core:client:jailRelease') >= 1)

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
    handle.eventHandlers['kora_core:server:onJailRequest'] = { function(src, minutes, reason, resourceName)
        requested = true
        h.assertEqual(src, 1)
        h.assertEqual(resourceName, 'xt-prison')
    end }

    local before = #eventsFor('kora_core:client:jailTeleport')
    local timersBefore = #scheduled
    local ok = Core.jail.jailPlayer(1, 15)
    h.assertTrue(ok, 'jailPlayer still reports success -- the external resource is expected to have handled it')
    h.assertTrue(requested, 'onJailRequest should have fired for the external resource')
    h.assertEqual(#eventsFor('kora_core:client:jailTeleport'), before, 'Core.jail must not apply its own teleport when deferring')
    h.assertFalse(Core.jail.isJailed(1), 'Core.jail must not set its own metadata.jailed when deferring')
    h.assertEqual(#scheduled, timersBefore, 'external prison owns the release timer')

    handle.resourceStates['xt-prison'] = 'missing'
end)

h.test('rejoin re-applies the teleport if still jailed, but not once released', function()
    Core.jail.jailPlayer(1, 10)
    local before = #eventsFor('kora_core:client:jailTeleport')

    handle.fireEvent('kora_core:server:playerLoaded', 1, 1)
    h.assertTrue(#eventsFor('kora_core:client:jailTeleport') > before, 'still jailed -- should re-teleport on rejoin')

    Core.jail.release(1)
    local afterRelease = #eventsFor('kora_core:client:jailTeleport')
    handle.fireEvent('kora_core:server:playerLoaded', 1, 1)
    h.assertEqual(#eventsFor('kora_core:client:jailTeleport'), afterRelease, 'no longer jailed -- rejoin should not re-teleport')
end)

h.test('sentence expiry clears both metadata fields and releases once', function()
    local p = loginAs(2, 'JAIL-EXPIRY')
    h.assertTrue(Core.jail.jailPlayer(2, 1))
    local timer = scheduled[#scheduled]
    h.assertEqual(timer.delay, 60000)

    now = now + 60
    timer.callback()
    h.assertEqual(p.PlayerData.metadata.jailed, 0)
    h.assertEqual(p.PlayerData.metadata.injail, 0)
    h.assertEqual(#eventsFor('kora_core:client:jailRelease', 2), 1)
    h.assertEqual(releases[2], 1)
    timer.callback()
    h.assertEqual(releases[2], 1, 'an already-released sentence cannot release again')
end)

h.test('an early timer reschedules until the sentence expires', function()
    local p = loginAs(3, 'JAIL-EARLY')
    Core.jail.jailPlayer(3, 1)
    local releaseAt = p.PlayerData.metadata.jailed
    local timer = scheduled[#scheduled]
    timer.callback()
    h.assertEqual(p.PlayerData.metadata.jailed, releaseAt, 'an early callback must not release')
    h.assertEqual(releases[3], nil)
    local retry = scheduled[#scheduled]
    h.assertTrue(retry ~= timer, 'a new callback is scheduled')
    h.assertEqual(retry.delay, 60000)

    now = now + 60
    retry.callback()
    h.assertEqual(p.PlayerData.metadata.jailed, 0)
    h.assertEqual(releases[3], 1)
end)

h.test('a previous sentence timer cannot release a newer sentence', function()
    local p = loginAs(4, 'JAIL-RESENTENCE')
    Core.jail.jailPlayer(4, 1)
    local oldTimer = scheduled[#scheduled]
    Core.jail.jailPlayer(4, 2)
    local releaseAt = p.PlayerData.metadata.jailed
    local newTimer = scheduled[#scheduled]

    now = now + 60
    oldTimer.callback()
    h.assertEqual(p.PlayerData.metadata.jailed, releaseAt)
    h.assertEqual(releases[4], nil)
    now = now + 60
    newTimer.callback()
    h.assertEqual(p.PlayerData.metadata.jailed, 0)
    h.assertEqual(releases[4], 1)
end)

h.test('manual release makes the pending sentence timer a no-op', function()
    loginAs(5, 'JAIL-MANUAL')
    Core.jail.jailPlayer(5, 1)
    local timer = scheduled[#scheduled]
    h.assertTrue(Core.jail.release(5))
    now = now + 60
    timer.callback()
    h.assertEqual(releases[5], 1, 'manual release emits the only release event')
    h.assertEqual(#eventsFor('kora_core:client:jailRelease', 5), 1)
end)

h.test('a restored sentence receives its own timer after character relog', function()
    local p = loginAs(6, 'JAIL-RELOG')
    Core.jail.jailPlayer(6, 2)
    local releaseAt = p.PlayerData.metadata.jailed
    local oldTimer = scheduled[#scheduled]
    h.assertTrue(Core.player.logout(6))
    local restored = loginAs(6, 'JAIL-RELOG', releaseAt)
    local timer = scheduled[#scheduled]
    h.assertEqual(timer.delay, 120000)
    h.assertEqual(#eventsFor('kora_core:client:jailTeleport', 6), 2)

    now = now + 120
    oldTimer.callback()
    h.assertEqual(restored.PlayerData.metadata.jailed, releaseAt, 'the old handle timer cannot release the new session')
    h.assertEqual(releases[6], nil)
    timer.callback()
    h.assertEqual(restored.PlayerData.metadata.jailed, 0)
    h.assertEqual(restored.PlayerData.metadata.injail, 0)
    h.assertEqual(releases[6], 1)
end)

h.test('disconnect and source reuse cannot give an old timer another character', function()
    local p = loginAs(7, 'JAIL-DROPPED')
    Core.jail.jailPlayer(7, 2)
    local releaseAt = p.PlayerData.metadata.jailed
    local oldTimer = scheduled[#scheduled]
    Core.player.dropPlayer(7, 'test')
    oldTimer.callback()
    h.assertEqual(releases[7], nil, 'a disconnected player cannot be released')

    local replacement = loginAs(7, 'JAIL-REPLACEMENT', releaseAt)
    local timer = scheduled[#scheduled]
    now = now + 120
    oldTimer.callback()
    h.assertEqual(replacement.PlayerData.metadata.jailed, releaseAt, 'even a matching timestamp belongs to another handle')
    h.assertEqual(releases[7], nil)
    timer.callback()
    h.assertEqual(replacement.PlayerData.metadata.jailed, 0)
    h.assertEqual(releases[7], 1)
end)

h.test('an already-expired built-in sentence is cleared when loaded', function()
    local timersBefore = #scheduled
    local p = loginAs(8, 'JAIL-EXPIRED', now - 1)
    h.assertEqual(p.PlayerData.metadata.jailed, 0)
    h.assertEqual(p.PlayerData.metadata.injail, 0)
    h.assertEqual(#eventsFor('kora_core:client:jailTeleport', 8), 0)
    h.assertEqual(#eventsFor('kora_core:client:jailRelease', 8), 1)
    h.assertEqual(releases[8], 1)
    h.assertEqual(#scheduled, timersBefore, 'an expired sentence needs no timer')
end)

h.test('external prison ownership skips restored and expired sentence handling', function()
    handle.resourceStates['xt-prison'] = 'started'
    local timersBefore = #scheduled
    local active = loginAs(9, 'JAIL-EXTERNAL-ACTIVE', now + 60)
    local expired = loginAs(10, 'JAIL-EXTERNAL-EXPIRED', now - 60)
    h.assertEqual(active.PlayerData.metadata.jailed, now + 60)
    h.assertEqual(expired.PlayerData.metadata.jailed, now - 60)
    h.assertEqual(expired.PlayerData.metadata.injail, now - 60, 'external metadata is left untouched')
    h.assertEqual(#scheduled, timersBefore)
    h.assertEqual(#eventsFor('kora_core:client:jailTeleport', 9), 0)
    h.assertEqual(#eventsFor('kora_core:client:jailRelease', 10), 0)
    handle.resourceStates['xt-prison'] = 'missing'
end)

os.time = realTime
h.report('jail')
