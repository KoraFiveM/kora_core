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

function Core.development._tick()
    if not active then return end

    local ped = Kora.cache.ped()
    if not pedExists(ped) then return end

    if lastPed and lastPed ~= ped then restorePed(lastPed) end
    lastPed = ped

    SetEntityInvincible(ped, true)
    SetPedMoveRateOverride(ped, walkSpeed)

    RestorePlayerStamina(Kora.cache.playerId(), 1.0)
end

local function restoreOwnedState()
    restorePed(lastPed)

    local currentPed = Kora.cache.ped()
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
        TriggerEvent('kora_core:client:devModeChanged', false)
        return
    end

    local myGeneration = generation
    Core.development._tick()
    TriggerEvent('kora_core:client:devModeChanged', true)
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

RegisterNetEvent('kora_core:client:setDevMode', setLocalMode)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() or not active then return end
    active = false
    generation = generation + 1
    restoreOwnedState()
end)
