-- Seed job definitions with graded pay scales. Shape matches legacy
-- QBCore.Shared.Jobs: keyed by job name, with a `grades` map.
QBCoreSeed = QBCoreSeed or {}

QBCoreSeed.jobs = {
    {
        name = 'unemployed', label = 'Civilian', defaultDuty = true, offDutyPay = false,
        grades = { [0] = { name = 'Freelancer', payment = 10 } },
    },
    {
        name = 'police', label = 'Law Enforcement', defaultDuty = false, offDutyPay = false,
        grades = {
            [0] = { name = 'Recruit',  payment = 50 },
            [1] = { name = 'Officer',  payment = 75 },
            [2] = { name = 'Sergeant', payment = 100 },
            [3] = { name = 'Chief',    payment = 150, isboss = true },
        },
    },
    {
        name = 'ambulance', label = 'EMS', defaultDuty = false, offDutyPay = false,
        grades = {
            [0] = { name = 'Trainee',  payment = 50 },
            [1] = { name = 'Paramedic',payment = 75 },
            [2] = { name = 'Doctor',   payment = 100 },
            [3] = { name = 'Chief',    payment = 150, isboss = true },
        },
    },
    {
        name = 'mechanic', label = 'Mechanic', defaultDuty = false, offDutyPay = false,
        grades = {
            [0] = { name = 'Apprentice', payment = 40 },
            [1] = { name = 'Mechanic',   payment = 60 },
            [2] = { name = 'Boss',       payment = 100, isboss = true },
        },
    },
}
