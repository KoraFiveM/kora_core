local h = dofile('test/harness.lua')
local handle = dofile('test/mocks.lua').install()
dofile('config.lua')
dofile('shared/items.lua'); dofile('shared/jobs.lua'); dofile('shared/gangs.lua')
dofile('shared/vehicles.lua'); dofile('shared/weapons.lua'); dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua'); dofile('modules/registry/server.lua')
dofile('modules/player/shared.lua'); dofile('modules/replication/server.lua')
dofile('modules/persistence/server.lua'); dofile('modules/persistence/operations.lua')
dofile('modules/player/server.lua')
dofile('modules/inventory/shared.lua'); dofile('modules/inventory/server.lua')
dofile('modules/jobs/server.lua')

exports.kora_sql = { hasActivePlayerOperation = function() return false end }
local PI, flushHook = CoreInternal.player, nil
QB.sql.flush = function() if flushHook then return flushHook() end; return true end
local roleEvents = 0
for _, event in ipairs({ 'QBCore:Server:OnJobUpdate', 'QBCore:Server:OnGangUpdate', 'QBCore:Server:SetDuty' }) do
    AddEventHandler(event, function() roleEvents = roleEvents + 1 end)
end
local serial = 800
local function player()
    serial = serial + 1
    local data = PI.freshData('MUTATOR' .. serial, 'license:mutator' .. serial, 1,
        { firstname = 'Logout', lastname = 'Mutator' })
    h.assertTrue(Core.player.login(serial, data.citizenid, data))
    return serial, PI.handle(serial)
end

h.test('logout rejects every fallback inventory mutation before touching live items or consuming drops', function()
    local src, live = player()
    h.assertTrue(Core.inventory.addItem(src, 'water_bottle', 4, 1))
    h.assertTrue(Core.inventory.addItem(src, 'water_bottle', 2, 2))
    local drop = Core.inventory.dropCreate({ x=1, y=2, z=3 }, { [1]={name='water_bottle',amount=2,info={}} })
    local used = 0
    Core.inventory.createUseable('water_bottle', function() used = used + 1 end)
    local results, before, during, eventsBefore, eventsAfter = {}, json.encode(live.PlayerData.items)
    flushHook = function()
        eventsBefore = #handle.clientEvents
        results = {
            Core.inventory.addItem(src, 'water_bottle', 2, 1),
            Core.inventory.addItem(src, 'phone', 2),
            Core.inventory.removeItem(src, 'water_bottle', 1, 1),
            Core.inventory.removeItem(src, 'water_bottle', 6),
            Core.inventory._removeFromSlot(src, 1, 1),
            Core.inventory.moveItem(src, 1, 2, 1),
            Core.inventory.moveItem(src, 1, 3, 4),
            Core.inventory.clearInventory(src),
            Core.inventory.setItems(src, {}),
            Core.inventory.useItem(src, 1),
            Core.inventory.dropTake(src, drop, 1, 2),
        }
        during, eventsAfter = json.encode(live.PlayerData.items), #handle.clientEvents
        return true
    end
    h.assertTrue(Core.player.logout(src)); flushHook = nil
    for index = 1, 11 do h.assertFalse(results[index], 'mutation ' .. index .. ' must reject during logout') end
    h.assertEqual(during, before); h.assertEqual(eventsAfter, eventsBefore); h.assertEqual(used, 0)
    local replacement = player()
    h.assertTrue(Core.inventory.dropTake(replacement, drop, 1, 2), 'a rejected pickup leaves its drop intact')
    h.assertEqual(Core.inventory.getItemCount(replacement, 'water_bottle'), 2)
    h.assertTrue(Core.player.logout(replacement))
end)

h.test('logout rejects job gang and duty changes without false events or index changes', function()
    local src, live = player()
    h.assertTrue(Core.jobs.setJob(src, 'police', 1))
    h.assertTrue(Core.jobs.setJobDuty(src, true))
    local before = json.encode({ live.PlayerData.job, live.PlayerData.gang })
    local results, during, duty, police, clientBefore, clientAfter, serverBefore, serverAfter
    flushHook = function()
        clientBefore, serverBefore = #handle.clientEvents, roleEvents
        results = { Core.jobs.setJob(src, 'ambulance', 1), Core.jobs.setGang(src, 'ballas', 1), Core.jobs.setJobDuty(src, false) }
        during = json.encode({ live.PlayerData.job, live.PlayerData.gang })
        duty, police = Core.jobs.getDutyCount('police'), Core.jobs.getPlayersByJob('police')[1]
        clientAfter, serverAfter = #handle.clientEvents, roleEvents
        return true
    end
    h.assertTrue(Core.player.logout(src)); flushHook = nil
    for index = 1, 3 do h.assertFalse(results[index]) end
    h.assertEqual(during, before); h.assertEqual(duty, 1); h.assertEqual(police, src)
    h.assertEqual(clientAfter, clientBefore); h.assertEqual(serverAfter, serverBefore)
end)

h.test('failed logout releases the mutation guard for the retained character', function()
    local src = player()
    flushHook = function() return false, 'save failed' end
    h.assertFalse(Core.player.logout(src)); flushHook = nil
    h.assertTrue(Core.inventory.addItem(src, 'water_bottle', 3))
    h.assertTrue(Core.inventory.removeItem(src, 'water_bottle', 1))
    h.assertEqual(Core.inventory.getItemCount(src, 'water_bottle'), 2)
    h.assertTrue(Core.jobs.setJob(src, 'police', 1))
    h.assertTrue(Core.jobs.setGang(src, 'ballas', 1))
    h.assertTrue(Core.jobs.setJobDuty(src, true))
    h.assertEqual(Core.jobs.getDutyCount('police'), 1)
    h.assertTrue(Core.player.logout(src))
end)

h.report('logout mutators')
