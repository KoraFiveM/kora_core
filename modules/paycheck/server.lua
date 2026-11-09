local running = false
local threadGeneration = 0

function Core.paycheck._tick()
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
