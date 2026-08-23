-- Core.garage smoke test -- uses a small in-memory fake `player_vehicles`
-- table in place of the generic mocks.lua QB.sql stub, since that stub's
-- responses are canned per exact SQL string (not parameter-aware) and
-- garage's CRUD genuinely needs INSERT-then-SELECT-back behavior to test
-- meaningfully.
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

local rows = {} -- plate -> row

local function clone(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

handle.QB.sql.execute = function(sql, params)
    if sql:find('INSERT INTO `player_vehicles`', 1, true) then
        local plate, model, citizenid, job, fuel, engineHealth, bodyHealth = table.unpack(params)
        if rows[plate] then return nil, 'duplicate plate' end
        rows[plate] = {
            plate = plate, model = model, citizenid = citizenid, job = job,
            state = 'garaged', fuel = fuel, engine_health = engineHealth, body_health = bodyHealth,
            mods = nil, last_position = nil, impound_fee = nil, impound_lot = nil, deleted_at = nil,
        }
        return { affectedRows = 1 }
    elseif sql:find("SET `state` = 'garaged'", 1, true) and sql:find('COALESCE', 1, true) then
        local fuel, engineHealth, bodyHealth, mods, lastPosition, plate = table.unpack(params)
        local row = rows[plate]
        if not row then return nil, 'not found' end
        row.state = 'garaged'
        row.fuel = fuel or row.fuel
        row.engine_health = engineHealth or row.engine_health
        row.body_health = bodyHealth or row.body_health
        row.mods = mods or row.mods
        row.last_position = lastPosition or row.last_position
        return { affectedRows = 1 }
    elseif sql:find("SET `state` = 'out'", 1, true) then
        local plate = params[1]
        if rows[plate] then rows[plate].state = 'out' end
        return { affectedRows = 1 }
    elseif sql:find("SET `state` = 'impounded'", 1, true) then
        local fee, lot, plate = table.unpack(params)
        local row = rows[plate]
        if not row then return nil, 'not found' end
        row.state = 'impounded'; row.impound_fee = fee; row.impound_lot = lot
        return { affectedRows = 1 }
    elseif sql:find('`impound_fee` = NULL', 1, true) then
        local plate = params[1]
        local row = rows[plate]
        if not row then return nil, 'not found' end
        row.state = 'garaged'; row.impound_fee = nil; row.impound_lot = nil
        return { affectedRows = 1 }
    elseif sql:find('`deleted_at` = NOW()', 1, true) then
        local plate = params[1]
        if rows[plate] then rows[plate].deleted_at = os.time() end
        return { affectedRows = 1 }
    elseif sql:find('UPDATE `player_vehicles` SET', 1, true) then
        -- updateState's generic patch, distinguished from storeVehicle's by
        -- not setting `state` at all.
        local fuel, engineHealth, bodyHealth, mods, lastPosition, plate = table.unpack(params)
        local row = rows[plate]
        if not row then return nil, 'not found' end
        row.fuel = fuel or row.fuel
        row.engine_health = engineHealth or row.engine_health
        row.body_health = bodyHealth or row.body_health
        row.mods = mods or row.mods
        row.last_position = lastPosition or row.last_position
        return { affectedRows = 1 }
    end
    error('unmocked SQL in garage test: ' .. sql)
end

handle.QB.sql.single = function(sql, params)
    local plate = params[1]
    local row = rows[plate]
    if not row or row.deleted_at then return nil end
    return clone(row)
end

handle.QB.sql.query = function(sql, params)
    local citizenid = params[1]
    local out = {}
    for _, row in pairs(rows) do
        if row.citizenid == citizenid and not row.deleted_at then out[#out + 1] = clone(row) end
    end
    return out
end

_G.CreateVehicle = function(model, x, y, z, heading) return 42 end
_G.DoesEntityExist = function() return true end
_G.SetVehicleNumberPlateText = function() end
_G.SetVehicleFuelLevel = function() end
_G.SetVehicleEngineHealth = function() end
_G.SetVehicleBodyHealth = function() end
_G.NetworkGetNetworkIdFromEntity = function(e) return 1000 + e end
_G.joaat = function(s) return 12345 end
_G.json = { encode = function(t) return 'JSON' end, decode = function(s) return {} end }

dofile('modules/garage/server.lua')

h.test('createVehicle inserts a new row', function()
    local ok = Core.garage.createVehicle('CID1', 'ambulance', 'EMS001')
    h.assertTrue(ok)
    local row = Core.garage.getByPlate('EMS001')
    h.assertTrue(row ~= nil)
    h.assertEqual(row.citizenid, 'CID1')
    h.assertEqual(row.state, 'garaged')
    h.assertEqual(row.fuel, Config.garage.defaultFuel)
end)

h.test('createVehicle rejects a duplicate plate', function()
    local ok, err = Core.garage.createVehicle('CID2', 'ambulance', 'EMS001')
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
end)

h.test('getByOwner returns every non-deleted row for a citizenid', function()
    Core.garage.createVehicle('CID1', 'police', 'PD001')
    local owned = Core.garage.getByOwner('CID1')
    h.assertEqual(#owned, 2)
end)

h.test('spawnVehicle creates a networked entity and marks the row out', function()
    local networkId, err = Core.garage.spawnVehicle(1, 'EMS001', { x = 0, y = 0, z = 0 }, 0.0)
    h.assertTrue(networkId ~= false, 'expected a network id, got error: ' .. tostring(err))
    h.assertEqual(Core.garage.getByPlate('EMS001').state, 'out')
end)

h.test('storeVehicle garages the vehicle and snapshots its condition', function()
    local ok = Core.garage.storeVehicle('EMS001', { fuel = 42, engineHealth = 700 })
    h.assertTrue(ok)
    local row = Core.garage.getByPlate('EMS001')
    h.assertEqual(row.state, 'garaged')
    h.assertEqual(row.fuel, 42)
    h.assertEqual(row.engine_health, 700)
end)

h.test('storeVehicle refuses an impounded vehicle', function()
    Core.garage.createVehicle('CID3', 'police', 'IMP001')
    Core.garage.impound('IMP001', 500, 'lot-1')
    local ok, err = Core.garage.storeVehicle('IMP001', {})
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
end)

h.test('spawnVehicle refuses an impounded vehicle', function()
    local networkId, err = Core.garage.spawnVehicle(1, 'IMP001', { x = 0, y = 0, z = 0 }, 0.0)
    h.assertFalse(networkId)
    h.assertTrue(err ~= nil)
end)

h.test("retrieveImpound refuses a citizen who doesn't own the vehicle", function()
    local ok, err = Core.garage.retrieveImpound(1, 'IMP001') -- src 1 is CID1, row is owned by CID3
    h.assertFalse(ok)
    h.assertEqual(err, 'not your vehicle')
end)

h.test('retrieveImpound clears the impound flags for the real owner', function()
    local data = CoreInternal.player.freshData('CID3', 'license:cid3', 1, { firstname = 'A', lastname = 'B' })
    Core.player.login(2, 'CID3', data)

    local ok = Core.garage.retrieveImpound(2, 'IMP001')
    h.assertTrue(ok)
    local row = Core.garage.getByPlate('IMP001')
    h.assertEqual(row.state, 'garaged')
    h.assertTrue(row.impound_fee == nil)
end)

h.test('deleteVehicle soft-deletes -- getByPlate no longer finds it', function()
    Core.garage.deleteVehicle('EMS001')
    h.assertTrue(Core.garage.getByPlate('EMS001') == nil)
end)

h.report('garage')
