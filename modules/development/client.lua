-- Core.development (client realm) -- applies the server-authoritative mode to
-- the local player ped and restores every owned native override on disable.

local active = false
local generation = 0
local walkSpeed = tonumber(Config.development.walkSpeed)
local lastPed = nil

assert(walkSpeed and walkSpeed > 0,
    'Config.development.walkSpeed must be a positive number.')

local function pedExists(ped)
    return ped and ped ~= 0 and DoesEntityExist(ped)
end

local function restorePed(ped)
    if not pedExists(ped) then return end
    SetEntityInvincible(ped, false)
    SetPedMoveRateOverride(ped, 1.0)
end

-- Underscore-prefixed so build/finalise.lua does not export a frame-level
-- implementation detail. Kept directly callable for the plain-Lua smoke test.
function Core.development._tick()
    if not active then return end

    local ped = QB.cache.ped()
    if not pedExists(ped) then return end

    if lastPed and lastPed ~= ped then restorePed(lastPed) end
    lastPed = ped

    -- The move-rate native is frame-scoped. Reasserting invincibility in this
    -- same loop also makes the mode survive respawns and momentary interference
    -- from another client script.
    SetEntityInvincible(ped, true)
    SetPedMoveRateOverride(ped, walkSpeed)

    -- Refilling every frame keeps stamina pinned at full; there is nothing to
    -- restore on disable because normal drain resumes as soon as this stops.
    RestorePlayerStamina(QB.cache.playerId(), 1.0)
end

local function restoreOwnedState()
    restorePed(lastPed)

    local currentPed = QB.cache.ped()
    if currentPed ~= lastPed then restorePed(currentPed) end
    lastPed = nil
end

local function setLocalMode(enabled)
    enabled = enabled == true
    if active == enabled then return end

    active = enabled
    generation = generation + 1

    if not active then
        restoreOwnedState()
        TriggerEvent('qbcore:client:devModeChanged', false)
        return
    end

    local myGeneration = generation
    Core.development._tick()
    TriggerEvent('qbcore:client:devModeChanged', true)
    CreateThread(function()
        while active and generation == myGeneration do
            Core.development._tick()
            Wait(0)
        end
    end)
end

---@return boolean
function Core.development.isDevMode()
    return active
end

RegisterNetEvent('qbcore:client:setDevMode', setLocalMode)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() or not active then return end
    active = false
    generation = generation + 1
    restoreOwnedState()
end)
