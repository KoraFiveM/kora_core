-- compat/client/qb-core-events.lua -- client-side legacy event glue. The delta
-- apply in modules/replication/client.lua already fires
-- QBCore:Player:SetPlayerData / OnJobUpdate / OnGangUpdate locally; this file
-- handles the remaining inbound admin/command events a stock qb admin menu or
-- third-party resource fires (spawn/delete vehicle, teleports, /me, etc.),
-- porting the real qb-core client/events.lua bodies.

-- Teleport Commands ----------------------------------------------------------

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

    -- Fade screen to hide how clients get teleported.
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

    -- Remove black screen once the loop has ended.
    DoScreenFadeIn(650)
    if vehicle > 0 then
        FreezeEntityPosition(vehicle, false)
    else
        FreezeEntityPosition(ped, false)
    end

    if not found then
        -- If we can't find the coords, set the coords to the old ones.
        SetPedCoordsKeepVehicle(ped, oldCoords['x'], oldCoords['y'], oldCoords['z'] - 1.0)
        QBCore.Functions.Notify('Unable to teleport to waypoint', 'error', 5000)
        return
    end

    -- If Z coord was found, set coords in found coords.
    SetPedCoordsKeepVehicle(ped, x, y, groundZ)
    QBCore.Functions.Notify('Teleported to waypoint', 'success', 5000)
end)

-- PVP toggle ------------------------------------------------------------------

-- Ported verbatim from real qb-core's client/events.lua. Real qb-core admin
-- commands fire this after flipping the server-side PVP flag so this client's
-- ped stops (or resumes) taking friendly-fire damage in step with everyone
-- else's.
RegisterNetEvent('QBCore:Client:PvpHasToggled', function(enabled)
    SetCanAttackFriendly(PlayerPedId(), enabled, false)
    NetworkSetFriendlyFireOption(enabled)
end)

-- Vehicle Commands -----------------------------------------------------------

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

-- Vehicle lifecycle compatibility -------------------------------------------
-- kora_lib's shared cache already owns the bounded local-player telemetry poll.
-- Subscribe to its edge changes rather than keeping a separate
-- client loop and server relay alive just to re-fire these local QBCore events.
-- The legacy event names and payload shape remain unchanged for vehiclekeys,
-- fuel, seatbelt, garage, and other QBCore-era consumers.
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

-- Lifecycle ------------------------------------------------------------------

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    -- Ensure the mirror requests a snapshot if it somehow hasn't yet.
    if Core.replication.getData() == nil then Core.replication.requestResync() end
end)

-- Keep the paired legacy unload signal network-safe even when no compatibility
-- resource currently consumes it.  This avoids CFX rejecting kora_core's legacy
-- TriggerClientEvent during character logout.
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function() end)

-- QBCore:Client:OnPlayerUpdated -- upstream applies the pushed `val` directly
-- into its plain QBCore.PlayerData global for the given `key` (or the whole
-- blob when key is 'all'/nil). We deliberately do NOT do that here: this
-- kora_core is server-authoritative via its own seq-tracked delta-replication
-- protocol (modules/replication/client.lua), and accepting an arbitrary
-- externally-pushed blob would let a foreign resource desync the mirror
-- (TriggerClientEvent('QBCore:Client:OnPlayerUpdated', src, 'all', garbage)
-- is exactly as reachable from a hostile resource as from a legitimate one).
-- So this handler ONLY re-announces the mirror's CURRENT, correct,
-- server-authoritative data via the same derived local legacy events
-- modules/replication/client.lua's fireLegacy fires on every delta -- `val`
-- is never read.
--
-- The key=='all'/nil case goes through Core.replication.reannounceFull()
-- rather than a bare TriggerEvent('QBCore:Player:SetPlayerData', ...) here:
-- that event is RegisterNetEvent'd in modules/replication/client.lua with its
-- own foreign-write acceptor (any resource's raw trigger of the full-blob
-- event gets MERGED into the live mirror, since a genuine legacy resource is
-- expected to write it that way). Firing it locally without that module's
-- private REFIRE_TOKEN would be indistinguishable from a foreign write, so
-- our own re-announcement -- built from toLegacyPlayerData's translated
-- (zero-based) view -- would get merged straight back into the internal
-- (one-based) mirror, corrupting it. reannounceFull() reuses the exact same
-- REFIRE_TOKEN'd path fireLegacy already uses on every delta, so this is
-- correctly recognised as our own re-fire. The job/gang branches below have
-- no such acceptor (OnJobUpdate/OnGangUpdate are plain fan-out events, not
-- merged into anything), so a direct translate-and-fire is safe there and
-- kept local, guarded on the specific Core.compat function since Core is an
-- auto-vivifying proxy (build/initiate.lua).
--
-- `token`: modules/replication/client.lua's fireLegacy fires THIS event
-- itself (real qb-core's actual protocol name) with the same
-- 'qbcore:rep:refire' token it uses for QBCore:Player:SetPlayerData, since it
-- already fired OnJobUpdate/OnGangUpdate directly for that same delta a few
-- lines above -- re-deriving and firing them again here would double them.
-- Duplicated string literal rather than a shared import: same "small enough
-- to duplicate per compat file" idiom as provideExport in the kora_lib compat/
-- files (modules/replication/client.lua's own copy is intentionally private).
-- A genuine external TriggerClientEvent (the real qb-core wire shape,
-- `(key, val)`) never supplies a 3rd argument, so `token` is simply nil there
-- and this guard never fires -- the translate-and-fire path below still runs
-- exactly as before for a real external trigger.
RegisterNetEvent('QBCore:Client:OnPlayerUpdated', function(key, _, token)
    local data = Core.replication.getData()
    if not data then return end

    if key == nil or key == 'all' then
        Core.replication.reannounceFull()
    elseif key == 'job' then
        if token == 'qbcore:rep:refire' then return end
        local legacyJob = Core.compat.toLegacyJobOrGang and Core.compat.toLegacyJobOrGang(data.job) or data.job
        TriggerEvent('QBCore:Client:OnJobUpdate', legacyJob)
    elseif key == 'gang' then
        if token == 'qbcore:rep:refire' then return end
        local legacyGang = Core.compat.toLegacyJobOrGang and Core.compat.toLegacyJobOrGang(data.gang) or data.gang
        TriggerEvent('QBCore:Client:OnGangUpdate', legacyGang)
    end
    -- Any other key: no-op. Divergence from upstream, which would apply an
    -- arbitrary key/val pair directly -- see the comment above this handler.
end)

-- Legacy QBCore:Notify -- real qb-core registers this on the client so any
-- resource (and kora_core's own admin commands / compat GetCoreObject:Notify) can
-- fire TriggerClientEvent('QBCore:Notify', src, text, type, length) and have it
-- shown. Without this handler the event is emitted server-side (see
-- compat/server/qb-core.lua and modules/commands/server.lua) but silently
-- dropped client-side. Route it through the SAME path QBCore.Functions.Notify
-- uses (which forwards to kora_lib's Kora.notify.send), so there's one notify code
-- path. QBCore is the global assembled in compat/shared/coreobject.lua and
-- compat/client/qb-core.lua (loaded before this file), so Functions.Notify is
-- present by the time this fires.
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

-- /me command 3D text --------------------------------------------------------

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

-- Shared table updates -------------------------------------------------------
-- Real qb-core patches its in-VM QBCore.Shared tables from these events. In our
-- build QBCore.Shared.{Items,Vehicles,Jobs,Gangs,Weapons} are live legacy views
-- over getter-backed registries (see compat/shared/coreobject.lua), and the
-- authoritative sync happens over qbcore:registry:delta -- the client registry
-- is server-owned and has no local "set" API. So these stay thin, best-effort
-- local patches for any resource that still broadcasts the legacy shared-update
-- events; a subsequent registry delta will reconcile if it diverges.
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

-- QBCore:Client:SharedUpdate -- a DIFFERENT real qb-core event from the two
-- above (singular 'SharedUpdate', not 'OnSharedUpdate'/'OnSharedUpdateMultiple'):
-- upstream fires it ONCE per player, right after playerConnecting, carrying the
-- ENTIRE QBCore.Shared table as one payload -- a full push at connect time, not
-- an incremental delta. Upstream's own client handler for it just merges that
-- payload into its plain QBCore.Shared global. We deliberately do NOT do that
-- here: QBCore.Shared.{Items,Vehicles,Jobs,Gangs,Weapons} are already LIVE
-- compatibility views (compat/shared/coreobject.lua's metatable), kept
-- current by the registry snapshot every joining client already requests
-- (modules/registry/client.lua) -- overwriting them with a one-shot snapshot
-- payload would be a stale, one-time regression, not an update. So this handler
-- is an effective no-op; it exists only so a third-party script that hooks the
-- EVENT NAME itself (rather than reading QBCore.Shared) still observes it fire.
-- Only emitted server-side at all when Config.compat.fireSharedUpdateAtLogin is
-- on (compat/server/qb-core-events.lua) -- off by default.
RegisterNetEvent('QBCore:Client:SharedUpdate', function(_sharedTable)
    -- Intentional no-op -- see comment above.
end)
