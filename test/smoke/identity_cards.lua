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
dofile('modules/inventory/shared.lua')
dofile('modules/inventory/server.lua')
dofile('modules/inventory/identity_cards.lua')

local data = CoreInternal.player.freshData('CID1', 'license:abc', 1, {
    firstname = 'Ada',
    lastname = 'Lovelace',
    birthdate = '1815-12-10',
    gender = 1,
    nationality = 'British',
})
Core.player.login(1, 'CID1', data)
handle.setPlayers({ 1 })

local function clearClient()
    for i = #handle.clientEvents, 1, -1 do
        handle.clientEvents[i] = nil
    end
end

local function lastCardArgs()
    local msg = handle.lastClient('chat:addMessage')
    if not msg then return nil end
    local payload = msg.args[1]
    return msg, payload and payload.args
end

h.test('id_card and driver_license register as useables at load', function()
    h.assertTrue(Core.inventory.getUseable('id_card') ~= nil)
    h.assertTrue(Core.inventory.getUseable('driver_license') ~= nil)
end)

h.test('using id_card shows holder details from item info to nearby players', function()
    local player = CoreInternal.player.handle(1)
    player.PlayerData.items = {
        [1] = {
            slot = 1, name = 'id_card', amount = 1,
            info = {
                citizenid = 'CID1', firstname = 'Ada', lastname = 'Lovelace',
                birthdate = '1815-12-10', gender = 0, nationality = 'British',
            },
        },
    }
    clearClient()
    h.assertTrue(Core.inventory.useItem(1, 1))
    local msg, args = lastCardArgs()
    h.assertTrue(msg ~= nil, 'chat:addMessage must fire for the holder')
    h.assertEqual(msg.target, 1)
    h.assertEqual(args[1], 'ID Card')
    h.assertEqual(args[2], 'CID1')
    h.assertEqual(args[3], 'Ada')
    h.assertEqual(args[4], 'Lovelace')
    h.assertEqual(args[5], '1815-12-10')
    h.assertEqual(args[6], 'Male')
    h.assertEqual(args[7], 'British')
end)

h.test('using driver_license shows license fields from item info', function()
    local player = CoreInternal.player.handle(1)
    player.PlayerData.items = {
        [2] = {
            slot = 2, name = 'driver_license', amount = 1,
            info = {
                firstname = 'Ada', lastname = 'Lovelace',
                birthdate = '1815-12-10', type = 'Class C',
            },
        },
    }
    clearClient()
    h.assertTrue(Core.inventory.useItem(1, 2))
    local _, args = lastCardArgs()
    h.assertTrue(args ~= nil, 'chat:addMessage must fire for the holder')
    h.assertEqual(args[1], 'Drivers License')
    h.assertEqual(args[2], 'Ada')
    h.assertEqual(args[3], 'Lovelace')
    h.assertEqual(args[4], '1815-12-10')
    h.assertEqual(args[5], 'Class C')
end)

h.test('missing item info falls back to the holder PlayerData', function()
    local player = CoreInternal.player.handle(1)
    player.PlayerData.items = {
        [3] = { slot = 3, name = 'id_card', amount = 1, info = {} },
    }
    clearClient()
    h.assertTrue(Core.inventory.useItem(1, 3))
    local _, args = lastCardArgs()
    h.assertTrue(args ~= nil)
    h.assertEqual(args[2], 'CID1')
    h.assertEqual(args[3], 'Ada')
    h.assertEqual(args[4], 'Lovelace')
    h.assertEqual(args[6], 'Female')
end)

h.test('players beyond 3.0 m do not receive the card', function()
    handle.setPlayers({ 1, 2 })
    _G.GetPlayerPed = function(id) return id end
    _G.GetEntityCoords = function(ped) return { x = ped == 2 and 50.0 or 0.0, y = 0.0, z = 0.0 } end

    local player = CoreInternal.player.handle(1)
    player.PlayerData.items = {
        [1] = {
            slot = 1, name = 'id_card', amount = 1,
            info = { citizenid = 'CID1', firstname = 'Ada', lastname = 'Lovelace', birthdate = '1815-12-10', gender = 0, nationality = 'British' },
        },
    }
    clearClient()
    h.assertTrue(Core.inventory.useItem(1, 1))

    local targets = {}
    for _, ev in ipairs(handle.clientEvents) do
        if ev.name == 'chat:addMessage' then targets[#targets + 1] = ev.target end
    end
    h.assertEqual(#targets, 1)
    h.assertEqual(targets[1], 1)

    handle.setPlayers({ 1 })
    _G.GetPlayerPed = function(_) return 100 end
    _G.GetEntityCoords = function(_) return { x = 0.0, y = 0.0, z = 0.0 } end
end)

h.test('provider onResourceStart re-registers the stock handlers', function()
    local registered = {}
    local previous = Core.inventory.createUseable
    Core.inventory.createUseable = function(name, handler)
        registered[#registered + 1] = name
        return previous(name, handler)
    end
    handle.fireEvent('onResourceStart', nil, Config.inventory.provider or 'kora_inventory')
    Core.inventory.createUseable = previous

    local seen = {}
    for _, name in ipairs(registered) do seen[name] = true end
    h.assertTrue(seen.id_card == true)
    h.assertTrue(seen.driver_license == true)
end)

h.report('identity_cards')
