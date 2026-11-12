local running = false
local threadGeneration = 0

function Core.needs._tick()
    for _, src in ipairs(Core.player.getPlayers()) do
        if not Core.development.isDevMode(src) then
            local hunger = Core.metadata.incrementMetaData(src, 'hunger', -Config.needs.hungerDecay, 0, 100)
            local thirst = Core.metadata.incrementMetaData(src, 'thirst', -Config.needs.thirstDecay, 0, 100)
            TriggerClientEvent('hud:client:UpdateNeeds', src, hunger, thirst)
        end
    end
end

---Starts the hunger/thirst decay loop. Calling it while already running is a no-op.
function Core.needs.startNeedsDecay()
    if running then return end
    running = true
    threadGeneration = threadGeneration + 1
    local myGeneration = threadGeneration

    CreateThread(function()
        while running and threadGeneration == myGeneration do
            Wait(Config.needs.tickInterval)
            if running and threadGeneration == myGeneration then
                local ok, err = pcall(Core.needs._tick)
                if not ok then
                    print(('[kora_core:needs] tick errored: %s'):format(tostring(err)))
                end
            end
        end
    end)
end

function Core.needs.stopNeedsDecay()
    running = false
    threadGeneration = threadGeneration + 1
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then Core.needs.startNeedsDecay() end
end)

---Resets hunger/thirst to full and stress to zero for one player -- mirrors
---legacy `hospital:server:resetHungerThirst`, called from a
---job resource's own respawn/heal flow (this module doesn't hook death itself).
---@param src integer
function Core.needs.reset(src)
    Core.metadata.setMetaData(src, 'hunger', 100)
    Core.metadata.setMetaData(src, 'thirst', 100)
    Core.metadata.setMetaData(src, 'stress', 0)
end
