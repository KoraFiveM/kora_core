-- Core.dispatch (server realm) -- job-aware alert fan-out. Recipients are
-- resolved via Core.jobs.getPlayersByJob's O(1) index (one lookup per job in
-- payload.jobs, not a scan), then TriggerClientEvent is looped per recipient
-- -- there is no native multi-target send, and a -1 broadcast + client-side
-- filter would leak alert content (coords, message) to every connected
-- client instead of just the on-duty roster it's meant for.

---@class CoreDispatchAlert
---@field jobs string[] Job names to notify (on-duty members only).
---@field title string|nil
---@field message string|nil
---@field coords table|nil  -- {x,y,z} or vector3/vector4
---@field code string|nil
---@field blip table|nil    -- {sprite,color,scale,duration}, consumed by the receiving job resource's own client code
---@field sound string|nil
---@field radius number|nil
---@field data table|nil    -- freeform, passed through untouched

-- `local` is the same-server TriggerEvent legacy code elsewhere might also
    -- fire directly (matches the legacy police:server:policeAlert
-- convention); `client` is what each recipient receives. Ambulance/EMS has no
-- established local-TriggerEvent convention to mirror -- only the client-side
-- alert is legacy-preserved for it.
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

    -- Dedup: a src listed under more than one requested job is notified once.
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

    -- Server-side mirror for a dispatch/MDT resource that records incidents: the client
    -- push reaches every recipient, so recording from it would log once per recipient.
    -- Fired after the fan-out so a listener error cannot stop recipients being notified.
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
