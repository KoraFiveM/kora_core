-- Seed job definitions with graded pay scales. Shape matches legacy
-- QBCore.Shared.Jobs: keyed by job name, with a one-based `grades` array.
-- `offDutyPay` is either `false` (no off-duty paycheck) or a flat number paid
-- to an employed-but-off-duty player each paycheck tick -- see Core.paycheck.
--
-- `type` and `blip` are extra fields the registry happily carries through
-- (Core.registry.registerShared stores a record as-is) but that core itself
-- never reads or copies onto PlayerData.job -- CoreInternal.player.buildJob
-- only copies name/label/payment/onduty/isboss/grade. A consumer that needs
-- `type`/`blip` (e.g. a job resource deciding whether it's LEO/EMS, or
-- drawing a duty blip) must read the REGISTRY record client-side via
-- `exports.qbcore:getShared('jobs', jobName)`, not `PlayerData.job`.
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
}
