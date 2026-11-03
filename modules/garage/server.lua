-- Core.garage (server realm) -- SQL-persisted vehicle ownership: civilian
-- garage (store/retrieve) and job duty-fleet vehicles share one
-- `player_vehicles` table (see modules/persistence/schema.lua), distinguished by
-- whether `citizenid` or `job` is set on a row (by convention, not enforced
-- at the SQL level -- a row is expected to have exactly one of the two).
--
-- spawnVehicle uses the raw CreateVehicle native, NEVER Kora.entities (local/non-networked):
-- a duty or owned vehicle must be visible to every player.
--
-- Vehicle `mods` are stored/returned as opaque JSON and NOT auto-applied (that is
-- presentation-layer work for the garage UI); fuel/engine/body health are applied on spawn.

local function decodeJson(s, fallback)
    if not s then return fallback end
    local ok, v = pcall(json.decode, s)
    return ok and v or fallback
end

local function hydrate(row)
    if not row then return nil end
    row.mods = decodeJson(row.mods, nil)
    row.last_position = decodeJson(row.last_position, nil)
    return row
end

local spawningByPlate = {}

local function normalizePlate(plate)
    if type(plate) ~= 'string' then return nil end
    local normalized = plate:gsub('^%s+', ''):gsub('%s+$', ''):upper()
    return normalized ~= '' and normalized or nil
end

local function deleteSpawnedVehicle(vehicle)
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        DeleteEntity(vehicle)
    end
end

local function resolveNetworkId(vehicle)
    local deadline = GetGameTimer() + Config.garage.spawnNetworkIdTimeout
    repeat
        local networkId = tonumber(NetworkGetNetworkIdFromEntity(vehicle))
        if networkId and networkId % 1 == 0 and networkId > 0 then return networkId end
        Wait(50)
    until not DoesEntityExist(vehicle) or GetGameTimer() >= deadline
    return nil
end

---@param citizenid string|nil Set for a civilian-owned vehicle.
---@param model string|number
---@param plate string
---@param job string|nil Set for a job duty-fleet vehicle. Exactly one of `citizenid`/`job` is expected.
---@param extra table|nil {fuel?, engineHealth?, bodyHealth?}
---@return boolean, string|nil
function Core.garage.createVehicle(citizenid, model, plate, job, extra)
    assert(citizenid or job, 'Core.garage.createVehicle requires citizenid or job.')
    assert(type(plate) == 'string' and #plate > 0, 'Core.garage.createVehicle requires a plate.')

    extra = extra or {}
    local modelName = type(model) == 'number' and tostring(model) or model

    local ok, err = Kora.sql.execute(
        'INSERT INTO `player_vehicles` (`plate`,`model`,`vehicle`,`citizenid`,`job`,`fuel`,`engine_health`,`body_health`) '
        .. 'VALUES (?,?,?,?,?,?,?,?)',
        {
            -- Exactly one of citizenid/job is set; the other must be a real SQL NULL (a bare nil
            -- would leave a hole in this array and the driver rejects the statement).
            plate, modelName, modelName, citizenid or Kora.sql.NULL, job or Kora.sql.NULL,
            extra.fuel or Config.garage.defaultFuel,
            extra.engineHealth or Config.garage.defaultEngineHealth,
            extra.bodyHealth or Config.garage.defaultBodyHealth,
        }
    )

    if ok == nil and err then return false, err end
    return true
end

---@param plate string
---@return table|nil
function Core.garage.getByPlate(plate)
    local row = Kora.sql.single('SELECT * FROM `player_vehicles` WHERE `plate` = ? AND `deleted_at` IS NULL', { plate })
    return hydrate(row)
end

---@param citizenid string
---@return table[]
function Core.garage.getByOwner(citizenid)
    local rows = Kora.sql.query(
        'SELECT * FROM `player_vehicles` WHERE `citizenid` = ? AND `deleted_at` IS NULL ORDER BY `id`', { citizenid }
    ) or {}
    for _, row in ipairs(rows) do hydrate(row) end
    return rows
end

---Marks a vehicle garaged and snapshots its condition. Does not delete the
---live entity -- the caller (which has the entity handle) does that itself
---after this succeeds.
---@param plate string
---@param snapshot table|nil {fuel?, engineHealth?, bodyHealth?, mods?, position?, garageId?, ownerCitizenId?}
---@return boolean, string|nil
function Core.garage.storeVehicle(plate, snapshot)
    local row = Core.garage.getByPlate(plate)
    if not row then return false, 'unknown vehicle' end
    if row.state == 'impounded' then return false, 'vehicle is impounded' end

    snapshot = snapshot or {}
    if snapshot.garageId ~= nil then
        if type(snapshot.garageId) ~= 'string' or #snapshot.garageId < 1 or #snapshot.garageId > 50 then return false, 'invalid garage id' end
        if snapshot.ownerCitizenId and row.citizenid ~= snapshot.ownerCitizenId then return false, 'vehicle ownership changed' end
        local values = { snapshot.garageId, snapshot.fuel or Kora.sql.NULL, snapshot.engineHealth or Kora.sql.NULL,
            snapshot.bodyHealth or Kora.sql.NULL, snapshot.mods and json.encode(snapshot.mods) or Kora.sql.NULL, plate }
        if snapshot.ownerCitizenId then values[#values + 1] = snapshot.ownerCitizenId end
        local affected, err = Kora.sql.update(
            'UPDATE `player_vehicles` SET `state`=\'garaged\', `garage_id`=?, '
            .. '`fuel`=COALESCE(?,`fuel`), `engine_health`=COALESCE(?,`engine_health`), '
            .. '`body_health`=COALESCE(?,`body_health`), `mods`=COALESCE(?,`mods`) '
            .. 'WHERE `plate`=? AND `state`=\'out\' AND `deleted_at` IS NULL' .. (snapshot.ownerCitizenId and ' AND `citizenid`=?' or ''), values)
        if err or affected ~= 1 then return false, err or 'vehicle is no longer available' end
        return true
    end
    local ok, err = Kora.sql.execute(
        'UPDATE `player_vehicles` SET `state` = \'garaged\', '
        .. '`fuel` = COALESCE(?, `fuel`), `engine_health` = COALESCE(?, `engine_health`), '
        .. '`body_health` = COALESCE(?, `body_health`), `mods` = COALESCE(?, `mods`), '
        .. '`last_position` = COALESCE(?, `last_position`) WHERE `plate` = ?',
        {
            snapshot.fuel, snapshot.engineHealth, snapshot.bodyHealth,
            snapshot.mods and json.encode(snapshot.mods) or nil,
            snapshot.position and json.encode(snapshot.position) or nil,
            plate,
        }
    )

    if ok == nil and err then return false, err end
    return true
end

---Tags a spawned owned-vehicle entity with its `player_vehicles.id` as the
---server-only (non-replicated) `vehicleid` state bag, which stock ox_inventory
---reads before falling back to a per-open SQL lookup. Inert when convar
---`kora:vehicleIdStateBag` is 0. Callers must only tag after the entity exists
---and the row's state update succeeded.
---@param entity integer
---@param id integer `player_vehicles.id`
---@return boolean tagged
function Core.garage.tagVehicle(entity, id)
    if GetConvarInt('kora:vehicleIdStateBag', 1) == 0 then return false end
    id = math.tointeger(tonumber(id))
    if not id or id < 1 then return false end
    if type(entity) ~= 'number' or entity == 0 or not DoesEntityExist(entity) then return false end
    Entity(entity).state:set('vehicleid', id, false)
    return true
end

---Spawns `plate` as a real, networked entity and marks it `out`. Refuses an
---impounded vehicle -- retrieve it via Core.garage.retrieveImpound first.
---@param src integer
---@param plate string
---@param coords vector3 | {x: number, y: number, z: number}
---@param heading number
---@param expectedOwner? string Optional owner precondition for trusted property providers.
---@return integer|false networkId
---@return string? error
function Core.garage.spawnVehicle(src, plate, coords, heading, expectedOwner)
    local plateKey = normalizePlate(plate)
    if not plateKey then return false, 'invalid plate' end
    if spawningByPlate[plateKey] then return false, 'vehicle spawn already in progress' end

    spawningByPlate[plateKey] = true
    local vehicle
    local callOk, networkId, spawnErr = pcall(function()
        local row = Core.garage.getByPlate(plateKey)
        if not row then return false, 'unknown vehicle' end
        if expectedOwner and row.citizenid ~= expectedOwner then return false, 'vehicle ownership changed' end
        if row.state == 'impounded' then return false, 'vehicle is impounded' end
        if row.state == 'out' then return false, 'vehicle is already out' end

        local modelHash = tonumber(row.model) or joaat(row.model)

        vehicle = CreateVehicle(modelHash, coords.x, coords.y, coords.z, heading or 0.0, true, false)
        if vehicle == 0 or not DoesEntityExist(vehicle) then
            return false, 'failed to create vehicle'
        end

        SetEntityRoutingBucket(vehicle, GetPlayerRoutingBucket(src))

        SetVehicleNumberPlateText(vehicle, row.plate)
        SetVehicleBodyHealth(vehicle, row.body_health + 0.0)

        local resolvedNetworkId = resolveNetworkId(vehicle)
        if not resolvedNetworkId then
            deleteSpawnedVehicle(vehicle)
            vehicle = nil
            return false, 'failed to network vehicle'
        end

        local values = { row.plate }
        if expectedOwner then values[#values + 1] = expectedOwner end
        local affected, err = Kora.sql.update(
            'UPDATE `player_vehicles` SET `state` = \'out\' '
            .. 'WHERE `plate` = ? AND `state` = \'garaged\' AND `deleted_at` IS NULL' .. (expectedOwner and ' AND `citizenid`=?' or ''),
            values
        )
        if err or affected ~= 1 then
            deleteSpawnedVehicle(vehicle)
            vehicle = nil
            return false, err or 'vehicle is no longer available'
        end

        Core.garage.tagVehicle(vehicle, row.id)

        TriggerClientEvent('qbcore:client:vehicleCondition', src, resolvedNetworkId, row.fuel + 0.0, row.engine_health + 0.0)
        return resolvedNetworkId
    end)

    spawningByPlate[plateKey] = nil
    if not callOk then
        deleteSpawnedVehicle(vehicle)
        return false, tostring(networkId)
    end
    return networkId, spawnErr
end

---@param plate string
---@param fee number
---@param impoundLot string|nil
---@return boolean, string|nil
function Core.garage.impound(plate, fee, impoundLot)
    local row = Core.garage.getByPlate(plate)
    if not row then return false, 'unknown vehicle' end

    local ok, err = Kora.sql.execute(
        'UPDATE `player_vehicles` SET `state` = \'impounded\', `impound_fee` = ?, `impound_lot` = ?, `impounded_at` = NOW() WHERE `plate` = ?',
        { fee, impoundLot, plate }
    )

    if ok == nil and err then return false, err end
    return true
end

---Clears an impound flag. Charging the impound fee is the caller's job, done before this call.
---@param src integer
---@param plate string
---@return boolean, string|nil
function Core.garage.retrieveImpound(src, plate)
    local row = Core.garage.getByPlate(plate)
    if not row then return false, 'unknown vehicle' end
    if row.state ~= 'impounded' then return false, 'vehicle is not impounded' end

    -- Civilian rows are owner-only; job-fleet rows (citizenid unset) are a job-resource policy.
    if row.citizenid then
        local requesterCitizenid = Core.player.getPlayerData(src, { 'citizenid' })
        if requesterCitizenid ~= row.citizenid then
            return false, 'not your vehicle'
        end
    end

    local affected, err = Kora.sql.update(
        'UPDATE `player_vehicles` SET `state` = \'garaged\', `impound_fee` = NULL, '
        .. '`impound_lot` = NULL, `impounded_at` = NULL '
        .. 'WHERE `plate` = ? AND `state` = \'impounded\' AND `deleted_at` IS NULL',
        { row.plate }
    )

    if err then return false, err end
    if affected ~= 1 then return false, 'vehicle is no longer impounded' end
    return true
end

---Partial condition update for periodic autosave of an `out` vehicle. Unlike storeVehicle,
---does not change `state` or refuse an impounded vehicle.
---@param plate string
---@param patch table {fuel?, engineHealth?, bodyHealth?, mods?, position?}
---@return boolean
function Core.garage.updateState(plate, patch)
    if not Core.garage.getByPlate(plate) then return false end

    local ok = Kora.sql.execute(
        'UPDATE `player_vehicles` SET '
        .. '`fuel` = COALESCE(?, `fuel`), `engine_health` = COALESCE(?, `engine_health`), '
        .. '`body_health` = COALESCE(?, `body_health`), `mods` = COALESCE(?, `mods`), '
        .. '`last_position` = COALESCE(?, `last_position`) WHERE `plate` = ?',
        {
            -- Patch fields are COALESCE'd in SQL: absent ones must bind as NULL, not leave a hole.
            patch.fuel or Kora.sql.NULL,
            patch.engineHealth or Kora.sql.NULL,
            patch.bodyHealth or Kora.sql.NULL,
            patch.mods and json.encode(patch.mods) or Kora.sql.NULL,
            patch.position and json.encode(patch.position) or Kora.sql.NULL,
            plate,
        }
    )

    return ok ~= nil
end

---Persists a complete QBCore-compatible vehicle-property snapshot without changing garage
---state. Server-only: callers must authorize and charge for tuning first. Plate/model and
---fuel/health stay in their dedicated columns so the JSON snapshot cannot override them.
---@param plate string
---@param properties table Result of Kora.vehicle.getProperties.
---@return boolean, string|nil
function Core.garage.saveVehicleProperties(plate, properties)
    if type(properties) ~= 'table' then return false, 'vehicle properties must be a table' end

    local storedProperties = {}
    for key, value in pairs(properties) do
        -- plate/model identify the row; condition values live in dedicated columns.
        if key ~= 'plate' and key ~= 'model'
            and key ~= 'fuelLevel' and key ~= 'engineHealth' and key ~= 'bodyHealth' then
            storedProperties[key] = value
        end
    end

    local saved = Core.garage.updateState(plate, {
        fuel = properties.fuelLevel,
        engineHealth = properties.engineHealth,
        bodyHealth = properties.bodyHealth,
        mods = storedProperties,
    })
    if not saved then return false, 'unknown vehicle' end
    return true
end

---Soft-deletes a vehicle row (same convention `players`/character rows use).
---@param plate string
---@return boolean
function Core.garage.deleteVehicle(plate)
    local ok = Kora.sql.execute('UPDATE `player_vehicles` SET `deleted_at` = NOW() WHERE `plate` = ?', { plate })
    return ok ~= nil
end
