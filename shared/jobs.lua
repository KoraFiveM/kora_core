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
        name = 'mechanic', label = 'Mechanic', defaultDuty = false, offDutyPay = false, type = 'automotive',
        grades = {
            { name = 'Apprentice', payment = 40 },
            { name = 'Mechanic',   payment = 60 },
            { name = 'Boss',       payment = 100, isboss = true },
        },
    },
    {
        name = 'roadside', label = 'Roadside Assistance', defaultDuty = false, offDutyPay = false, type = 'automotive',
        grades = {
            { name = 'Responder', payment = 40 },
            { name = 'Technician', payment = 60 },
            { name = 'Supervisor', payment = 90, isboss = true },
        },
    },
    {
        name = 'bodyshop', label = 'Bodyshop', defaultDuty = false, offDutyPay = false, type = 'bodyshop',
        grades = {
            { name = 'Detailer', payment = 40 },
            { name = 'Painter', payment = 60 },
            { name = 'Owner', payment = 90, isboss = true },
        },
    },
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
