KoraCoreSeed = KoraCoreSeed or {}

KoraCoreSeed.jobs = {
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

    {
        name = 'beeker', label = 'Beeker\'s Garage', defaultDuty = true, offDutyPay = false, type = 'mechanic',
        grades = {
            ['0'] = { name = 'Recruit', payment = 50 },
            ['1'] = { name = 'Novice', payment = 75 },
            ['2'] = { name = 'Experienced', payment = 100 },
            ['3'] = { name = 'Advanced', payment = 125 },
            ['4'] = { name = 'Manager', payment = 150, isboss = true },
        },
    },
    {
        name = 'bennys', label = 'Benny\'s Original Motor Works', defaultDuty = true, offDutyPay = false, type = 'mechanic',
        grades = {
            ['0'] = { name = 'Recruit', payment = 50 },
            ['1'] = { name = 'Novice', payment = 75 },
            ['2'] = { name = 'Experienced', payment = 100 },
            ['3'] = { name = 'Advanced', payment = 125 },
            ['4'] = { name = 'Manager', payment = 150, isboss = true },
        },
    },
    {
        name = 'bus', label = 'Bus', defaultDuty = true, offDutyPay = false,
        grades = {
            ['0'] = { name = 'Driver', payment = 50 },
        },
    },
    {
        name = 'cardealer', label = 'Vehicle Dealer', defaultDuty = true, offDutyPay = false,
        grades = {
            ['0'] = { name = 'Recruit', payment = 50 },
            ['1'] = { name = 'Showroom Sales', payment = 75 },
            ['2'] = { name = 'Business Sales', payment = 100 },
            ['3'] = { name = 'Finance', payment = 125 },
            ['4'] = { name = 'Manager', payment = 150, isboss = true },
        },
    },
    {
        name = 'garbage', label = 'Garbage', defaultDuty = true, offDutyPay = false,
        grades = {
            ['0'] = { name = 'Collector', payment = 50 },
        },
    },
    {
        name = 'hotdog', label = 'Hotdog', defaultDuty = true, offDutyPay = false,
        grades = {
            ['0'] = { name = 'Sales', payment = 50 },
        },
    },
    {
        name = 'judge', label = 'Honorary', defaultDuty = true, offDutyPay = false,
        grades = {
            ['0'] = { name = 'Judge', payment = 100 },
        },
    },
    {
        name = 'lawyer', label = 'Law Firm', defaultDuty = true, offDutyPay = false,
        grades = {
            ['0'] = { name = 'Associate', payment = 50 },
        },
    },
    {
        name = 'mechanic2', label = 'LS Customs', defaultDuty = true, offDutyPay = false, type = 'mechanic',
        grades = {
            ['0'] = { name = 'Recruit', payment = 50 },
            ['1'] = { name = 'Novice', payment = 75 },
            ['2'] = { name = 'Experienced', payment = 100 },
            ['3'] = { name = 'Advanced', payment = 125 },
            ['4'] = { name = 'Manager', payment = 150, isboss = true },
        },
    },
    {
        name = 'mechanic3', label = 'LS Customs', defaultDuty = true, offDutyPay = false, type = 'mechanic',
        grades = {
            ['0'] = { name = 'Recruit', payment = 50 },
            ['1'] = { name = 'Novice', payment = 75 },
            ['2'] = { name = 'Experienced', payment = 100 },
            ['3'] = { name = 'Advanced', payment = 125 },
            ['4'] = { name = 'Manager', payment = 150, isboss = true },
        },
    },
    {
        name = 'news', label = 'Weazel News', defaultDuty = true, offDutyPay = false,
        grades = {
            ['0'] = { name = 'Journalist', payment = 50 },
        },
    },
    {
        name = 'realestate', label = 'Real Estate', defaultDuty = true, offDutyPay = false,
        grades = {
            ['0'] = { name = 'Recruit', payment = 50 },
            ['1'] = { name = 'House Sales', payment = 75 },
            ['2'] = { name = 'Business Sales', payment = 100 },
            ['3'] = { name = 'Broker', payment = 125 },
            ['4'] = { name = 'Manager', payment = 150, isboss = true },
        },
    },
    {
        name = 'taxi', label = 'Taxi', defaultDuty = true, offDutyPay = false,
        grades = {
            ['0'] = { name = 'Recruit', payment = 50 },
            ['1'] = { name = 'Driver', payment = 75 },
            ['2'] = { name = 'Event Driver', payment = 100 },
            ['3'] = { name = 'Sales', payment = 125 },
            ['4'] = { name = 'Manager', payment = 150, isboss = true },
        },
    },
    {
        name = 'trucker', label = 'Trucker', defaultDuty = true, offDutyPay = false,
        grades = {
            ['0'] = { name = 'Driver', payment = 50 },
        },
    },
    {
        name = 'vineyard', label = 'Vineyard', defaultDuty = true, offDutyPay = false,
        grades = {
            ['0'] = { name = 'Picker', payment = 50 },
        },
    },
}
