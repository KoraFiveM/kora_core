-- Core.vehicleAirControl (client realm) -- optionally removes the driver's
-- ability to steer, pitch or roll a land vehicle while it is airborne, so jumps
-- cannot be "landed perfectly" with the keyboard/stick. Driven by
-- Config.vehicleAirControl (see config.lua).
--
-- No permanent loop: a worker exists only while the local ped is the DRIVER of a
-- vehicle whose class is not exempt. It idles at 250 ms while the vehicle is on
-- the ground (so a car upside down on the road can still be rocked back) and
-- only runs per frame while the vehicle is actually airborne.

local DRIVER_SEAT = -1
local GROUND_POLL_MS = 250
-- 59/60 move left-right / up-down, 61/62 up-only/down-only, 63/64 left-only/right-only.
local AIR_CONTROLS = { 59, 60, 61, 62, 63, 64 }

local vehicle = Kora.cache.vehicle()
local seat = Kora.cache.seat()
local generation = 0 -- bumping it retires any running worker

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

    -- Read on every start so a live Config change applies on the next entry.
    local settings = Config.vehicleAirControl
    if not settings or not settings.disable then return end
    if isExempt(settings, GetVehicleClass(vehicle)) then return end

    startWorker(vehicle, generation)
end

-- The cache updates seat before vehicle; both handlers re-evaluate from local copies.
Kora.cache.onChange('seat', function(value)
    seat = value
    refresh()
end)

Kora.cache.onChange('vehicle', function(value)
    vehicle = value
    refresh()
end)

refresh()
