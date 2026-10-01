-- Core.garage (server realm) -- SQL-persisted vehicle ownership: civilian
-- garage (store/retrieve) and job duty-fleet vehicles share one
-- `player_vehicles` table (see sql/005_vehicles.sql), distinguished by
-- whether `citizenid` or `job` is set on a row (by convention, not enforced
-- at the SQL level -- a row is expected to have exactly one of the two).
--
-- spawnVehicle uses the raw CreateVehicle native, NEVER QB.entities (qblib's
-- entity spawner is explicitly local/non-networked) -- a duty or owned
-- vehicle must be visible to every player, not just the one who spawned it.
--
-- Vehicle `mods` are stored/returned as opaque JSON and are NOT auto-applied
-- to a spawned vehicle by this module -- that's ~50 SetVehicleMod calls of
-- presentation-layer work belonging to whichever job/garage UI actually
-- wants a tuning system, not to a generic persistence primitive. fuel/engine/
-- body health ARE applied on spawn since that's cheap and universally wanted.

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

    local ok, err = QB.sql.execute(
        'INSERT INTO `player_vehicles` (`plate`,`model`,`vehicle`,`citizenid`,`job`,`fuel`,`engine_health`,`body_health`) '
        .. 'VALUES (?,?,?,?,?,?,?,?)',
        {
            -- Exactly one of citizenid/job is set; the other is a real SQL NULL.
            -- Writing it as a bare nil would leave a hole in this array and the
            -- driver would reject the whole statement.
            plate, modelName, modelName, citizenid or QB.sql.NULL, job or QB.sql.NULL,
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
    local row = QB.sql.single('SELECT * FROM `player_vehicles` WHERE `plate` = ? AND `deleted_at` IS NULL', { plate })
    return hydrate(row)
end

---@param citizenid string
---@return table[]
function Core.garage.getByOwner(citizenid)
    local rows = QB.sql.query(
        'SELECT * FROM `player_vehicles` WHERE `citizenid` = ? AND `deleted_at` IS NULL ORDER BY `id`', { citizenid }
    ) or {}
    for _, row in ipairs(rows) do hydrate(row) end
    return rows
end

---Marks a vehicle garaged and snapshots its condition. Does not delete the
---live entity -- the caller (which has the entity handle) does that itself
---after this succeeds.
---@param plate string
---@param snapshot table|nil {fuel?, engineHealth?, bodyHealth?, mods?, position?}
---@return boolean, string|nil
function Core.garage.storeVehicle(plate, snapshot)
    local row = Core.garage.getByPlate(plate)
    if not row then return false, 'unknown vehicle' end
    if row.state == 'impounded' then return false, 'vehicle is impounded' end

    snapshot = snapshot or {}
    local ok, err = QB.sql.execute(
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

---Spawns `plate` as a real, networked entity and marks it `out`. Refuses an
---impounded vehicle -- retrieve it via Core.garage.retrieveImpound first.
---@param src integer
---@param plate string
---@param coords vector3 | {x: number, y: number, z: number}
---@param heading number
---@return integer|false networkId
---@return string? error
function Core.garage.spawnVehicle(src, plate, coords, heading)
    local plateKey = normalizePlate(plate)
    if not plateKey then return false, 'invalid plate' end
    if spawningByPlate[plateKey] then return false, 'vehicle spawn already in progress' end

    spawningByPlate[plateKey] = true
    local vehicle
    local callOk, networkId, spawnErr = pcall(function()
        local row = Core.garage.getByPlate(plateKey)
        if not row then return false, 'unknown vehicle' end
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

        local affected, err = QB.sql.update(
            'UPDATE `player_vehicles` SET `state` = \'out\' '
            .. 'WHERE `plate` = ? AND `state` = \'garaged\' AND `deleted_at` IS NULL',
            { row.plate }
        )
        if err or affected ~= 1 then
            deleteSpawnedVehicle(vehicle)
            vehicle = nil
            return false, err or 'vehicle is no longer available'
        end

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

    local ok, err = QB.sql.execute(
        'UPDATE `player_vehicles` SET `state` = \'impounded\', `impound_fee` = ?, `impound_lot` = ?, `impounded_at` = NOW() WHERE `plate` = ?',
        { fee, impoundLot, plate }
    )

    if ok == nil and err then return false, err end
    return true
end

---Clears an impound flag. Charging the impound fee (Core.money.removeMoney)
---is the caller's responsibility, done before calling this -- garage
---persistence stays payment-method-agnostic, same reasoning Core.jobs leaves
---payment amounts to Core.money rather than moving cash itself.
---@param src integer
---@param plate string
---@return boolean, string|nil
function Core.garage.retrieveImpound(src, plate)
    local row = Core.garage.getByPlate(plate)
    if not row then return false, 'unknown vehicle' end
    if row.state ~= 'impounded' then return false, 'vehicle is not impounded' end

    -- A civilian-owned row can only be retrieved by its own owner; a
    -- job-fleet row (citizenid unset) has no per-player ownership to check --
    -- any on-duty member retrieving it is a job-resource-level policy
    -- decision, not this module's.
    if row.citizenid then
        local requesterCitizenid = Core.player.getPlayerData(src, { 'citizenid' })
        if requesterCitizenid ~= row.citizenid then
            return false, 'not your vehicle'
        end
    end

    local affected, err = QB.sql.update(
        'UPDATE `player_vehicles` SET `state` = \'garaged\', `impound_fee` = NULL, '
        .. '`impound_lot` = NULL, `impounded_at` = NULL '
        .. 'WHERE `plate` = ? AND `state` = \'impounded\' AND `deleted_at` IS NULL',
        { row.plate }
    )

    if err then return false, err end
    if affected ~= 1 then return false, 'vehicle is no longer impounded' end
    return true
end

---Generic partial condition update, for periodic autosave of a vehicle
---that's currently `out` (not just on store). Unlike storeVehicle, does not
---change `state` or refuse an impounded vehicle -- this is a pure condition
---snapshot, callable regardless of where the vehicle currently is.
---@param plate string
---@param patch table {fuel?, engineHealth?, bodyHealth?, mods?, position?}
---@return boolean
function Core.garage.updateState(plate, patch)
    if not Core.garage.getByPlate(plate) then return false end

    local ok = QB.sql.execute(
        'UPDATE `player_vehicles` SET '
        .. '`fuel` = COALESCE(?, `fuel`), `engine_health` = COALESCE(?, `engine_health`), '
        .. '`body_health` = COALESCE(?, `body_health`), `mods` = COALESCE(?, `mods`), '
        .. '`last_position` = COALESCE(?, `last_position`) WHERE `plate` = ?',
        {
            -- Every patch field is optional and COALESCE'd in SQL, so an absent
            -- one must bind as NULL rather than leaving a hole in this array.
            patch.fuel or QB.sql.NULL,
            patch.engineHealth or QB.sql.NULL,
            patch.bodyHealth or QB.sql.NULL,
            patch.mods and json.encode(patch.mods) or QB.sql.NULL,
            patch.position and json.encode(patch.position) or QB.sql.NULL,
            plate,
        }
    )

    return ok ~= nil
end

---Persists a complete QBCore-compatible vehicle-property snapshot without
---changing the vehicle's garage state. This is intentionally a server-only
---primitive: callers must authorize and charge for tuning before calling it.
---The plate and model remain authoritative database fields, while fuel and
---health are kept in their dedicated columns so a later garage spawn cannot
---be overridden by the JSON snapshot.
---@param plate string
---@param properties table Result of QB.vehicle.getProperties.
---@return boolean, string|nil
function Core.garage.saveVehicleProperties(plate, properties)
    if type(properties) ~= 'table' then return false, 'vehicle properties must be a table' end

    local storedProperties = {}
    for key, value in pairs(properties) do
        -- `plate` identifies the row and `model` is its ownership record, not
        -- mutable vehicle appearance. The condition values live in dedicated
        -- columns and are applied by spawnVehicle before presentation props.
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
    local ok = QB.sql.execute('UPDATE `player_vehicles` SET `deleted_at` = NOW() WHERE `plate` = ?', { plate })
    return ok ~= nil
end
