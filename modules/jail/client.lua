local CONTAINMENT_RADIUS = 30.0

local containmentZone = nil

local function clearContainment()
    if containmentZone then
        containmentZone.remove()
        containmentZone = nil
    end
end

RegisterNetEvent('kora_core:client:jailTeleport', function(coords, remainingSeconds)
    clearContainment()

    SetEntityCoords(PlayerPedId(), coords.x, coords.y, coords.z, false, false, false, false)

    containmentZone = Kora.zones.sphere({
        coords = coords,
        radius = CONTAINMENT_RADIUS,
        onExit = function()
            if not containmentZone then return end
            SetEntityCoords(PlayerPedId(), coords.x, coords.y, coords.z, false, false, false, false)
        end,
    })

    Kora.notify.send({ message = ('You have been jailed for %d minutes.'):format(math.ceil(remainingSeconds / 60)), type = 'error' })
end)

RegisterNetEvent('kora_core:client:jailRelease', function()
    clearContainment()
    Kora.notify.send({ message = 'You have been released.', type = 'success' })
end)

AddEventHandler('QBCore:Client:OnPlayerUnload', function()
    clearContainment()
end)
