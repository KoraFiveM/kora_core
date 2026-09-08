-- Vanilla GTA/FiveM weapon catalogue. These are registry records rather than
-- inventory slots: qbcore and qbinventory both resolve an item's definition
-- through this list, and weapons are consequently always non-stackable.
--
-- `ammotype` intentionally keeps GTA's native ammo hash name. Inventory ammo
-- packs expose the matching value in shared/items.lua, so a weapon system can
-- map packs to natives without inventing another taxonomy.
QBCoreSeed = QBCoreSeed or {}

-- Inventory applies these only while the corresponding weapon is actually in
-- a player's hand. Everything omitted here deliberately retains native damage
-- and critical-hit behaviour.
local damageSettings = {
    weapon_unarmed = { modifier = 0.2, disableCriticalHits = true },
    weapon_dagger = { modifier = 0.6, disableCriticalHits = true },
    weapon_bat = { modifier = 0.4, disableCriticalHits = true },
    weapon_bottle = { modifier = 0.6, disableCriticalHits = true },
    weapon_crowbar = { modifier = 0.6, disableCriticalHits = true },
    weapon_flashlight = { modifier = 0.4, disableCriticalHits = true },
    weapon_hammer = { modifier = 0.4, disableCriticalHits = true },
    weapon_hatchet = { modifier = 0.5, disableCriticalHits = true },
    weapon_knuckle = { modifier = 0.4, disableCriticalHits = true },
    weapon_knife = { modifier = 0.4, disableCriticalHits = true },
    weapon_machete = { modifier = 0.5, disableCriticalHits = true },
    weapon_switchblade = { modifier = 0.5, disableCriticalHits = true },
    weapon_nightstick = { modifier = 0.4, disableCriticalHits = true },
    weapon_wrench = { modifier = 0.6, disableCriticalHits = true },
    weapon_pistol = { modifier = 0.8, disableCriticalHits = true },
    weapon_pistol_mk2 = { modifier = 0.9, disableCriticalHits = true },
    weapon_combatpistol = { modifier = 1.0, disableCriticalHits = true },
    weapon_appistol = { modifier = 0.4, disableCriticalHits = true },
    weapon_pistol50 = { modifier = 1.4, disableCriticalHits = true },
    weapon_snspistol = { modifier = 1.0, disableCriticalHits = true },
    weapon_heavypistol = { modifier = 0.1, disableCriticalHits = true },
    weapon_vintagepistol = { modifier = 0.8, disableCriticalHits = true },
    weapon_flaregun = { modifier = 0.1, disableCriticalHits = true },
    weapon_marksmanpistol = { modifier = 0.1, disableCriticalHits = true },
    weapon_revolver = { modifier = 0.5, disableCriticalHits = true },
    weapon_microsmg = { modifier = 0.5, disableCriticalHits = true },
    weapon_minismg = { modifier = 0.5, disableCriticalHits = true },
    weapon_smg = { modifier = 0.5, disableCriticalHits = true },
    weapon_smg_mk2 = { modifier = 0.1, disableCriticalHits = true },
    weapon_assaultsmg = { modifier = 1.0, disableCriticalHits = true },
    weapon_combatpdw = { modifier = 0.5, disableCriticalHits = true },
    weapon_machinepistol = { modifier = 0.5, disableCriticalHits = true },
    weapon_pumpshotgun = { modifier = 0.4, disableCriticalHits = true },
    weapon_pumpshotgun_mk2 = { modifier = 0.4, disableCriticalHits = true },
    weapon_dbshotgun = { modifier = 0.4, disableCriticalHits = true },
    weapon_assaultrifle = { modifier = 0.4, disableCriticalHits = true },
    weapon_carbinerifle_mk2 = { modifier = 0.6, disableCriticalHits = true },
    weapon_compactrifle = { modifier = 0.5, disableCriticalHits = true },
    weapon_mg = { modifier = 0.1, disableCriticalHits = true },
    weapon_combatmg = { modifier = 0.1, disableCriticalHits = true },
    weapon_combatmg_mk2 = { modifier = 0.1, disableCriticalHits = true },
    weapon_proxmine = { modifier = 1.5, disableCriticalHits = true },
    weapon_bzgas = { modifier = 0.1, disableCriticalHits = true },
    weapon_molotov = { modifier = 1.0, disableCriticalHits = true },
    weapon_smokegrenade = { modifier = 0.1, disableCriticalHits = true },
}

local function weapon(name, label, ammotype, weight, weapontype)
    local damage = damageSettings[name] or {}
    return {
        name = name,
        label = label,
        ammotype = ammotype,
        ammoItem = ammotype and (QBCoreSeed.ammoItems and QBCoreSeed.ammoItems[ammotype]) or nil,
        weight = weight,
        type = 'weapon',
        weapontype = weapontype,
        damageModifier = damage.modifier or 1.0,
        disableCriticalHits = damage.disableCriticalHits == true,
        unique = true,
        useable = true,
        image = name .. '.png',
        imageUrl = QBCoreSeed.imageUrl(name),
        shouldClose = true,
    }
end

QBCoreSeed.weapons = {
    -- Melee
    weapon('weapon_unarmed', 'Fists', nil, 0, 'Melee'),
    weapon('weapon_dagger', 'Antique Cavalry Dagger', nil, 400, 'Melee'),
    weapon('weapon_bat', 'Baseball Bat', nil, 1200, 'Melee'),
    weapon('weapon_bottle', 'Broken Bottle', nil, 400, 'Melee'),
    weapon('weapon_crowbar', 'Crowbar', nil, 2500, 'Melee'),
    weapon('weapon_flashlight', 'Flashlight', nil, 450, 'Melee'),
    weapon('weapon_golfclub', 'Golf Club', nil, 900, 'Melee'),
    weapon('weapon_hammer', 'Hammer', nil, 1200, 'Melee'),
    weapon('weapon_hatchet', 'Hatchet', nil, 1100, 'Melee'),
    weapon('weapon_knuckle', 'Knuckle Dusters', nil, 300, 'Melee'),
    weapon('weapon_knife', 'Knife', nil, 500, 'Melee'),
    weapon('weapon_machete', 'Machete', nil, 900, 'Melee'),
    weapon('weapon_switchblade', 'Switchblade', nil, 300, 'Melee'),
    weapon('weapon_nightstick', 'Nightstick', nil, 850, 'Melee'),
    weapon('weapon_wrench', 'Pipe Wrench', nil, 1800, 'Melee'),
    weapon('weapon_battleaxe', 'Battle Axe', nil, 2200, 'Melee'),
    weapon('weapon_poolcue', 'Pool Cue', nil, 800, 'Melee'),
    weapon('weapon_stone_hatchet', 'Stone Hatchet', nil, 1300, 'Melee'),
    weapon('weapon_candycane', 'Candy Cane', nil, 250, 'Melee'),

    -- Handguns
    weapon('weapon_pistol', 'Pistol', 'AMMO_PISTOL', 1100, 'Pistol'),
    weapon('weapon_pistol_mk2', 'Pistol Mk II', 'AMMO_PISTOL', 1200, 'Pistol'),
    weapon('weapon_combatpistol', 'Combat Pistol', 'AMMO_PISTOL', 1150, 'Pistol'),
    weapon('weapon_appistol', 'AP Pistol', 'AMMO_PISTOL', 1050, 'Pistol'),
    weapon('weapon_stungun', 'Stun Gun', 'AMMO_STUNGUN', 700, 'Pistol'),
    weapon('weapon_stungun_mp', 'Stun Gun MP', 'AMMO_STUNGUN', 700, 'Pistol'),
    weapon('weapon_pistol50', 'Pistol .50', 'AMMO_PISTOL', 1350, 'Pistol'),
    weapon('weapon_snspistol', 'SNS Pistol', 'AMMO_PISTOL', 750, 'Pistol'),
    weapon('weapon_snspistol_mk2', 'SNS Pistol Mk II', 'AMMO_PISTOL', 850, 'Pistol'),
    weapon('weapon_heavypistol', 'Heavy Pistol', 'AMMO_PISTOL', 1500, 'Pistol'),
    weapon('weapon_vintagepistol', 'Vintage Pistol', 'AMMO_PISTOL', 900, 'Pistol'),
    weapon('weapon_flaregun', 'Flare Gun', 'AMMO_FLARE', 1000, 'Pistol'),
    weapon('weapon_marksmanpistol', 'Marksman Pistol', 'AMMO_PISTOL', 1400, 'Pistol'),
    weapon('weapon_revolver', 'Heavy Revolver', 'AMMO_PISTOL', 1700, 'Pistol'),
    weapon('weapon_revolver_mk2', 'Heavy Revolver Mk II', 'AMMO_PISTOL', 1800, 'Pistol'),
    weapon('weapon_doubleaction', 'Double-Action Revolver', 'AMMO_PISTOL', 1550, 'Pistol'),
    weapon('weapon_raypistol', 'Up-n-Atomizer', 'AMMO_PISTOL', 1250, 'Pistol'),
    weapon('weapon_ceramicpistol', 'Ceramic Pistol', 'AMMO_PISTOL', 850, 'Pistol'),
    weapon('weapon_navyrevolver', 'Navy Revolver', 'AMMO_PISTOL', 1650, 'Pistol'),
    weapon('weapon_gadgetpistol', 'Perico Pistol', 'AMMO_PISTOL', 1000, 'Pistol'),
    weapon('weapon_pistolxm3', 'WM 29 Pistol', 'AMMO_PISTOL', 1100, 'Pistol'),

    -- Submachine guns
    weapon('weapon_microsmg', 'Micro SMG', 'AMMO_SMG', 1800, 'SMG'),
    weapon('weapon_smg', 'SMG', 'AMMO_SMG', 2500, 'SMG'),
    weapon('weapon_smg_mk2', 'SMG Mk II', 'AMMO_SMG', 2700, 'SMG'),
    weapon('weapon_assaultsmg', 'Assault SMG', 'AMMO_SMG', 3000, 'SMG'),
    weapon('weapon_combatpdw', 'Combat PDW', 'AMMO_SMG', 3200, 'SMG'),
    weapon('weapon_machinepistol', 'Machine Pistol', 'AMMO_SMG', 1600, 'SMG'),
    weapon('weapon_minismg', 'Mini SMG', 'AMMO_SMG', 1500, 'SMG'),
    weapon('weapon_raycarbine', 'Unholy Hellbringer', 'AMMO_SMG', 3900, 'SMG'),
    weapon('weapon_tacticalsmg', 'Tactical SMG', 'AMMO_SMG', 1900, 'SMG'),

    -- Shotguns
    weapon('weapon_pumpshotgun', 'Pump Shotgun', 'AMMO_SHOTGUN', 3600, 'Shotgun'),
    weapon('weapon_pumpshotgun_mk2', 'Pump Shotgun Mk II', 'AMMO_SHOTGUN', 3900, 'Shotgun'),
    weapon('weapon_sawnoffshotgun', 'Sawed-Off Shotgun', 'AMMO_SHOTGUN', 2700, 'Shotgun'),
    weapon('weapon_assaultshotgun', 'Assault Shotgun', 'AMMO_SHOTGUN', 4400, 'Shotgun'),
    weapon('weapon_bullpupshotgun', 'Bullpup Shotgun', 'AMMO_SHOTGUN', 3500, 'Shotgun'),
    weapon('weapon_musket', 'Musket', 'AMMO_MUSKET', 4300, 'Shotgun'),
    weapon('weapon_heavyshotgun', 'Heavy Shotgun', 'AMMO_SHOTGUN', 5200, 'Shotgun'),
    weapon('weapon_dbshotgun', 'Double Barrel Shotgun', 'AMMO_SHOTGUN', 3300, 'Shotgun'),
    weapon('weapon_autoshotgun', 'Sweeper Shotgun', 'AMMO_SHOTGUN', 4100, 'Shotgun'),
    weapon('weapon_combatshotgun', 'Combat Shotgun', 'AMMO_SHOTGUN', 4600, 'Shotgun'),

    -- Assault rifles
    weapon('weapon_assaultrifle', 'Assault Rifle', 'AMMO_RIFLE', 3800, 'Rifle'),
    weapon('weapon_assaultrifle_mk2', 'Assault Rifle Mk II', 'AMMO_RIFLE', 4100, 'Rifle'),
    weapon('weapon_carbinerifle', 'Carbine Rifle', 'AMMO_RIFLE', 3500, 'Rifle'),
    weapon('weapon_carbinerifle_mk2', 'Carbine Rifle Mk II', 'AMMO_RIFLE', 3800, 'Rifle'),
    weapon('weapon_advancedrifle', 'Advanced Rifle', 'AMMO_RIFLE', 3600, 'Rifle'),
    weapon('weapon_specialcarbine', 'Special Carbine', 'AMMO_RIFLE', 3400, 'Rifle'),
    weapon('weapon_specialcarbine_mk2', 'Special Carbine Mk II', 'AMMO_RIFLE', 3700, 'Rifle'),
    weapon('weapon_bullpuprifle', 'Bullpup Rifle', 'AMMO_RIFLE', 3400, 'Rifle'),
    weapon('weapon_bullpuprifle_mk2', 'Bullpup Rifle Mk II', 'AMMO_RIFLE', 3700, 'Rifle'),
    weapon('weapon_compactrifle', 'Compact Rifle', 'AMMO_RIFLE', 2800, 'Rifle'),
    weapon('weapon_militaryrifle', 'Military Rifle', 'AMMO_RIFLE', 4000, 'Rifle'),
    weapon('weapon_heavyrifle', 'Heavy Rifle', 'AMMO_RIFLE', 4600, 'Rifle'),
    weapon('weapon_tacticalrifle', 'Service Carbine', 'AMMO_RIFLE', 3900, 'Rifle'),
    weapon('weapon_battlerifle', 'Battle Rifle', 'AMMO_RIFLE', 4400, 'Rifle'),

    -- Light machine guns
    weapon('weapon_mg', 'MG', 'AMMO_MG', 7000, 'LMG'),
    weapon('weapon_combatmg', 'Combat MG', 'AMMO_MG', 7800, 'LMG'),
    weapon('weapon_combatmg_mk2', 'Combat MG Mk II', 'AMMO_MG', 8200, 'LMG'),
    weapon('weapon_gusenberg', 'Gusenberg Sweeper', 'AMMO_MG', 6500, 'LMG'),

    -- Sniper rifles
    weapon('weapon_sniperrifle', 'Sniper Rifle', 'AMMO_SNIPER', 5800, 'Sniper'),
    weapon('weapon_heavysniper', 'Heavy Sniper', 'AMMO_SNIPER', 7600, 'Sniper'),
    weapon('weapon_heavysniper_mk2', 'Heavy Sniper Mk II', 'AMMO_SNIPER', 8200, 'Sniper'),
    weapon('weapon_marksmanrifle', 'Marksman Rifle', 'AMMO_SNIPER', 5200, 'Sniper'),
    weapon('weapon_marksmanrifle_mk2', 'Marksman Rifle Mk II', 'AMMO_SNIPER', 5500, 'Sniper'),
    weapon('weapon_precisionrifle', 'Precision Rifle', 'AMMO_SNIPER', 6000, 'Sniper'),

    -- Heavy weapons
    weapon('weapon_rpg', 'Rocket Launcher', 'AMMO_RPG', 8500, 'Heavy'),
    weapon('weapon_grenadelauncher', 'Grenade Launcher', 'AMMO_GRENADELAUNCHER', 7800, 'Heavy'),
    weapon('weapon_grenadelauncher_smoke', 'Smoke Grenade Launcher', 'AMMO_GRENADELAUNCHER_SMOKE', 7600, 'Heavy'),
    weapon('weapon_minigun', 'Minigun', 'AMMO_MINIGUN', 22000, 'Heavy'),
    weapon('weapon_firework', 'Firework Launcher', 'AMMO_FIREWORK', 5000, 'Heavy'),
    weapon('weapon_railgun', 'Railgun', 'AMMO_RAILGUN', 9000, 'Heavy'),
    weapon('weapon_hominglauncher', 'Homing Launcher', 'AMMO_HOMINGLAUNCHER', 9000, 'Heavy'),
    weapon('weapon_compactlauncher', 'Compact Grenade Launcher', 'AMMO_GRENADELAUNCHER', 6400, 'Heavy'),
    weapon('weapon_rayminigun', 'Widowmaker', 'AMMO_MINIGUN', 8500, 'Heavy'),
    weapon('weapon_railgunxm3', 'Railgun XM3', 'AMMO_RAILGUN', 9500, 'Heavy'),
    weapon('weapon_emplauncher', 'EMP Launcher', 'AMMO_EMPLAUNCHER', 7000, 'Heavy'),

    -- Throwables / utility. They are unique weapon records because the native
    -- treats the object as a weapon; individual packs are managed as item count.
    weapon('weapon_grenade', 'Grenade', 'AMMO_GRENADE', 400, 'Throwable'),
    weapon('weapon_bzgas', 'BZ Gas', 'AMMO_BZGAS', 350, 'Throwable'),
    weapon('weapon_molotov', 'Molotov Cocktail', 'AMMO_MOLOTOV', 600, 'Throwable'),
    weapon('weapon_stickybomb', 'Sticky Bomb', 'AMMO_STICKYBOMB', 700, 'Throwable'),
    weapon('weapon_proxmine', 'Proximity Mine', 'AMMO_PROXMINE', 750, 'Throwable'),
    weapon('weapon_snowball', 'Snowball', 'AMMO_SNOWBALL', 100, 'Throwable'),
    weapon('weapon_pipebomb', 'Pipe Bomb', 'AMMO_PIPEBOMB', 650, 'Throwable'),
    weapon('weapon_ball', 'Ball', 'AMMO_BALL', 250, 'Throwable'),
    weapon('weapon_smokegrenade', 'Tear Gas', 'AMMO_SMOKEGRENADE', 400, 'Throwable'),
    weapon('weapon_flare', 'Flare', 'AMMO_FLARE', 150, 'Throwable'),
    weapon('weapon_acidpackage', 'Acid Package', 'AMMO_ACIDPACKAGE', 500, 'Throwable'),

    -- Equipment that GTA exposes through the same weapon native family.
    weapon('weapon_petrolcan', 'Jerry Can', 'AMMO_PETROLCAN', 1800, 'Equipment'),
    weapon('weapon_fireextinguisher', 'Fire Extinguisher', 'AMMO_FIREEXTINGUISHER', 6000, 'Equipment'),
    weapon('weapon_hazardcan', 'Hazardous Jerry Can', 'AMMO_HAZARDCAN', 1800, 'Equipment'),
    weapon('weapon_fertilizercan', 'Fertilizer Can', 'AMMO_FERTILIZERCAN', 1800, 'Equipment'),
    weapon('weapon_parachute', 'Parachute', nil, 1000, 'Equipment'),
}
