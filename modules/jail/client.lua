-- Core.jail (client realm) -- receives the two pushes Core.jail's server
-- half fires and renders a minimal containment: teleport into the cell,
-- keep the player inside a radius for the sentence via a QB.zones sphere
-- (leaving it teleports straight back), release the zone and notify on
-- jailRelease. No countdown UI/HUD of its own -- qbcore ships no NUI, same
-- as everywhere else; a job resource wanting a jail-time display reads
-- Core.jail.getRemaining(src) itself.

local CONTAINMENT_RADIUS = 30.0

local containmentZone = nil

local function clearContainment()
    if containmentZone then
        containmentZone.remove()
        containmentZone = nil
    end
end

RegisterNetEvent('qbcore:client:jailTeleport', function(coords, remainingSeconds)
    clearContainment()

    SetEntityCoords(PlayerPedId(), coords.x, coords.y, coords.z, false, false, false, false)

    containmentZone = QB.zones.sphere({
        coords = coords,
        radius = CONTAINMENT_RADIUS,
        onExit = function()
            if not containmentZone then return end -- already released between the exit tick and this callback
            SetEntityCoords(PlayerPedId(), coords.x, coords.y, coords.z, false, false, false, false)
        end,
    })

    QB.notify.send({ description = ('You have been jailed for %d minutes.'):format(math.ceil(remainingSeconds / 60)), type = 'error' })
end)

RegisterNetEvent('qbcore:client:jailRelease', function()
    clearContainment()
    QB.notify.send({ description = 'You have been released.', type = 'success' })
end)

AddEventHandler('QBCore:Client:OnPlayerUnload', function()
    clearContainment()
end)
