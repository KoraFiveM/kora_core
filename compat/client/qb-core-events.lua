RegisterNetEvent('QBCore:Command:TeleportToCoords', function(x, y, z, h)
    local ped = PlayerPedId()
    SetPedCoordsKeepVehicle(ped, x + 0.0, y + 0.0, z + 0.0)
    SetEntityHeading(ped, h or GetEntityHeading(ped))
end)

RegisterNetEvent('QBCore:Command:TeleportToPlayer', function(coords)
    local ped = PlayerPedId()
    SetPedCoordsKeepVehicle(ped, coords.x, coords.y, coords.z)
end)

local markerFrozen = nil

RegisterNetEvent('QBCore:Command:GoToMarker', function()
    local PlayerPedId = PlayerPedId
    local GetEntityCoords = GetEntityCoords
    local GetGroundZFor_3dCoord = GetGroundZFor_3dCoord

    local blipMarker <const> = GetFirstBlipInfoId(8)
    if not DoesBlipExist(blipMarker) then
        QBCore.Functions.Notify('No waypoint set', 'error', 5000)
        return 'marker'
    end

    DoScreenFadeOut(650)
    local faded = Kora.loops.controlled(IsScreenFadedOut, false, 2000, 25)
    if not faded then
        DoScreenFadeIn(0)
        return QBCore.Functions.Notify('Unable to begin waypoint teleport', 'error', 5000)
    end

    local ped, coords <const> = PlayerPedId(), GetBlipInfoIdCoord(blipMarker)
    local vehicle = GetVehiclePedIsIn(ped, false)
    local oldCoords <const> = GetEntityCoords(ped)

    local x, y, groundZ, Z_START = coords['x'], coords['y'], 850.0, 950.0
    local found = false
    markerFrozen = vehicle > 0 and vehicle or ped
    FreezeEntityPosition(markerFrozen, true)

    for i = Z_START, 0, -25.0 do
        local z = i
        if (i % 2) ~= 0 then
            z = Z_START - i
        end

        NewLoadSceneStart(x, y, z, x, y, z, 50.0, 0)
        local curTime = GetGameTimer()
        while IsNetworkLoadingScene() do
            if GetGameTimer() - curTime > 1000 then
                break
            end
            Wait(0)
        end
        NewLoadSceneStop()
        SetPedCoordsKeepVehicle(ped, x, y, z)

        curTime = GetGameTimer()
        while not HasCollisionLoadedAroundEntity(ped) do
            RequestCollisionAtCoord(x, y, z)
            if GetGameTimer() - curTime > 1000 then
                break
            end
            Wait(0)
        end

        found, groundZ = GetGroundZFor_3dCoord(x, y, z, false)
        if found then
            Wait(0)
            SetPedCoordsKeepVehicle(ped, x, y, groundZ)
            break
        end
        Wait(0)
    end

    DoScreenFadeIn(650)
    if DoesEntityExist(markerFrozen) then FreezeEntityPosition(markerFrozen, false) end
    markerFrozen = nil

    if not found then
        SetPedCoordsKeepVehicle(ped, oldCoords['x'], oldCoords['y'], oldCoords['z'] - 1.0)
        QBCore.Functions.Notify('Unable to teleport to waypoint', 'error', 5000)
        return
    end

    SetPedCoordsKeepVehicle(ped, x, y, groundZ)
    QBCore.Functions.Notify('Teleported to waypoint', 'success', 5000)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() or not markerFrozen then return end
    if DoesEntityExist(markerFrozen) then FreezeEntityPosition(markerFrozen, false) end
    markerFrozen = nil
    DoScreenFadeIn(0)
end)

RegisterNetEvent('QBCore:Client:PvpHasToggled', function(enabled)
    SetCanAttackFriendly(PlayerPedId(), enabled, false)
    NetworkSetFriendlyFireOption(enabled)
end)

RegisterNetEvent('QBCore:Command:SpawnVehicle', function(vehName)
    local ped = PlayerPedId()
    if type(vehName) ~= 'string' then return end
    local hash = joaat(vehName)
    local veh = GetVehiclePedIsUsing(ped)
    if not IsModelInCdimage(hash) then return end

    if IsPedInAnyVehicle(ped) then
        SetEntityAsMissionEntity(veh, true, true)
        DeleteVehicle(veh)
    end

    local origin = GetEntityCoords(ped)
    local vehicle = QBCore.Functions.SpawnVehicle(hash, nil,
        { x = origin.x, y = origin.y, z = origin.z, w = GetEntityHeading(ped) }, true, true)
    if not vehicle then
        return QBCore.Functions.Notify('Unable to spawn that vehicle', 'error', 5000)
    end
    SetVehicleDirtLevel(vehicle, 0.0)
    TriggerEvent('vehiclekeys:client:SetOwner', QBCore.Functions.GetPlate(vehicle))
end)

RegisterNetEvent('QBCore:Command:DeleteVehicle', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsUsing(ped)
    if veh ~= 0 then
        SetEntityAsMissionEntity(veh, true, true)
        DeleteVehicle(veh)
    else
        local pcoords = GetEntityCoords(ped)
        local vehicles = GetGamePool('CVehicle')
        for _, v in pairs(vehicles) do
            if #(pcoords - GetEntityCoords(v)) <= 5.0 then
                SetEntityAsMissionEntity(v, true, true)
                DeleteVehicle(v)
            end
        end
    end
end)

RegisterNetEvent('QBCore:Client:VehicleInfo', function(info)
    local plate = QBCore.Functions.GetPlate(info.vehicle)
    local hasKeys = true

    if GetResourceState('qb-vehiclekeys') == 'started' then
        hasKeys = exports['qb-vehiclekeys']:HasKeys(plate)
    end

    local data = {
        vehicle = info.vehicle,
        seat = info.seat,
        name = info.modelName,
        plate = plate,
        driver = GetPedInVehicleSeat(info.vehicle, -1),
        inseat = GetPedInVehicleSeat(info.vehicle, info.seat),
        haskeys = hasKeys
    }

    TriggerEvent('QBCore:Client:' .. info.event .. 'Vehicle', data)
end)

local lastVehicleSeat = Kora.cache.seat()

local function emitVehicleInfo(event, vehicle, seat)
    local modelName = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    TriggerEvent('QBCore:Client:VehicleInfo', {
        vehicle = vehicle,
        seat = seat,
        name = modelName,
        modelName = modelName,
        netId = DoesEntityExist(vehicle) and VehToNet(vehicle) or 0,
        event = event,
    })
end

local function watchVehicleCache()
    Kora.cache.onChange('seat', function(seat)
        if seat ~= false then lastVehicleSeat = seat end
    end)

    Kora.cache.onChange('enteringVehicle', function(vehicle, previousVehicle)
        if vehicle then
            emitVehicleInfo('Entering', vehicle, Kora.cache.enteringSeat())
            return
        end

        if previousVehicle then
            SetTimeout(0, function()
                if not Kora.cache.vehicle() then
                    TriggerEvent('QBCore:Client:AbortVehicleEntering')
                end
            end)
        end
    end)

    Kora.cache.onChange('vehicle', function(vehicle, previousVehicle)
        if vehicle then
            emitVehicleInfo('Entered', vehicle, Kora.cache.seat())
        elseif previousVehicle then
            emitVehicleInfo('Left', previousVehicle, lastVehicleSeat)
            lastVehicleSeat = false
        end
    end)
end

watchVehicleCache()
AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= 'kora_lib' then return end
    local seat = Kora.cache.seat()
    if seat then lastVehicleSeat = seat end
    watchVehicleCache()
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    if Core.replication.getData() == nil then Core.replication.requestResync() end
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function() end)

RegisterNetEvent('QBCore:Client:OnPlayerUpdated', function(key, _, token)
    local data = Core.replication.getData()
    if not data then return end

    if key == nil or key == 'all' then
        Core.replication.reannounceFull()
    elseif key == 'job' then
        if token == 'kora_core:rep:refire' then return end
        local legacyJob = Core.compat.toLegacyJobOrGang and Core.compat.toLegacyJobOrGang(data.job, 'jobs') or data.job
        TriggerEvent('QBCore:Client:OnJobUpdate', legacyJob)
    elseif key == 'gang' then
        if token == 'kora_core:rep:refire' then return end
        local legacyGang = Core.compat.toLegacyJobOrGang and Core.compat.toLegacyJobOrGang(data.gang, 'gangs') or data.gang
        TriggerEvent('QBCore:Client:OnGangUpdate', legacyGang)
    end
end)

RegisterNetEvent('QBCore:Notify', function(text, type_, length, icon)
    QBCore.Functions.Notify(text, type_, length, icon)
end)

RegisterNetEvent('qb-core:client:DrawText', function(text, position)
    CoreInternal.compat.drawText(text, position)
end)
RegisterNetEvent('qb-core:client:ChangeText', function(text, position)
    CoreInternal.compat.changeText(text, position)
end)
RegisterNetEvent('qb-core:client:HideText', function()
    CoreInternal.compat.hideText()
end)
RegisterNetEvent('qb-core:client:KeyPressed', function()
    CoreInternal.compat.keyPressed()
end)

local function Draw3DText(coords, str)
    local onScreen, worldX, worldY = World3dToScreen2d(coords.x, coords.y, coords.z)
    local camCoords = GetGameplayCamCoord()
    local scale = 200 / (GetGameplayCamFov() * #(camCoords - coords))
    if onScreen then
        SetTextScale(1.0, 0.5 * scale)
        SetTextFont(4)
        SetTextColour(255, 255, 255, 255)
        SetTextEdge(2, 0, 0, 0, 150)
        SetTextProportional(1)
        SetTextOutline()
        SetTextCentre(1)
        BeginTextCommandDisplayText('STRING')
        AddTextComponentSubstringPlayerName(str)
        EndTextCommandDisplayText(worldX, worldY)
    end
end

RegisterNetEvent('QBCore:Command:ShowMe3D', function(senderId, msg)
    local sender = GetPlayerFromServerId(senderId)
    CreateThread(function()
        local displayTime = 5000 + GetGameTimer()
        while displayTime > GetGameTimer() do
            local targetPed = GetPlayerPed(sender)
            local tCoords = GetEntityCoords(targetPed)
            Draw3DText(tCoords, msg)
            Wait(0)
        end
    end)
end)

RegisterNetEvent('QBCore:Client:OnSharedUpdate', function(tableName, key, value)
    local tbl = QBCore.Shared[tableName]
    if type(tbl) == 'table' then
        tbl[key] = value
    end
    TriggerEvent('QBCore:Client:UpdateObject')
end)

RegisterNetEvent('QBCore:Client:OnSharedUpdateMultiple', function(tableName, values)
    local tbl = QBCore.Shared[tableName]
    if type(tbl) == 'table' then
        for key, value in pairs(values) do
            tbl[key] = value
        end
    end
    TriggerEvent('QBCore:Client:UpdateObject')
end)

RegisterNetEvent('QBCore:Client:SharedUpdate', function(_sharedTable)
end)
