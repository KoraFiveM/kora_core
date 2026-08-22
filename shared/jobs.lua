-- Seed job definitions with graded pay scales. Shape matches legacy
-- QBCore.Shared.Jobs: keyed by job name, with a one-based `grades` array.
QBCoreSeed = QBCoreSeed or {}

QBCoreSeed.jobs = {
    {
        name = 'unemployed', label = 'Civilian', defaultDuty = true, offDutyPay = false,
        grades = { { name = 'Freelancer', payment = 10 } },
    },
    {
        name = 'police', label = 'Law Enforcement', defaultDuty = false, offDutyPay = false,
        grades = {
            { name = 'Recruit',  payment = 50 },
            { name = 'Officer',  payment = 75 },
            { name = 'Sergeant', payment = 100 },
            { name = 'Chief',    payment = 150, isboss = true },
        },
    },
    {
        name = 'ambulance', label = 'EMS', defaultDuty = false, offDutyPay = false,
        grades = {
            { name = 'Trainee',  payment = 50 },
            { name = 'Paramedic',payment = 75 },
            { name = 'Doctor',   payment = 100 },
            { name = 'Chief',    payment = 150, isboss = true },
        },
    },
    {
        name = 'mechanic', label = 'Mechanic', defaultDuty = false, offDutyPay = false,
        grades = {
            { name = 'Apprentice', payment = 40 },
            { name = 'Mechanic',   payment = 60 },
            { name = 'Boss',       payment = 100, isboss = true },
        },
    },
}
