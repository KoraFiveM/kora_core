-- compat/client/qb-core-events.lua -- client-side legacy event glue. The delta
-- apply in modules/replication/client.lua already fires
-- QBCore:Player:SetPlayerData / OnJobUpdate / OnGangUpdate locally; this file
-- handles the remaining inbound admin/command events a stock qb admin menu or
-- third-party resource fires (spawn/delete vehicle, teleports, /me, etc.),
-- porting the real qb-core client/events.lua bodies.

RegisterNetEvent('QBCore:Command:TeleportToCoords', function(x, y, z, h)
    local ped = PlayerPedId()
    SetPedCoordsKeepVehicle(ped, x + 0.0, y + 0.0, z + 0.0)
    SetEntityHeading(ped, h or GetEntityHeading(ped))
end)

RegisterNetEvent('QBCore:Command:TeleportToPlayer', function(coords)
    local ped = PlayerPedId()
    SetPedCoordsKeepVehicle(ped, coords.x, coords.y, coords.z)
end)

-- Ported from real qb-core. Real uses Lang:t() for its notifications; we don't
-- ship the qb locale object client-side, so the notify strings are inlined and
-- routed through QBCore.Functions.Notify (which forwards to kora_lib).
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

    -- Unpack coords instead of having to unpack them while iterating.
    -- 825.0 seems to be the max a player can reach while 0.0 being the lowest.
    local x, y, groundZ, Z_START = coords['x'], coords['y'], 850.0, 950.0
    local found = false
    if vehicle > 0 then
        FreezeEntityPosition(vehicle, true)
    else
        FreezeEntityPosition(ped, true)
    end

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

        -- Get ground coord. As mentioned in the natives, this only works if the client is in render distance.
        found, groundZ = GetGroundZFor_3dCoord(x, y, z, false)
        if found then
            Wait(0)
            SetPedCoordsKeepVehicle(ped, x, y, groundZ)
            break
        end
        Wait(0)
    end

    DoScreenFadeIn(650)
    if vehicle > 0 then
        FreezeEntityPosition(vehicle, false)
    else
        FreezeEntityPosition(ped, false)
    end

    if not found then
        SetPedCoordsKeepVehicle(ped, oldCoords['x'], oldCoords['y'], oldCoords['z'] - 1.0)
        QBCore.Functions.Notify('Unable to teleport to waypoint', 'error', 5000)
        return
    end

    SetPedCoordsKeepVehicle(ped, x, y, groundZ)
    QBCore.Functions.Notify('Teleported to waypoint', 'success', 5000)
end)

-- Ported verbatim from real qb-core's client/events.lua. Real qb-core admin
-- commands fire this after flipping the server-side PVP flag so this client's
-- ped stops (or resumes) taking friendly-fire damage in step with everyone
-- else's.
RegisterNetEvent('QBCore:Client:PvpHasToggled', function(enabled)
    SetCanAttackFriendly(PlayerPedId(), enabled, false)
    NetworkSetFriendlyFireOption(enabled)
end)

RegisterNetEvent('QBCore:Command:SpawnVehicle', function(vehName)
    local ped = PlayerPedId()
    local hash = joaat(vehName)
    local veh = GetVehiclePedIsUsing(ped)
    if not IsModelInCdimage(hash) then return end
    local loaded = QBCore.Functions.LoadModel(hash)
    if not loaded then
        return QBCore.Functions.Notify('Unable to load that vehicle', 'error', 5000)
    end

    if IsPedInAnyVehicle(ped) then
        SetEntityAsMissionEntity(veh, true, true)
        DeleteVehicle(veh)
    end

    -- A client event cannot prove why a shared entity is authorized. Keep this
    -- legacy command functional as a local-only compatibility vehicle; native
    -- admin/job resources use their guarded server-owned spawn paths.
    local vehicle = CreateVehicle(hash, GetEntityCoords(ped), GetEntityHeading(ped), false, false)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        SetModelAsNoLongerNeeded(hash)
        return QBCore.Functions.Notify('Unable to spawn that vehicle', 'error', 5000)
    end
    TaskWarpPedIntoVehicle(ped, vehicle, -1)
    SetVehicleFuelLevel(vehicle, 100.0)
    SetVehicleDirtLevel(vehicle, 0.0)
    SetModelAsNoLongerNeeded(hash)
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

-- Subscribes to kora_lib's shared-cache edge changes (instead of a separate poll/relay) to re-fire the local legacy vehicle events with their original names and payloads.
local lastVehicleSeat = Kora.cache.seat()

local function emitVehicleInfo(event, vehicle, seat)
    local modelName = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    TriggerEvent('QBCore:Client:VehicleInfo', {
        vehicle = vehicle,
        seat = seat,
        -- Preserve both keys: old qb-core server code supplied `name`, while
        -- its client compatibility handler reads `modelName`.
        name = modelName,
        modelName = modelName,
        netId = VehToNet(vehicle),
        event = event,
    })
end

Kora.cache.onChange('seat', function(seat)
    -- On exit the cache intentionally updates seat before vehicle, so retain
    -- the last occupied seat for the forthcoming LeftVehicle payload.
    if seat ~= false then lastVehicleSeat = seat end
end)

Kora.cache.onChange('enteringVehicle', function(vehicle, previousVehicle)
    if vehicle then
        emitVehicleInfo('Entering', vehicle, Kora.cache.enteringSeat())
        return
    end

    if previousVehicle then
        -- enteringVehicle clears in the same cache refresh that may set the
        -- actual vehicle. Deferring one scheduler turn distinguishes a
        -- completed entry from an aborted animation without a second poll.
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

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    -- Ensure the mirror requests a snapshot if it somehow hasn't yet.
    if Core.replication.getData() == nil then Core.replication.requestResync() end
end)

-- Keep the paired legacy unload signal network-safe even when no compatibility
-- resource currently consumes it.  This avoids CFX rejecting kora_core's legacy
-- TriggerClientEvent during character logout.
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function() end)

-- QBCore:Client:OnPlayerUpdated: upstream applies the pushed `val` into QBCore.PlayerData. We deliberately do NOT: the mirror is
-- server-authoritative via seq-tracked delta replication, and an externally pushed blob would let a foreign resource desync it.
-- This handler ONLY re-announces the mirror's CURRENT data via the local legacy events; `val` is never read.
--
-- key=='all'/nil goes through Core.replication.reannounceFull() rather than a bare TriggerEvent('QBCore:Player:SetPlayerData'):
-- that event has a foreign-write acceptor in modules/replication/client.lua which MERGES raw triggers into the mirror, so firing
-- without its private REFIRE_TOKEN would merge our zero-based view back into the one-based mirror. The job/gang branches have no
-- such acceptor, so they translate-and-fire locally, guarded on the specific Core.compat function since Core is an
-- auto-vivifying proxy (build/initiate.lua).
--
-- `token`: fireLegacy fires this event itself with 'qbcore:rep:refire' after already firing OnJobUpdate/OnGangUpdate for the
-- delta; re-firing them here would double them. The literal is duplicated on purpose (private per compat file). A genuine
-- external trigger `(key, val)` never supplies it, so it is nil there.
RegisterNetEvent('QBCore:Client:OnPlayerUpdated', function(key, _, token)
    local data = Core.replication.getData()
    if not data then return end

    if key == nil or key == 'all' then
        Core.replication.reannounceFull()
    elseif key == 'job' then
        if token == 'qbcore:rep:refire' then return end
        local legacyJob = Core.compat.toLegacyJobOrGang and Core.compat.toLegacyJobOrGang(data.job, 'jobs') or data.job
        TriggerEvent('QBCore:Client:OnJobUpdate', legacyJob)
    elseif key == 'gang' then
        if token == 'qbcore:rep:refire' then return end
        local legacyGang = Core.compat.toLegacyJobOrGang and Core.compat.toLegacyJobOrGang(data.gang, 'gangs') or data.gang
        TriggerEvent('QBCore:Client:OnGangUpdate', legacyGang)
    end
    -- Any other key: no-op. Divergence from upstream, which would apply an
    -- arbitrary key/val pair directly -- see the comment above this handler.
end)

-- Legacy QBCore:Notify, routed through QBCore.Functions.Notify (-> Kora.notify.send) so server-side emissions (compat and admin commands) are not silently dropped client-side.
RegisterNetEvent('QBCore:Notify', function(text, type_, length, icon)
    QBCore.Functions.Notify(text, type_, length, icon)
end)

-- qb-core's drawtext event aliases target the same exported prompt family.
-- Resolve through the provided identity so these keep the drawtext.lua
-- two-argument semantics rather than QBCore.Functions.DrawText's world-text
-- signature.
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

-- Real qb-core patches QBCore.Shared from these events. Here Shared.* are live views over getter-backed registries synced via
-- qbcore:registry:delta (no local set API), so these stay thin best-effort patches; a later registry delta reconciles divergence.
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

-- QBCore:Client:SharedUpdate (singular; distinct from OnSharedUpdate*): upstream sends the ENTIRE QBCore.Shared once at connect.
-- Deliberately an effective no-op: our Shared.* views are already live via the registry snapshot, and overwriting them with a
-- one-shot payload would regress them. It exists so scripts hooking the event name still see it fire; only emitted when
-- Config.compat.fireSharedUpdateAtLogin is on (compat/server/qb-core-events.lua).
RegisterNetEvent('QBCore:Client:SharedUpdate', function(_sharedTable)
end)
