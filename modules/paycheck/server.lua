-- Core.paycheck (server realm) -- the paycheck loop legacy qb-core's own
-- Config.jobs.paycheckInterval was always a stub for (compat/server/qb-core.lua's
-- F.PaycheckInterval reads it, but nothing in the original engine ever ticked
-- against it). Pays every employed player once per Config.jobs.paycheckInterval:
-- job.payment while on duty, job.offDutyPay (a flat number, or false to skip)
-- while off duty. Uses Core.jobs.getPlayersByJob's O(1) index, once per
-- distinct job currently held by any online player -- not a per-player scan.

local running = false
local threadGeneration = 0

-- Underscore-prefixed so build/finalise.lua skips it (never exported) while
-- staying directly callable from a test -- same "internal but testable"
-- convention Core.persistence._insertNew/_load already use. Not just a
-- style choice here: this mock environment's Wait() never yields, so
-- resuming the CreateThread loop below even once would infinite-loop the
-- test process -- the tick logic MUST be reachable without going through it.
function Core.paycheck._tick()
    -- Group online players by job first so each job's roster is fetched via
    -- the index once, not once per player.
    local playersByJob = {}
    for _, src in ipairs(Core.player.getPlayers()) do
        local job = Core.jobs.getJob(src)
        if job and job.name then
            playersByJob[job.name] = playersByJob[job.name] or {}
            playersByJob[job.name][#playersByJob[job.name] + 1] = src
        end
    end

    for jobName in pairs(playersByJob) do
        local record = Core.registry.getShared('jobs', jobName)
        if record then
            local onDuty = {}
            for _, src in ipairs(Core.jobs.getPlayersByJob(jobName, true)) do onDuty[src] = true end

            for _, src in ipairs(playersByJob[jobName]) do
                local job = Core.jobs.getJob(src)
                local payment = job and job.payment

                if onDuty[src] then
                    if type(payment) == 'number' and payment > 0 then
                        Core.money.addMoney(src, Config.money.cashType, payment, 'paycheck')
                    end
                elseif type(record.offDutyPay) == 'number' and record.offDutyPay > 0 then
                    Core.money.addMoney(src, Config.money.cashType, record.offDutyPay, 'paycheck')
                end
            end
        end
    end
end

---Starts the paycheck loop. Calling it while already running is a no-op.
function Core.paycheck.startPaycheck()
    if running then return end
    running = true
    threadGeneration = threadGeneration + 1
    local myGeneration = threadGeneration

    CreateThread(function()
        while running and threadGeneration == myGeneration do
            Wait(Config.jobs.paycheckInterval)
            if running and threadGeneration == myGeneration then
                local ok, err = pcall(Core.paycheck._tick)
                if not ok then
                    print(('[qbcore:paycheck] tick errored: %s'):format(tostring(err)))
                end
            end
        end
    end)
end

---Stops the paycheck loop. The in-flight Wait() still runs out before the
---thread notices and exits -- at most one tick's worth of delay.
function Core.paycheck.stopPaycheck()
    running = false
    threadGeneration = threadGeneration + 1
end

---@return boolean
function Core.paycheck.isPaycheckRunning()
    return running
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then Core.paycheck.startPaycheck() end
end)
