-- compat/server/qb-vehicles.lua -- stock QBCore:Server:SpawnVehicle and
-- QBCore:Server:CreateVehicle callbacks (qb-core/server/events.lua), returning the
-- network id like stock. Stock lets any client choose any model at any
-- coordinates; here the request is validated against Config.compat.vehicleSpawn
-- and the vehicle is created by the server (strict entity lockdown never sees a
-- client-created entity). Config.compat.vehicleSpawnCallbacks selects
-- 'off' (not registered) | 'admin' | 'limited'. See docs/vehicle-spawn.md.

local mode = Config.compat.vehicleSpawnCallbacks
if mode ~= 'admin' and mode ~= 'limited' then return end

local F = QBCore.Functions
local settings = Config.compat.vehicleSpawn or {}

local MODEL_NAME_MAX = 32
local MAX_AXIS = 10000.0

local lastRequest = {}
local live = {}

local function finite(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

local function allowedModel(model)
    local name, hash
    if type(model) == 'string' then
        if #model > MODEL_NAME_MAX or not model:match('^[%w_]+$') then return nil end
        name, hash = model:lower(), joaat(model)
    elseif finite(model) and model % 1 == 0 then
        hash = model
    else
        return nil
    end
    if name and QBCore.Shared.Vehicles[name] then return hash end
    if QBCore.Shared.VehicleHashes[hash] then return hash end
    for _, allowed in ipairs(settings.allowModels or {}) do
        if type(allowed) == 'string' and joaat(allowed) == hash then return hash end
    end
    return nil
end

local function resolveCoords(ped, coords)
    local origin = GetEntityCoords(ped)
    if coords == nil then return vector4(origin.x, origin.y, origin.z, GetEntityHeading(ped)), origin end
    if type(coords) ~= 'table' or not (finite(coords.x) and finite(coords.y) and finite(coords.z)) then return nil end
    if math.abs(coords.x) > MAX_AXIS or math.abs(coords.y) > MAX_AXIS or math.abs(coords.z) > MAX_AXIS then return nil end
    local heading = coords.w
    if heading ~= nil and not finite(heading) then return nil end
    return vector4(coords.x, coords.y, coords.z, heading or 0.0), origin
end

local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function audit(src, callback, data)
    data.callback = callback
    local ok, err = pcall(Core.logging.logEvent, 'vehicle', src, data)
    if not ok then print(('^3[qbcore:vehicles]^7 audit log failed: %s'):format(tostring(err))) end
end

local function trackSpawn(src, vehicle)
    local list = live[src]
    if not list then list = {}; live[src] = list end
    for i = #list, 1, -1 do
        if not DoesEntityExist(list[i]) then table.remove(list, i) end
    end
    list[#list + 1] = vehicle
    local limit = math.max(1, math.floor(tonumber(settings.maxLive) or 2))
    while #list > limit do
        local oldest = table.remove(list, 1)
        if DoesEntityExist(oldest) then DeleteEntity(oldest) end
    end
end

local function grantKeys(src, vehicle)
    if settings.grantKeys == false or GetResourceState('kora_vehiclekeys') ~= 'started' then return end
    local plate = GetVehicleNumberPlateText(vehicle)
    if type(plate) ~= 'string' or plate:match('^%s*$') then return end
    local ok, err = pcall(function() return exports.kora_vehiclekeys:giveKeys(src, plate) end)
    if not ok then print(('^3[qbcore:vehicles]^7 could not grant keys: %s'):format(tostring(err))) end
end

local function handle(callbackName, create)
    return function(src, cb, model, coords, warp)
        local function refuse(reason)
            audit(src, callbackName, { refused = reason })
            cb(nil)
        end

        if mode == 'admin' then
            if not F.HasPermission(src, 'admin') then return refuse('permission') end
        elseif not F.GetPlayer(src) then
            return refuse('not loaded')
        end

        local limited = mode == 'limited'
        if limited then
            local now = GetGameTimer()
            local cooldown = tonumber(settings.cooldownMs) or 2000
            if lastRequest[src] and now - lastRequest[src] < cooldown then return refuse('rate limited') end
            lastRequest[src] = now
        end

        local ped = GetPlayerPed(src)
        if not ped or ped == 0 then return refuse('no ped') end
        local hash = limited and allowedModel(model)
        if limited and not hash then return refuse('model not allowed') end
        if not limited then
            hash = type(model) == 'string' and joaat(model) or model
            if not (finite(hash) and (type(model) ~= 'string' or model:match('^[%w_]+$'))) then return refuse('bad model') end
        end

        local position, origin = resolveCoords(ped, coords)
        if not position then return refuse('bad coords') end
        if limited and distance(position, origin) > (tonumber(settings.maxDistance) or 75.0) then
            return refuse('too far')
        end

        local vehicle = create(src, hash, position, warp == true)
        if not vehicle or not DoesEntityExist(vehicle) then return refuse('spawn failed') end
        if limited then trackSpawn(src, vehicle) end
        grantKeys(src, vehicle)
        audit(src, callbackName, { model = tostring(model), plate = GetVehicleNumberPlateText(vehicle) })
        cb(NetworkGetNetworkIdFromEntity(vehicle))
    end
end

F.CreateCallback('QBCore:Server:SpawnVehicle', handle('QBCore:Server:SpawnVehicle', function(src, hash, position, warp)
    return F.SpawnVehicle(src, hash, position, warp)
end))
F.CreateCallback('QBCore:Server:CreateVehicle', handle('QBCore:Server:CreateVehicle', function(src, hash, position, warp)
    return F.CreateAutomobile(src, hash, position, warp)
end))

AddEventHandler('qbcore:server:playerDropped', function(src)
    lastRequest[src] = nil
    local list = live[src]
    live[src] = nil
    if list and settings.deleteOnDrop ~= false then
        for _, vehicle in ipairs(list) do
            if DoesEntityExist(vehicle) then DeleteEntity(vehicle) end
        end
    end
end)
