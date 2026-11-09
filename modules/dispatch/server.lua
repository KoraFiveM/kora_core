local LEGACY_JOB_EVENTS = {
    police = { client = 'police:client:policeAlert', local_ = 'police:server:policeAlert' },
    ambulance = { client = 'hospital:client:ambulanceAlert' },
    ems = { client = 'hospital:client:ambulanceAlert' },
}

---Sends `payload` to every on-duty player of each job in `payload.jobs`.
---@param payload CoreDispatchAlert
---@return integer recipientCount
function Core.dispatch.alert(payload)
    assert(type(payload) == 'table' and type(payload.jobs) == 'table' and #payload.jobs > 0,
        'Core.dispatch.alert requires payload.jobs as a non-empty array.')

    local recipients = {}
    for _, jobName in ipairs(payload.jobs) do
        for _, src in ipairs(Core.jobs.getPlayersByJob(jobName, true)) do
            recipients[src] = true
        end
    end

    local count = 0
    for src in pairs(recipients) do
        TriggerClientEvent('qbcore:client:dispatchAlert', src, payload)
        count = count + 1
    end

    TriggerEvent('qbcore:server:dispatchAlert', payload, count)

    if Config.dispatch.legacyEvents then
        for _, jobName in ipairs(payload.jobs) do
            local legacy = LEGACY_JOB_EVENTS[jobName]
            if legacy then
                if legacy.local_ then
                    TriggerEvent(legacy.local_, payload.message or payload.title or '')
                end
                for src in pairs(recipients) do
                    TriggerClientEvent(legacy.client, src, payload.coords, payload.message or payload.title or '')
                end
            end
        end
    end

    return count
end
