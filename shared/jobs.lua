-- Seed job definitions with graded pay scales. Shape matches legacy
-- QBCore.Shared.Jobs: keyed by job name, with a one-based `grades` array.
-- `offDutyPay` is either `false` (no off-duty paycheck) or a flat number paid
-- to an employed-but-off-duty player each paycheck tick -- see Core.paycheck.
--
-- `type` groups jobs into a SERVICE ('leo' covers police, sheriff and state
-- troopers; 'ems' covers ambulance and fire). It is copied onto PlayerData.job
-- by CoreInternal.player.buildJob and indexed by Core.jobs, so
-- `exports.qbcore:getPlayersByJobType('leo', true)` reaches every on-duty
-- member of every LEO job in one O(1) lookup -- which is what a dispatch system
-- targets rather than enumerating job names. Read it off `PlayerData.job.type`.
--
-- `blip` is NOT copied onto PlayerData.job. The registry carries it through
-- (Core.registry.registerShared stores a record as-is) but nothing reads it
-- from player data, so a consumer that wants it must read the REGISTRY record
-- via `exports.qbcore:getShared('jobs', jobName)`. Same for any other extra
-- field added here.
QBCoreSeed = QBCoreSeed or {}

QBCoreSeed.jobs = {
    {
        name = 'unemployed', label = 'Civilian', defaultDuty = true, offDutyPay = false, type = 'civ',
        grades = { { name = 'Freelancer', payment = 10 } },
    },
    {
        name = 'police', label = 'Law Enforcement', defaultDuty = false, offDutyPay = false, type = 'leo',
        blip = { sprite = 60, color = 29, scale = 0.85 },
        grades = {
            { name = 'Cadet',      payment = 50 },
            { name = 'Officer',    payment = 75 },
            { name = 'Sergeant',   payment = 100 },
            { name = 'Lieutenant', payment = 125 },
            { name = 'Chief',      payment = 150, isboss = true },
        },
    },
    {
        name = 'ambulance', label = 'EMS', defaultDuty = false, offDutyPay = false, type = 'ems',
        blip = { sprite = 61, color = 1, scale = 0.85 },
        grades = {
            { name = 'Recruit',    payment = 50 },
            { name = 'EMT',        payment = 75 },
            { name = 'Paramedic',  payment = 100 },
            { name = 'Supervisor', payment = 125 },
            { name = 'Chief',      payment = 150, isboss = true },
        },
    },
    {
        name = 'mechanic', label = 'Mechanic', defaultDuty = false, offDutyPay = false, type = 'civ',
        grades = {
            { name = 'Apprentice', payment = 40 },
            { name = 'Mechanic',   payment = 60 },
            { name = 'Boss',       payment = 100, isboss = true },
        },
    },
    -- 'recovery' is a deliberate third service type alongside leo/ems: it is
    -- what proves the dispatch pipeline is genuinely job-agnostic rather than
    -- emergency-services-shaped. A tow operator gets their own call channel,
    -- own theme and own history without a line of dispatch code knowing what
    -- towing is.
    {
        name = 'tow', label = 'Recovery', defaultDuty = false, offDutyPay = false, type = 'recovery',
        blip = { sprite = 68, color = 5, scale = 0.85 },
        grades = {
            { name = 'Driver',    payment = 45 },
            { name = 'Operator',  payment = 65 },
            { name = 'Owner',     payment = 100, isboss = true },
        },
    },
}
