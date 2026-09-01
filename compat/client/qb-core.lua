-- compat/client/qb-core.lua -- the client half of the QBCore object, exposed via
-- exports['qb-core']:GetCoreObject() AND, like real qb-core, as one direct
-- export per function (exports['qb-core']:Notify(...)). Two implementation
-- strategies are used, mirroring real qb-core's own client/functions.lua:
--   * Self-contained CFX-native helpers are PORTED near-verbatim from real
--     qb-core -- there is nothing qb-core-specific in them, so a faithful copy
--     is safer than a re-derivation.
--   * The handful that touch player/UI state (GetPlayerData, HasItem, Notify,
--     Progressbar) are THIN FORWARDS to qblib (QB.*) / our replicated mirror --
--     the whole point of building on qblib.

local function provideExport(providedResource, exportName, func)
    AddEventHandler(('__cfx_export_%s_%s'):format(providedResource, exportName), function(setCB)
        setCB(func)
    end)
end

local F = QBCore.Functions

-- Notify type strings differ between realms: real qb-core passes 'primary' and
-- assorted freeform types straight into its NUI, whereas qblib validates
-- against info/success/warning/error and DROPS (logs) anything else. Map the
-- common qb-core types onto qblib's set so a legacy Notify('primary') still
-- shows rather than silently vanishing; unknown types fall back to 'info'.
local NOTIFY_TYPE_MAP = {
    primary = 'info',
    inform  = 'info',
    info    = 'info',
    success = 'success',
    warning = 'warning',
    error   = 'error',
}

-- Callbacks ------------------------------------------------------------------

QBCore.ServerCallbacks = QBCore.ServerCallbacks or {}

-- legacyClientCallbacks is CreateClientCallback's single source of truth --
-- mirrors legacyCallbacks in compat/server/qb-core.lua. CreateClientCallback
-- stores the handler here (keyed by name); both the qblib-registered wrapper
-- below AND the raw QBCore:Client:TriggerClientCallback net event handler
-- look the CURRENT handler up from this table at dispatch time instead of
-- closing over it, so a later CreateClientCallback call for the same name (a
-- legitimate resource restart) updates what both transports invoke.
local legacyClientCallbacks = {}

-- Real qb-core stores this in QBCore.ClientCallbacks (server-side) and fires
-- it from the QBCore:Client:TriggerClientCallback net event -- the raw wire
-- handled below. We ALSO keep registering with qblib's QB.callback so a
-- cross-resource caller that talks to QB.callback.trigger directly (rather
-- than through QBCore.Functions.TriggerClientCallback) still reaches this
-- handler; see compat/server/qb-core.lua's TriggerClientCallback comment for
-- why the SERVER trigger itself now speaks the raw wire exclusively instead
-- of also going through qblib (it would double-invoke this handler otherwise).
--
-- Real QBCore hands the legacy handler a RESPONDER as its first argument --
-- function(cb, ...) ... cb(result) end -- not a value to return. qblib's
-- QB.callback.register instead ships back whatever the registered function
-- RETURNS, same mismatch (and same fix: bridge via a promise + timeout) as
-- the server's CreateCallback above.
function F.CreateClientCallback(name, handler)
    legacyClientCallbacks[name] = handler
    QB.callback.register(name, function(...)
        local p = promise.new()
        local settled = false

        local function respond(...)
            if settled then return end
            settled = true
            p:resolve(table.pack(...))
        end

        -- Dispatch through legacyClientCallbacks[name], NOT the `handler`
        -- upvalue -- see the table's comment above.
        legacyClientCallbacks[name](respond, ...)

        CreateThread(function()
            Wait(Config.compat.callbackTimeoutMs or 5000)
            respond()
        end)

        local results = Citizen.Await(p)
        return table.unpack(results, 1, results.n)
    end)
end

-- Raw wire, server->client leg: the server's TriggerClientCallback (raw wire
-- exclusively -- see compat/server/qb-core.lua) delivers the request here.
-- Looks up the handler CreateClientCallback registered and invokes it with a
-- responder that replies over the matching raw event.
RegisterNetEvent('QBCore:Client:TriggerClientCallback', function(name, ...)
    if type(name) ~= 'string' then return end
    local handler = legacyClientCallbacks[name]
    if not handler then return end

    local function respond(...)
        TriggerServerEvent('QBCore:Server:TriggerClientCallback', name, ...)
    end

    local ok, err = pcall(handler, respond, ...)
    if not ok then
        print(('^1[qbcore:qb-core-bridge]^7 legacy client callback %q raised an error: %s'):format(tostring(name), tostring(err)))
    end
end)

-- Use qb-core's native callback wire for legacy callers. Routing this through
-- qblib's promise-valued export makes a callback timeout surface as an export
-- exception before the legacy callback can receive its normal nil result.
-- Arg shape matches real: (name, cb, ...).
--
-- ALSO stores into QBCore.ServerCallbacks[name], matching upstream's own
-- side effect of TriggerCallback, so a raw reply (or a script that pokes
-- ServerCallbacks directly) finds the expected handler.
function F.TriggerCallback(name, cb, ...)
    if cb then QBCore.ServerCallbacks[name] = cb end
    TriggerServerEvent('QBCore:Server:TriggerCallback', name, ...)
end

-- Raw wire, client->server REPLY leg: a legacy script that fired
-- QBCore:Server:TriggerCallback directly (skipping our TriggerCallback) gets
-- its answer here. Pop-then-clear so a stray duplicate reply can't invoke a
-- stale entry a second time.
RegisterNetEvent('QBCore:Client:TriggerCallback', function(name, ...)
    if type(name) ~= 'string' then return end
    local cb = QBCore.ServerCallbacks[name]
    QBCore.ServerCallbacks[name] = nil
    if cb then cb(...) end
end)

-- Not part of real qb-core's CLIENT surface, but kept as a harmless alias some
-- of our resources already call; it registers the same way CreateClientCallback
-- does, so it needs the same responder/promise bridge.
function F.CreateCallback(name, handler) F.CreateClientCallback(name, handler) end

-- Player ---------------------------------------------------------------------

-- Real returns QBCore.PlayerData; if cb is supplied it calls cb(data) too.
-- QBCore.PlayerData itself is kept in sync by modules/replication/client.lua
-- (the same place the legacy QBCore:Player:SetPlayerData event fires from --
-- see its comment), already legacy-shaped (zero-based job/gang grade.level).
function F.GetPlayerData(cb)
    local data = QBCore.PlayerData
    if cb then cb(data) end
    return data
end

---Returns the full character name from the replicated mirror.
---@return string
function F.GetName()
    local charinfo = Core.replication.getData({ 'charinfo' }) or {}
    return (charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')
end

function F.GetCoords(entity)
    local coords = GetEntityCoords(entity)
    return vector4(coords.x, coords.y, coords.z, GetEntityHeading(entity))
end

-- Real forwards to exports['qb-inventory']:HasItem. Ours forwards to qbinventory
-- (which also answers the qb-inventory export identity) when it is running, and
-- otherwise falls back to scanning the replicated items table so HasItem still
-- returns a sane answer without the inventory resource present.
function F.HasItem(items, amount)
    if GetResourceState('qbinventory') == 'started' then
        return exports.qbinventory:HasItem(items, amount)
    end
    local invItems = Core.replication.getData({ 'items' }) or {}
    local function count(name)
        local n = 0
        for _, item in pairs(invItems) do
            if item and item.name == name then n = n + (item.amount or 0) end
        end
        return n
    end
    if type(items) == 'table' then
        for _, name in ipairs(items) do
            if count(name) < (amount or 1) then return false end
        end
        return true
    end
    return count(items) >= (amount or 1)
end

---@param entity number - The entity to look at
---@param timeout number - The time in milliseconds before the function times out
---@param speed number - The speed at which the entity should turn
---@return number - The time at which the entity was looked at
function F.LookAtEntity(entity, timeout, speed)
    local involved = GetInvokingResource()
    if not DoesEntityExist(entity) then
        return involved .. ' :^1  Entity does not exist'
    end
    if type(entity) ~= 'number' then
        return involved .. ' :^1  Entity must be a number'
    end
    if type(speed) ~= 'number' then
        return involved .. ' :^1  Speed must be a number'
    end
    if speed > 5.0 then speed = 5.0 end
    if timeout > 5000 then timeout = 5000 end
    local ped = PlayerPedId()
    local playerPos = GetEntityCoords(ped)
    local targetPos = GetEntityCoords(entity)
    local dx = targetPos.x - playerPos.x
    local dy = targetPos.y - playerPos.y
    local targetHeading = GetHeadingFromVector_2d(dx, dy)
    local turnSpeed
    local startTimeout = GetGameTimer()
    while true do
        local currentHeading = GetEntityHeading(ped)
        local diff = targetHeading - currentHeading
        if math.abs(diff) < 2 then
            break
        end
        if diff < -180 then
            diff = diff + 360
        elseif diff > 180 then
            diff = diff - 360
        end
        turnSpeed = speed + (2.5 - speed) * (1 - math.abs(diff) / 180)
        if diff > 0 then
            currentHeading = currentHeading + turnSpeed
        else
            currentHeading = currentHeading - turnSpeed
        end
        SetEntityHeading(ped, currentHeading)
        Wait(0)
        if (startTimeout + timeout) < GetGameTimer() then break end
    end
    SetEntityHeading(ped, targetHeading)
end

-- Function to run an animation
--- @param animDict string: The name of the animation dictionary
--- @param animName string - The name of the animation within the dictionary
--- @param upperbodyOnly boolean - If true, the animation will only affect the upper body of the ped
--- @param duration number - The duration of the animation in milliseconds. -1 will play the animation indefinitely
--- @return number - The timestamp indicating when the animation concluded.
function F.PlayAnim(animDict, animName, upperbodyOnly, duration)
    local invoked = GetInvokingResource()
    local animPromise = promise.new()
    if type(animDict) ~= 'string' or type(animName) ~= 'string' then
        animPromise:reject(invoked .. ' :^1  Wrong type for animDict or animName')
        return animPromise.value
    end
    if not DoesAnimDictExist(animDict) then
        animPromise:reject(invoked .. ' :^1  Animation dictionary does not exist')
        return animPromise.value
    end
    local flags = upperbodyOnly and 16 or 0
    local runTime = duration or -1
    if runTime == -1 then flags = 49 end
    local ped = PlayerPedId()
    local start = GetGameTimer()
    while not HasAnimDictLoaded(animDict) do
        RequestAnimDict(animDict)
        if (GetGameTimer() - start) > 5000 then
            animPromise:reject(invoked .. ' :^1  Animation dictionary failed to load')
            return animPromise.value
        end
        Wait(1)
    end
    TaskPlayAnim(ped, animDict, animName, 8.0, 8.0, runTime, flags, 0, true, true, true)
    Wait(10) -- Wait a bit for the animation to start, then check if it exists
    local currentTime = GetAnimDuration(animDict, animName)
    if currentTime == 0 then
        animPromise:reject(invoked .. ' :^1  Animation does not exist')
        return animPromise.value
    end
    local fullDuration = currentTime * 1000
    local waitTime = duration and math.min(duration, fullDuration) or fullDuration
    Wait(waitTime)
    RemoveAnimDict(animDict)
    animPromise:resolve(currentTime)
    return animPromise.value
end

function F.IsWearingGloves()
    local ped = PlayerPedId()
    local armIndex = GetPedDrawableVariation(ped, 3)
    local model = GetEntityModel(ped)
    -- Guarded: our QBCore.Shared doesn't seed the MaleNoGloves/FemaleNoGloves
    -- tables, so treat a missing table as "no known no-glove indices" (returns
    -- true) rather than erroring on a nil index.
    if model == GetHashKey('mp_m_freemode_01') then
        if (QBCore.Shared.MaleNoGloves or {})[armIndex] then
            return false
        end
    else
        if (QBCore.Shared.FemaleNoGloves or {})[armIndex] then
            return false
        end
    end
    return true
end

-- NUI Calls ------------------------------------------------------------------

-- Real qb-core SendNUIMessage's its own notify. We forward to qblib's notifier
-- instead. The full real signature (text, texttype, length, icon) is honoured,
-- including the table form of `text` ({ text=, caption= }); caption maps onto
-- qblib's title.
function F.Notify(text, texttype, length, icon)
    local payload = {
        type = NOTIFY_TYPE_MAP[texttype] or 'info',
        duration = length or 5000,
        icon = icon,
    }
    if type(text) == 'table' then
        payload.message = text.text or 'Placeholder'
        payload.title = text.caption
    else
        payload.message = text
    end
    QB.notify.send(payload)
end

-- Real qb-core defers to the standalone `progressbar` resource. We forward to
-- qblib's progressbar instead. The full real arg list is accepted; the
-- disableControls, animation, prop and propTwo tables are translated to
-- qblib's shapes. QB.progressbar.start is blocking, so it's run in a thread
-- to keep Progressbar non-blocking like real qb-core, with onFinish/onCancel
-- driven off its completion result.
function F.Progressbar(name, label, duration, useWhileDead, canCancel, disableControls, animation, prop, propTwo, onFinish, onCancel)
    local payload = {
        label = label,
        duration = duration,
        canCancel = canCancel,
    }
    if disableControls then
        payload.disable = {
            move = disableControls.disableMovement,
            car = disableControls.disableCarMovement,
            combat = disableControls.disableCombat,
        }
    end
    if animation and animation.animDict and animation.anim then
        payload.anim = {
            dict = animation.animDict,
            clip = animation.anim,
            flag = animation.flags,
        }
    end

    local props = {}
    local function addLegacyProp(legacyProp)
        if type(legacyProp) == 'table' and legacyProp.model ~= nil then
            props[#props + 1] = {
                model = legacyProp.model,
                bone = legacyProp.bone,
                offset = legacyProp.coords,
                rotation = legacyProp.rotation,
                softPinning = true,
                collision = true,
                rotationOrder = 0,
                syncRotation = true,
            }
        end
    end
    addLegacyProp(prop)
    addLegacyProp(propTwo)
    if #props > 0 then payload.props = props end

    CreateThread(function()
        local completed = QB.progressbar.start(payload)
        if completed then
            if onFinish then onFinish() end
        else
            if onCancel then onCancel() end
        end
    end)
end

-- World Getters --------------------------------------------------------------

function F.GetVehicles()
    return GetGamePool('CVehicle')
end

function F.GetObjects()
    return GetGamePool('CObject')
end

function F.GetPlayers()
    return GetActivePlayers()
end

-- ped->playerId mapping the same way modules/closest/client.lua does -- QB.world
-- deals in ped handles for entityType 'player', but qb-core's contract here is
-- player ids.
local function pedToPlayerId(ped)
    for _, playerId in ipairs(GetActivePlayers()) do
        if GetPlayerPed(playerId) == ped then return playerId end
    end
    return nil
end

function F.GetPlayersFromCoords(coords, distance)
    if coords then
        coords = type(coords) == 'table' and vec3(coords.x, coords.y, coords.z) or coords
    else
        coords = GetEntityCoords(PlayerPedId())
    end
    local matches = QB.world.getNearbyEntities('player', coords, distance or 5)
    local closePlayers = {}
    for i = 1, #matches do
        local playerId = pedToPlayerId(matches[i].entity)
        if playerId then closePlayers[#closePlayers + 1] = playerId end
    end
    return closePlayers
end

-- Returns (playerId, distance) -- the first value is a PLAYER ID, not an entity
-- handle. This is the real qb-core signature (ported verbatim), NOT
-- QB.world.getClosestEntity's (entity, coords, distance) -- see AGENTS.md's
-- "thin forwards to QB.*, not reimplementations" for why this still forwards.
function F.GetClosestPlayer(coords)
    if coords then
        coords = type(coords) == 'table' and vec3(coords.x, coords.y, coords.z) or coords
    else
        coords = GetEntityCoords(PlayerPedId())
    end
    local entity, _, distance = QB.world.getClosestEntity('player', coords, {
        excludeEntities = { PlayerPedId() },
    })
    if not entity then return -1, -1 end
    return pedToPlayerId(entity) or -1, distance
end

function F.GetPeds(ignoreList)
    local pedPool = GetGamePool('CPed')
    local peds = {}
    local ignoreTable = {}
    ignoreList = ignoreList or {}
    for i = 1, #ignoreList do
        ignoreTable[ignoreList[i]] = true
    end
    for i = 1, #pedPool do
        if not ignoreTable[pedPool[i]] then
            peds[#peds + 1] = pedPool[i]
        end
    end
    return peds
end

-- GetClosestPed/Vehicle/Object return an entity handle (not a converted id),
-- so unlike GetClosestPlayer these forward straight to QB.world.getClosestEntity
-- -- see AGENTS.md's "thin forwards to QB.*, not reimplementations".
function F.GetClosestPed(coords, ignoreList)
    if coords then
        coords = type(coords) == 'table' and vec3(coords.x, coords.y, coords.z) or coords
    else
        coords = GetEntityCoords(PlayerPedId())
    end
    local entity, _, distance = QB.world.getClosestEntity('ped', coords, { excludeEntities = ignoreList })
    return entity or -1, distance or -1
end

function F.GetClosestVehicle(coords)
    if coords then
        coords = type(coords) == 'table' and vec3(coords.x, coords.y, coords.z) or coords
    else
        coords = GetEntityCoords(PlayerPedId())
    end
    local entity, _, distance = QB.world.getClosestEntity('vehicle', coords)
    return entity or -1, distance or -1
end

function F.GetClosestObject(coords)
    if coords then
        coords = type(coords) == 'table' and vec3(coords.x, coords.y, coords.z) or coords
    else
        coords = GetEntityCoords(PlayerPedId())
    end
    local entity, _, distance = QB.world.getClosestEntity('object', coords)
    return entity or -1, distance or -1
end

-- Vehicle --------------------------------------------------------------------

function F.LoadModel(model, timeout)
    timeout = timeout or 5000
    local modelName = model
    if type(modelName) ~= 'number' then modelName = joaat(model) end
    if HasModelLoaded(modelName) then return true, model end

    if not IsModelValid(modelName) and not IsModelInCdimage(modelName) then
        print(('[QBCore] Model does not exist: %s'):format(modelName or model))
        return false, modelName
    end

    RequestModel(modelName)
    local count = GetGameTimer() + timeout
    while not HasModelLoaded(modelName) and GetGameTimer() < count do
        Wait(0)
    end
    return HasModelLoaded(modelName), modelName
end

function F.SpawnVehicle(model, cb, coords, isnetworked, teleportInto)
    local ped = PlayerPedId()
    model = type(model) == 'string' and joaat(model) or model
    if not IsModelInCdimage(model) then return end
    if coords then
        coords = type(coords) == 'table' and vec3(coords.x, coords.y, coords.z) or coords
    else
        coords = GetEntityCoords(ped)
    end
    isnetworked = isnetworked == nil or isnetworked
    F.LoadModel(model)
    local veh = CreateVehicle(model, coords.x, coords.y, coords.z, coords.w, isnetworked, false)
    local netid = NetworkGetNetworkIdFromEntity(veh)
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    SetNetworkIdCanMigrate(netid, true)
    SetVehicleNeedsToBeHotwired(veh, false)
    SetVehRadioStation(veh, 'OFF')
    SetVehicleFuelLevel(veh, 100.0)
    SetModelAsNoLongerNeeded(model)
    if teleportInto then TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1) end
    if cb then cb(veh) end
end

function F.DeleteVehicle(vehicle)
    SetEntityAsMissionEntity(vehicle, true, true)
    DeleteVehicle(vehicle)
end

function F.GetPlate(vehicle)
    if vehicle == 0 then return end
    return QBCore.Shared.Trim(GetVehicleNumberPlateText(vehicle))
end

function F.GetVehicleLabel(vehicle)
    if vehicle == nil or vehicle == 0 then return end
    return GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)))
end

function F.GetVehicleProperties(vehicle)
    if DoesEntityExist(vehicle) then
        local pearlescentColor, wheelColor = GetVehicleExtraColours(vehicle)

        local colorPrimary, colorSecondary = GetVehicleColours(vehicle)
        if GetIsVehiclePrimaryColourCustom(vehicle) then
            local r, g, b = GetVehicleCustomPrimaryColour(vehicle)
            colorPrimary = { r, g, b }
        end

        if GetIsVehicleSecondaryColourCustom(vehicle) then
            local r, g, b = GetVehicleCustomSecondaryColour(vehicle)
            colorSecondary = { r, g, b }
        end

        local extras = {}
        for extraId = 0, 12 do
            if DoesExtraExist(vehicle, extraId) then
                local state = IsVehicleExtraTurnedOn(vehicle, extraId) == 1
                extras[tostring(extraId)] = state
            end
        end

        local modLivery = GetVehicleMod(vehicle, 48)
        if GetVehicleMod(vehicle, 48) == -1 and GetVehicleLivery(vehicle) ~= 0 then
            modLivery = GetVehicleLivery(vehicle)
        end

        local tireHealth = {}
        for i = 0, 3 do
            tireHealth[i] = GetVehicleWheelHealth(vehicle, i)
        end

        local tireBurstState = {}
        for i = 0, 5 do
            tireBurstState[i] = IsVehicleTyreBurst(vehicle, i, false)
        end

        local tireBurstCompletely = {}
        for i = 0, 5 do
            tireBurstCompletely[i] = IsVehicleTyreBurst(vehicle, i, true)
        end

        local windowStatus = {}
        for i = 0, 7 do
            windowStatus[i] = IsVehicleWindowIntact(vehicle, i) == 1
        end

        local doorStatus = {}
        for i = 0, 5 do
            doorStatus[i] = IsVehicleDoorDamaged(vehicle, i) == 1
        end

        local xenonColor
        local hasCustom, r, g, b = GetVehicleXenonLightsCustomColor(vehicle)
        if hasCustom then
            xenonColor = table.pack(r, g, b)
        else
            xenonColor = GetVehicleXenonLightsColor(vehicle)
        end

        return {
            model = GetEntityModel(vehicle),
            plate = F.GetPlate(vehicle),
            plateIndex = GetVehicleNumberPlateTextIndex(vehicle),
            bodyHealth = QBCore.Shared.Round(GetVehicleBodyHealth(vehicle), 0.1),
            engineHealth = QBCore.Shared.Round(GetVehicleEngineHealth(vehicle), 0.1),
            tankHealth = QBCore.Shared.Round(GetVehiclePetrolTankHealth(vehicle), 0.1),
            fuelLevel = QBCore.Shared.Round(GetVehicleFuelLevel(vehicle), 0.1),
            dirtLevel = QBCore.Shared.Round(GetVehicleDirtLevel(vehicle), 0.1),
            oilLevel = QBCore.Shared.Round(GetVehicleOilLevel(vehicle), 0.1),
            color1 = colorPrimary,
            color2 = colorSecondary,
            pearlescentColor = pearlescentColor,
            dashboardColor = GetVehicleDashboardColour(vehicle),
            wheelColor = wheelColor,
            wheels = GetVehicleWheelType(vehicle),
            wheelSize = GetVehicleWheelSize(vehicle),
            wheelWidth = GetVehicleWheelWidth(vehicle),
            tireHealth = tireHealth,
            tireBurstState = tireBurstState,
            tireBurstCompletely = tireBurstCompletely,
            windowTint = GetVehicleWindowTint(vehicle),
            windowStatus = windowStatus,
            doorStatus = doorStatus,
            neonEnabled = {
                IsVehicleNeonLightEnabled(vehicle, 0),
                IsVehicleNeonLightEnabled(vehicle, 1),
                IsVehicleNeonLightEnabled(vehicle, 2),
                IsVehicleNeonLightEnabled(vehicle, 3)
            },
            neonColor = table.pack(GetVehicleNeonLightsColour(vehicle)),
            interiorColor = GetVehicleInteriorColour(vehicle),
            extras = extras,
            tyreSmokeColor = table.pack(GetVehicleTyreSmokeColor(vehicle)),
            xenonColor = xenonColor,
            modSpoilers = GetVehicleMod(vehicle, 0),
            modFrontBumper = GetVehicleMod(vehicle, 1),
            modRearBumper = GetVehicleMod(vehicle, 2),
            modSideSkirt = GetVehicleMod(vehicle, 3),
            modExhaust = GetVehicleMod(vehicle, 4),
            modFrame = GetVehicleMod(vehicle, 5),
            modGrille = GetVehicleMod(vehicle, 6),
            modHood = GetVehicleMod(vehicle, 7),
            modFender = GetVehicleMod(vehicle, 8),
            modRightFender = GetVehicleMod(vehicle, 9),
            modRoof = GetVehicleMod(vehicle, 10),
            modEngine = GetVehicleMod(vehicle, 11),
            modBrakes = GetVehicleMod(vehicle, 12),
            modTransmission = GetVehicleMod(vehicle, 13),
            modHorns = GetVehicleMod(vehicle, 14),
            modSuspension = GetVehicleMod(vehicle, 15),
            modArmor = GetVehicleMod(vehicle, 16),
            modKit17 = GetVehicleMod(vehicle, 17),
            modTurbo = IsToggleModOn(vehicle, 18),
            modKit19 = GetVehicleMod(vehicle, 19),
            modSmokeEnabled = IsToggleModOn(vehicle, 20),
            modKit21 = GetVehicleMod(vehicle, 21),
            modXenon = IsToggleModOn(vehicle, 22),
            modFrontWheels = GetVehicleMod(vehicle, 23),
            modBackWheels = GetVehicleMod(vehicle, 24),
            modCustomTiresF = GetVehicleModVariation(vehicle, 23),
            modCustomTiresR = GetVehicleModVariation(vehicle, 24),
            modPlateHolder = GetVehicleMod(vehicle, 25),
            modVanityPlate = GetVehicleMod(vehicle, 26),
            modTrimA = GetVehicleMod(vehicle, 27),
            modOrnaments = GetVehicleMod(vehicle, 28),
            modDashboard = GetVehicleMod(vehicle, 29),
            modDial = GetVehicleMod(vehicle, 30),
            modDoorSpeaker = GetVehicleMod(vehicle, 31),
            modSeats = GetVehicleMod(vehicle, 32),
            modSteeringWheel = GetVehicleMod(vehicle, 33),
            modShifterLeavers = GetVehicleMod(vehicle, 34),
            modAPlate = GetVehicleMod(vehicle, 35),
            modSpeakers = GetVehicleMod(vehicle, 36),
            modTrunk = GetVehicleMod(vehicle, 37),
            modHydrolic = GetVehicleMod(vehicle, 38),
            modEngineBlock = GetVehicleMod(vehicle, 39),
            modAirFilter = GetVehicleMod(vehicle, 40),
            modStruts = GetVehicleMod(vehicle, 41),
            modArchCover = GetVehicleMod(vehicle, 42),
            modAerials = GetVehicleMod(vehicle, 43),
            modTrimB = GetVehicleMod(vehicle, 44),
            modTank = GetVehicleMod(vehicle, 45),
            modWindows = GetVehicleMod(vehicle, 46),
            modKit47 = GetVehicleMod(vehicle, 47),
            modLivery = modLivery,
            modKit49 = GetVehicleMod(vehicle, 49),
            liveryRoof = GetVehicleRoofLivery(vehicle),
        }
    else
        return
    end
end

function F.SetVehicleProperties(vehicle, props)
    if DoesEntityExist(vehicle) then
        if props.extras then
            for id, enabled in pairs(props.extras) do
                if enabled then
                    SetVehicleExtra(vehicle, tonumber(id), 0)
                else
                    SetVehicleExtra(vehicle, tonumber(id), 1)
                end
            end
        end

        local colorPrimary, colorSecondary = GetVehicleColours(vehicle)
        local pearlescentColor, wheelColor = GetVehicleExtraColours(vehicle)
        SetVehicleModKit(vehicle, 0)
        if props.plate then
            SetVehicleNumberPlateText(vehicle, props.plate)
        end
        if props.plateIndex then
            SetVehicleNumberPlateTextIndex(vehicle, props.plateIndex)
        end
        if props.bodyHealth then
            SetVehicleBodyHealth(vehicle, props.bodyHealth + 0.0)
        end
        if props.engineHealth then
            SetVehicleEngineHealth(vehicle, props.engineHealth + 0.0)
        end
        if props.tankHealth then
            SetVehiclePetrolTankHealth(vehicle, props.tankHealth + 0.0)
        end
        if props.fuelLevel then
            SetVehicleFuelLevel(vehicle, props.fuelLevel + 0.0)
        end
        if props.dirtLevel then
            SetVehicleDirtLevel(vehicle, props.dirtLevel + 0.0)
        end
        if props.oilLevel then
            SetVehicleOilLevel(vehicle, props.oilLevel + 0.0)
        end
        if props.color1 then
            if type(props.color1) == 'number' then
                ClearVehicleCustomPrimaryColour(vehicle)
                SetVehicleColours(vehicle, props.color1, colorSecondary)
            else
                SetVehicleCustomPrimaryColour(vehicle, props.color1[1], props.color1[2], props.color1[3])
            end
        end
        if props.color2 then
            if type(props.color2) == 'number' then
                ClearVehicleCustomSecondaryColour(vehicle)
                SetVehicleColours(vehicle, type(props.color1) == 'number' and props.color1 or colorPrimary, props.color2)
            else
                SetVehicleCustomSecondaryColour(vehicle, props.color2[1], props.color2[2], props.color2[3])
            end
        end
        if props.pearlescentColor then
            SetVehicleExtraColours(vehicle, props.pearlescentColor, wheelColor)
        end
        if props.interiorColor then
            SetVehicleInteriorColor(vehicle, props.interiorColor)
        end
        if props.dashboardColor then
            SetVehicleDashboardColour(vehicle, props.dashboardColor)
        end
        if props.wheelColor then
            SetVehicleExtraColours(vehicle, props.pearlescentColor or pearlescentColor, props.wheelColor)
        end
        if props.wheels then
            SetVehicleWheelType(vehicle, props.wheels)
        end
        if props.tireHealth then
            for wheelIndex, health in pairs(props.tireHealth) do
                SetVehicleWheelHealth(vehicle, wheelIndex, health)
            end
        end
        if props.tireBurstState then
            for wheelIndex, burstState in pairs(props.tireBurstState) do
                if burstState then
                    SetVehicleTyreBurst(vehicle, tonumber(wheelIndex), false, 1000.0)
                end
            end
        end
        if props.tireBurstCompletely then
            for wheelIndex, burstState in pairs(props.tireBurstCompletely) do
                if burstState then
                    SetVehicleTyreBurst(vehicle, tonumber(wheelIndex), true, 1000.0)
                end
            end
        end
        if props.windowTint then
            SetVehicleWindowTint(vehicle, props.windowTint)
        end
        if props.windowStatus then
            for windowIndex, smashWindow in pairs(props.windowStatus) do
                if not smashWindow then SmashVehicleWindow(vehicle, windowIndex) end
            end
        end
        if props.doorStatus then
            for doorIndex, breakDoor in pairs(props.doorStatus) do
                if breakDoor then
                    SetVehicleDoorBroken(vehicle, tonumber(doorIndex), true)
                end
            end
        end
        if props.neonEnabled then
            SetVehicleNeonLightEnabled(vehicle, 0, props.neonEnabled[1])
            SetVehicleNeonLightEnabled(vehicle, 1, props.neonEnabled[2])
            SetVehicleNeonLightEnabled(vehicle, 2, props.neonEnabled[3])
            SetVehicleNeonLightEnabled(vehicle, 3, props.neonEnabled[4])
        end
        if props.neonColor then
            SetVehicleNeonLightsColour(vehicle, props.neonColor[1], props.neonColor[2], props.neonColor[3])
        end
        if props.interiorColor then
            SetVehicleInteriorColour(vehicle, props.interiorColor)
        end
        if props.wheelSize then
            SetVehicleWheelSize(vehicle, props.wheelSize)
        end
        if props.wheelWidth then
            SetVehicleWheelWidth(vehicle, props.wheelWidth)
        end
        if props.tyreSmokeColor then
            SetVehicleTyreSmokeColor(vehicle, props.tyreSmokeColor[1], props.tyreSmokeColor[2], props.tyreSmokeColor[3])
        end
        if props.modSpoilers then
            SetVehicleMod(vehicle, 0, props.modSpoilers, false)
        end
        if props.modFrontBumper then
            SetVehicleMod(vehicle, 1, props.modFrontBumper, false)
        end
        if props.modRearBumper then
            SetVehicleMod(vehicle, 2, props.modRearBumper, false)
        end
        if props.modSideSkirt then
            SetVehicleMod(vehicle, 3, props.modSideSkirt, false)
        end
        if props.modExhaust then
            SetVehicleMod(vehicle, 4, props.modExhaust, false)
        end
        if props.modFrame then
            SetVehicleMod(vehicle, 5, props.modFrame, false)
        end
        if props.modGrille then
            SetVehicleMod(vehicle, 6, props.modGrille, false)
        end
        if props.modHood then
            SetVehicleMod(vehicle, 7, props.modHood, false)
        end
        if props.modFender then
            SetVehicleMod(vehicle, 8, props.modFender, false)
        end
        if props.modRightFender then
            SetVehicleMod(vehicle, 9, props.modRightFender, false)
        end
        if props.modRoof then
            SetVehicleMod(vehicle, 10, props.modRoof, false)
        end
        if props.modEngine then
            SetVehicleMod(vehicle, 11, props.modEngine, false)
        end
        if props.modBrakes then
            SetVehicleMod(vehicle, 12, props.modBrakes, false)
        end
        if props.modTransmission then
            SetVehicleMod(vehicle, 13, props.modTransmission, false)
        end
        if props.modHorns then
            SetVehicleMod(vehicle, 14, props.modHorns, false)
        end
        if props.modSuspension then
            SetVehicleMod(vehicle, 15, props.modSuspension, false)
        end
        if props.modArmor then
            SetVehicleMod(vehicle, 16, props.modArmor, false)
        end
        if props.modKit17 then
            SetVehicleMod(vehicle, 17, props.modKit17, false)
        end
        if props.modTurbo then
            ToggleVehicleMod(vehicle, 18, props.modTurbo)
        end
        if props.modKit19 then
            SetVehicleMod(vehicle, 19, props.modKit19, false)
        end
        if props.modSmokeEnabled then
            ToggleVehicleMod(vehicle, 20, props.modSmokeEnabled)
        end
        if props.modKit21 then
            SetVehicleMod(vehicle, 21, props.modKit21, false)
        end
        if props.modXenon then
            ToggleVehicleMod(vehicle, 22, props.modXenon)
        end
        if props.xenonColor then
            if type(props.xenonColor) == 'table' then
                SetVehicleXenonLightsCustomColor(vehicle, props.xenonColor[1], props.xenonColor[2], props.xenonColor[3])
            else
                SetVehicleXenonLightsColor(vehicle, props.xenonColor)
            end
        end
        if props.modFrontWheels then
            SetVehicleMod(vehicle, 23, props.modFrontWheels, false)
        end
        if props.modBackWheels then
            SetVehicleMod(vehicle, 24, props.modBackWheels, false)
        end
        if props.modCustomTiresF then
            SetVehicleMod(vehicle, 23, props.modFrontWheels, props.modCustomTiresF)
        end
        if props.modCustomTiresR then
            SetVehicleMod(vehicle, 24, props.modBackWheels, props.modCustomTiresR)
        end
        if props.modPlateHolder then
            SetVehicleMod(vehicle, 25, props.modPlateHolder, false)
        end
        if props.modVanityPlate then
            SetVehicleMod(vehicle, 26, props.modVanityPlate, false)
        end
        if props.modTrimA then
            SetVehicleMod(vehicle, 27, props.modTrimA, false)
        end
        if props.modOrnaments then
            SetVehicleMod(vehicle, 28, props.modOrnaments, false)
        end
        if props.modDashboard then
            SetVehicleMod(vehicle, 29, props.modDashboard, false)
        end
        if props.modDial then
            SetVehicleMod(vehicle, 30, props.modDial, false)
        end
        if props.modDoorSpeaker then
            SetVehicleMod(vehicle, 31, props.modDoorSpeaker, false)
        end
        if props.modSeats then
            SetVehicleMod(vehicle, 32, props.modSeats, false)
        end
        if props.modSteeringWheel then
            SetVehicleMod(vehicle, 33, props.modSteeringWheel, false)
        end
        if props.modShifterLeavers then
            SetVehicleMod(vehicle, 34, props.modShifterLeavers, false)
        end
        if props.modAPlate then
            SetVehicleMod(vehicle, 35, props.modAPlate, false)
        end
        if props.modSpeakers then
            SetVehicleMod(vehicle, 36, props.modSpeakers, false)
        end
        if props.modTrunk then
            SetVehicleMod(vehicle, 37, props.modTrunk, false)
        end
        if props.modHydrolic then
            SetVehicleMod(vehicle, 38, props.modHydrolic, false)
        end
        if props.modEngineBlock then
            SetVehicleMod(vehicle, 39, props.modEngineBlock, false)
        end
        if props.modAirFilter then
            SetVehicleMod(vehicle, 40, props.modAirFilter, false)
        end
        if props.modStruts then
            SetVehicleMod(vehicle, 41, props.modStruts, false)
        end
        if props.modArchCover then
            SetVehicleMod(vehicle, 42, props.modArchCover, false)
        end
        if props.modAerials then
            SetVehicleMod(vehicle, 43, props.modAerials, false)
        end
        if props.modTrimB then
            SetVehicleMod(vehicle, 44, props.modTrimB, false)
        end
        if props.modTank then
            SetVehicleMod(vehicle, 45, props.modTank, false)
        end
        if props.modWindows then
            SetVehicleMod(vehicle, 46, props.modWindows, false)
        end
        if props.modKit47 then
            SetVehicleMod(vehicle, 47, props.modKit47, false)
        end
        if props.modLivery then
            SetVehicleMod(vehicle, 48, props.modLivery, false)
            SetVehicleLivery(vehicle, props.modLivery)
        end
        if props.modKit49 then
            SetVehicleMod(vehicle, 49, props.modKit49, false)
        end
        if props.liveryRoof then
            SetVehicleRoofLivery(vehicle, props.liveryRoof)
        end
    end
end

-- Drawing / streaming / misc (ported verbatim from real qb-core) -------------

function F.DrawText(x, y, width, height, scale, r, g, b, a, text)
    SetTextFont(4)
    SetTextScale(scale, scale)
    SetTextColour(r, g, b, a)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x - width / 2, y - height / 2 + 0.005)
end

function F.DrawText3D(x, y, z, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    BeginTextCommandDisplayText('STRING')
    SetTextCentre(true)
    AddTextComponentSubstringPlayerName(text)
    SetDrawOrigin(x, y, z, 0)
    EndTextCommandDisplayText(0.0, 0.0)
    local factor = (string.len(text)) / 370
    DrawRect(0.0, 0.0 + 0.0125, 0.017 + factor, 0.03, 0, 0, 0, 75)
    ClearDrawOrigin()
end

-- Harmless alias kept from our previous compat: some of our resources call
-- Draw3DText(coords, text, opts) with a coords-table signature and route through
-- qblib's drawing module. DrawText3D above is the real qb-core (x, y, z, text)
-- function and MUST exist; this stays only for backward-compat.
function F.Draw3DText(coords, text, opts) QB.drawing.text3d(coords, text, opts) end

function F.RequestAnimDict(animDict, timeout)
    timeout = timeout or 5000
    if HasAnimDictLoaded(animDict) then return true, animDict end
    if not DoesAnimDictExist(animDict) then
        print(('[QBCore] Animation dictionary does not exist: %s'):format(animDict))
        return false, animDict
    end

    RequestAnimDict(animDict)
    local count = GetGameTimer() + timeout
    while not HasAnimDictLoaded(animDict) and GetGameTimer() < count do
        Wait(0)
    end
    return HasAnimDictLoaded(animDict), animDict
end

-- Alias kept from our previous compat -- not a real qb-core function, but some
-- of our resources call it; forwards to qblib's streamer.
function F.LoadAnimDict(dict, cb) QB.stream.loadAnimDict(dict, cb) end

function F.GetClosestBone(entity, list)
    local playerCoords, bone, coords, distance = GetEntityCoords(PlayerPedId())
    for _, element in pairs(list) do
        local boneCoords = GetWorldPositionOfEntityBone(entity, element.id or element)
        local boneDistance = #(playerCoords - boneCoords)
        if not coords then
            bone, coords, distance = element, boneCoords, boneDistance
        elseif distance > boneDistance then
            bone, coords, distance = element, boneCoords, boneDistance
        end
    end
    if not bone then
        bone = { id = GetEntityBoneIndexByName(entity, 'bodyshell'), type = 'remains', name = 'bodyshell' }
        coords = GetWorldPositionOfEntityBone(entity, bone.id)
        distance = #(coords - playerCoords)
    end
    return bone, coords, distance
end

function F.GetBoneDistance(entity, boneType, boneIndex)
    local bone
    if boneType == 1 then
        bone = GetPedBoneIndex(entity, boneIndex)
    else
        bone = GetEntityBoneIndexByName(entity, boneIndex)
    end
    local boneCoords = GetWorldPositionOfEntityBone(entity, bone)
    local playerCoords = GetEntityCoords(PlayerPedId())
    return #(boneCoords - playerCoords)
end

function F.AttachProp(ped, model, boneId, x, y, z, xR, yR, zR, vertex)
    local modelHash = type(model) == 'string' and joaat(model) or model
    local bone = GetPedBoneIndex(ped, boneId)
    F.LoadModel(modelHash)
    local prop = CreateObject(modelHash, 1.0, 1.0, 1.0, 1, 1, 0)
    AttachEntityToEntity(prop, ped, bone, x, y, z, xR, yR, zR, 1, 1, 0, 1, not vertex and 2 or 0, 1)
    SetModelAsNoLongerNeeded(modelHash)
    return prop
end

function F.SpawnClear(coords, radius)
    if coords then
        coords = type(coords) == 'table' and vec3(coords.x, coords.y, coords.z) or coords
    else
        coords = GetEntityCoords(PlayerPedId())
    end
    local vehicles = GetGamePool('CVehicle')
    local closeVeh = {}
    for i = 1, #vehicles, 1 do
        local vehicleCoords = GetEntityCoords(vehicles[i])
        local distance = #(vehicleCoords - coords)
        if distance <= radius then
            closeVeh[#closeVeh + 1] = vehicles[i]
        end
    end
    if #closeVeh > 0 then return false end
    return true
end

function F.LoadAnimSet(animSet, timeout)
    timeout = timeout or 5000
    if HasAnimSetLoaded(animSet) then return true, animSet end
    RequestAnimSet(animSet)

    local count = GetGameTimer() + timeout
    while not HasAnimSetLoaded(animSet) and GetGameTimer() < count do
        Wait(0)
    end

    return HasAnimSetLoaded(animSet), animSet
end

function F.LoadParticleDictionary(dictionary, timeout)
    timeout = timeout or 5000
    if HasNamedPtfxAssetLoaded(dictionary) then return true, dictionary end
    RequestNamedPtfxAsset(dictionary)

    local count = GetGameTimer() + timeout
    while not HasNamedPtfxAssetLoaded(dictionary) and GetGameTimer() < count do
        Wait(0)
    end

    return HasNamedPtfxAssetLoaded(dictionary), dictionary
end

function F.StartParticleAtCoord(dict, ptName, looped, coords, rot, scale, alpha, color, duration)
    if coords then
        coords = type(coords) == 'table' and vec3(coords.x, coords.y, coords.z) or coords
    else
        coords = GetEntityCoords(PlayerPedId())
    end
    F.LoadParticleDictionary(dict)
    UseParticleFxAssetNextCall(dict)
    SetPtfxAssetNextCall(dict)
    local particleHandle
    if looped then
        particleHandle = StartParticleFxLoopedAtCoord(ptName, coords.x, coords.y, coords.z, rot.x, rot.y, rot.z, scale or 1.0)
        if color then
            SetParticleFxLoopedColour(particleHandle, color.r, color.g, color.b, false)
        end
        SetParticleFxLoopedAlpha(particleHandle, alpha or 10.0)
        if duration then
            Wait(duration)
            StopParticleFxLooped(particleHandle, 0)
        end
    else
        SetParticleFxNonLoopedAlpha(alpha or 10.0)
        if color then
            SetParticleFxNonLoopedColour(color.r, color.g, color.b)
        end
        StartParticleFxNonLoopedAtCoord(ptName, coords.x, coords.y, coords.z, rot.x, rot.y, rot.z, scale or 1.0)
    end
    return particleHandle
end

function F.StartParticleOnEntity(dict, ptName, looped, entity, bone, offset, rot, scale, alpha, color, evolution, duration)
    F.LoadParticleDictionary(dict)
    UseParticleFxAssetNextCall(dict)
    local particleHandle, boneID
    if bone and GetEntityType(entity) == 1 then
        boneID = GetPedBoneIndex(entity, bone)
    elseif bone then
        boneID = GetEntityBoneIndexByName(entity, bone)
    end
    if looped then
        if bone then
            particleHandle = StartParticleFxLoopedOnEntityBone(ptName, entity, offset.x, offset.y, offset.z, rot.x, rot.y, rot.z, boneID, scale)
        else
            particleHandle = StartParticleFxLoopedOnEntity(ptName, entity, offset.x, offset.y, offset.z, rot.x, rot.y, rot.z, scale)
        end
        if evolution then
            SetParticleFxLoopedEvolution(particleHandle, evolution.name, evolution.amount, false)
        end
        if color then
            SetParticleFxLoopedColour(particleHandle, color.r, color.g, color.b, false)
        end
        SetParticleFxLoopedAlpha(particleHandle, alpha)
        if duration then
            Wait(duration)
            StopParticleFxLooped(particleHandle, 0)
        end
    else
        SetParticleFxNonLoopedAlpha(alpha or 10.0)
        if color then
            SetParticleFxNonLoopedColour(color.r, color.g, color.b)
        end
        if bone then
            StartParticleFxNonLoopedOnPedBone(ptName, entity, offset.x, offset.y, offset.z, rot.x, rot.y, rot.z, boneID, scale)
        else
            StartParticleFxNonLoopedOnEntity(ptName, entity, offset.x, offset.y, offset.z, rot.x, rot.y, rot.z, scale)
        end
    end
    return particleHandle
end

function F.GetStreetNametAtCoords(coords)
    local streetname1, streetname2 = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    return { main = GetStreetNameFromHashKey(streetname1), cross = GetStreetNameFromHashKey(streetname2) }
end

function F.GetZoneAtCoords(coords)
    return GetLabelText(GetNameOfZone(coords))
end

function F.GetCardinalDirection(entity)
    entity = DoesEntityExist(entity) and entity or PlayerPedId()
    if DoesEntityExist(entity) then
        local heading = GetEntityHeading(entity)
        if ((heading >= 0 and heading < 45) or (heading >= 315 and heading < 360)) then
            return 'North'
        elseif (heading >= 45 and heading < 135) then
            return 'West'
        elseif (heading >= 135 and heading < 225) then
            return 'South'
        elseif (heading >= 225 and heading < 315) then
            return 'East'
        end
    else
        return 'Cardinal Direction Error'
    end
end

function F.GetCurrentTime()
    local obj = {}
    obj.min = GetClockMinutes()
    obj.hour = GetClockHours()
    if obj.hour <= 12 then
        obj.ampm = 'AM'
    elseif obj.hour >= 13 then
        obj.ampm = 'PM'
        obj.formattedHour = obj.hour - 12
    end
    if obj.min <= 9 then
        obj.formattedMin = '0' .. obj.min
    end
    return obj
end

function F.GetGroundZCoord(coords)
    if not coords then return end

    local retval, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z, 0)
    if retval then
        return vector3(coords.x, coords.y, groundZ)
    else
        return coords
    end
end

function F.GetGroundHash(entity)
    local coords = GetEntityCoords(entity)
    local num = StartShapeTestCapsule(coords.x, coords.y, coords.z + 4, coords.x, coords.y, coords.z - 2.0, 1, 1, entity, 7)
    local retval, success, endCoords, surfaceNormal, materialHash, entityHit = GetShapeTestResultEx(num)
    return materialHash, entityHit, surfaceNormal, endCoords, success, retval
end

-- --- QBCore.Config -----------------------------------------------------------
-- config.lua is a shared_script (loaded identically into both realms -- see
-- fxmanifest.lua), so this is the exact same mapping compat/server/qb-core.lua
-- builds from the same shared `Config` global, at zero network cost. Previously
-- QBCore.Config was populated server-side only, leaving it an empty `{}` here.
QBCore.Config.Money = { MoneyTypes = Config.money.default, PayCheckTimeOut = 10 }
QBCore.Config.Player = { MaxWeight = Config.inventory.maxWeight, MaxInvSlots = Config.inventory.slots }
QBCore.Config.MaxPlayers = GetConvarInt('sv_maxclients', 32)
QBCore.Config.Server = {
    Discord = GetConvar('qb_discord', ''),
    Whitelist = false,
    WhitelistPermission = 'admin',
    Permissions = { 'god', 'admin', 'mod' },
    Closed = false,
    ClosedReason = 'Server Closed',
}
-- Upstream constants some legacy scripts read directly (real qb-core's
-- shared/config.lua). Informational-only here -- they don't drive our own
-- needs-decay loop, which is server-owned on a different cadence -- so these
-- are just hardcoded to match upstream's documented defaults for any legacy
-- script that reads them directly.
QBCore.Config.UpdateInterval = 5
QBCore.Config.StatusInterval = 5000

-- Force the lazy QBCore.Shared data views to materialise as REAL keys, same
-- as the server compat does: a consumer's GetCoreObject() result crosses the
-- export boundary as a msgpack copy that drops the metatable, so a key still
-- hiding behind coreobject.lua's lazy __index would be absent from the copy.
-- The client registries exist by now (RI.create in modules/registry/client.lua,
-- loaded before this file) but may still be EMPTY until the async snapshot
-- arrives -- that's fine: Items/Vehicles/Weapons cache the registry's live
-- `materialised` tables (reseed clears them IN PLACE, references stay stable),
-- and the Jobs/Gangs legacy views re-fill via their 'qbcore:registry:synced'
-- refresh hook when the snapshot lands.
for _, k in ipairs({ 'Items', 'Vehicles', 'Jobs', 'Gangs', 'Weapons' }) do
    local _ = QBCore.Shared[k]
end

-- Direct client exports ------------------------------------------------------
-- Real qb-core ends client/functions.lua with `for fn, func in pairs(QBCore.Functions) do exports(fn, func) end`,
-- exposing every function as exports['qb-core']:Fn(...). We can't call exports()
-- with the qb-core identity from here (we're the qbcore resource), so we use the
-- same __cfx_export identity-hijack helper GetCoreObject uses to register each
-- one under the 'qb-core' export name.
for functionName, func in pairs(QBCore.Functions) do
    if type(func) == 'function' then
        provideExport('qb-core', functionName, func)
    end
end

provideExport('qb-core', 'GetCoreObject', function() return QBCore end)

-- GetShared is a top-level export in real qb-core (shared/main.lua), not a
-- Functions entry, on BOTH realms -- it was previously only registered
-- server-side (compat/server/qb-core.lua), which is why a client script
-- (@qb-recyclejob/client.lua) calling exports['qb-core']:GetShared('Items')
-- got "No such export". Reads QBCore.Shared[namespace], which coreobject.lua's
-- metatable resolves to the live materialised registry table -- identical
-- body to the server compat's copy, including the canonical-casing fallback
-- (real-world legacy scripts don't reliably call this with PascalCase, e.g.
-- qb-recyclejob's OWN client.lua calls GetShared('items')).
local function getShared(namespace, item)
    local ns = QBCore.Shared[namespace]
    if not ns and Core.compat.canonicalSharedNamespace then
        ns = QBCore.Shared[Core.compat.canonicalSharedNamespace(namespace)]
    end
    if not ns then return nil end
    return item and ns[item] or ns
end
provideExport('qb-core', 'GetShared', getShared)

-- Thin per-namespace wrappers around GetShared, mirroring the server compat's
-- copies -- real qb-core exposes these as their own top-level exports too.
-- GetSharedJobs/Gangs go through the SAME getShared('Jobs'/'Gangs') call, so
-- they resolve to the legacy zero-based grade view, not the raw internal one.
provideExport('qb-core', 'GetSharedItems', function() return getShared('Items') end)
provideExport('qb-core', 'GetSharedVehicles', function() return getShared('Vehicles') end)
provideExport('qb-core', 'GetSharedJobs', function() return getShared('Jobs') end)
provideExport('qb-core', 'GetSharedGangs', function() return getShared('Gangs') end)
provideExport('qb-core', 'GetSharedWeapons', function() return getShared('Weapons') end)

-- Upstream qb-core's client/drawtext.lua exports a persistent on-screen prompt
-- family -- exports['qb-core']:DrawText(text, position) / ChangeText /
-- HideText / KeyPressed -- that legacy resources (qb-banking's 'Open Bank'
-- prompt) drive around their own key-press loops. That is a DIFFERENT function
-- from QBCore.Functions.DrawText(x, y, width, height, scale, r, g, b, a, text)
-- above: upstream registers both under the same export name and drawtext.lua
-- loads last, so its 2-arg version wins resolution. Mirror that shadowing by
-- registering AFTER the Functions loop (the last __cfx_export handler's setCB
-- runs last and wins). Rendered as a native per-frame draw rather than
-- upstream's NUI page -- same contract, no UI dependency.
local drawTextState = nil
local drawTextGen = 0

local DRAWTEXT_ANCHORS = {
    left = { x = 0.10, y = 0.50 },
    right = { x = 0.90, y = 0.50 },
    top = { x = 0.50, y = 0.05 },
}

local function compatDrawText(text, position)
    local wasActive = drawTextState ~= nil
    drawTextState = { text = tostring(text or ''), position = position }
    if wasActive then return end

    drawTextGen = drawTextGen + 1
    local gen = drawTextGen
    CreateThread(function()
        while drawTextState and drawTextGen == gen do
            local state = drawTextState
            local anchor = DRAWTEXT_ANCHORS[state.position] or DRAWTEXT_ANCHORS.left
            SetTextFont(4)
            SetTextScale(0.40, 0.40)
            SetTextColour(255, 255, 255, 255)
            SetTextCentre(true)
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName(state.text)
            EndTextCommandDisplayText(anchor.x, anchor.y)
            DrawRect(anchor.x, anchor.y + 0.0125, 0.017 + #state.text / 370, 0.03, 0, 0, 0, 100)
            Wait(0)
        end
    end)
end

local function compatHideText()
    drawTextState = nil
    -- Bump the generation so a draw thread mid-iteration exits even if a new
    -- DrawText immediately restarts the prompt (prevents doubled draw threads).
    drawTextGen = drawTextGen + 1
end

provideExport('qb-core', 'DrawText', compatDrawText)
provideExport('qb-core', 'ChangeText', compatDrawText)
provideExport('qb-core', 'HideText', compatHideText)
-- Upstream's KeyPressed plays a brief NUI press animation, then hides.
provideExport('qb-core', 'KeyPressed', compatHideText)
