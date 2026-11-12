local DRIVER_SEAT = -1
local GROUND_POLL_MS = 250
local AIR_CONTROLS = { 59, 60, 61, 62, 63, 64 }

local vehicle = Kora.cache.vehicle()
local seat = Kora.cache.seat()
local generation = 0

local function isExempt(settings, class)
    for _, exempt in ipairs(settings.exemptClasses or {}) do
        if exempt == class then return true end
    end
    return false
end

local function airborne(veh)
    return IsEntityInAir(veh) and not IsVehicleOnAllWheels(veh)
end

local function startWorker(veh, token)
    CreateThread(function()
        while token == generation and DoesEntityExist(veh) do
            local settings = Config.vehicleAirControl
            if not settings or not settings.disable then return end

            if airborne(veh) then
                while token == generation and DoesEntityExist(veh) and airborne(veh) do
                    for i = 1, #AIR_CONTROLS do
                        DisableControlAction(0, AIR_CONTROLS[i], true)
                    end
                    Wait(0)
                end
            else
                Wait(GROUND_POLL_MS)
            end
        end
    end)
end

local function refresh()
    generation = generation + 1
    if not vehicle or seat ~= DRIVER_SEAT then return end

    local settings = Config.vehicleAirControl
    if not settings or not settings.disable then return end
    if isExempt(settings, GetVehicleClass(vehicle)) then return end

    startWorker(vehicle, generation)
end

local function watchCache()
    Kora.cache.onChange('seat', function(value)
        seat = value
        refresh()
    end)

    Kora.cache.onChange('vehicle', function(value)
        vehicle = value
        refresh()
    end)
end

watchCache()
refresh()

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= 'kora_lib' then return end
    vehicle, seat = Kora.cache.vehicle(), Kora.cache.seat()
    watchCache()
    refresh()
end)
