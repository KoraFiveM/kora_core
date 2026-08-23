-- Core.needs (server realm) -- hunger/thirst decay, the one piece of legacy
-- qb-core behavior (hunger/thirst ticking down over time) nothing in this
-- engine reimplements otherwise. Stress is deliberately NOT auto-decayed
-- here -- there's no generic "stress should go down over time" rule the way
-- there is for hunger/thirst; job resources push stress increases/decreases
-- directly via the existing Core.metadata.incrementMetaData.

local running = false
local threadGeneration = 0

-- Underscore-prefixed so build/finalise.lua skips it (never exported) while
-- staying directly callable from a test -- see Core.paycheck._tick's doc
-- comment for why the tick logic can't be reached through the loop itself.
function Core.needs._tick()
    for _, src in ipairs(Core.player.getPlayers()) do
        Core.metadata.incrementMetaData(src, 'hunger', -Config.needs.hungerDecay, 0, 100)
        Core.metadata.incrementMetaData(src, 'thirst', -Config.needs.thirstDecay, 0, 100)
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
                    print(('[qbcore:needs] tick errored: %s'):format(tostring(err)))
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
---legacy qb-ambulancejob's `hospital:server:resetHungerThirst`, called from a
---job resource's own respawn/heal flow (this module doesn't hook death itself).
---@param src integer
function Core.needs.reset(src)
    Core.metadata.setMetaData(src, 'hunger', 100)
    Core.metadata.setMetaData(src, 'thirst', 100)
    Core.metadata.setMetaData(src, 'stress', 0)
end
