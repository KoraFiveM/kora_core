KoraCoreSeed = KoraCoreSeed or {}

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

-- Keep server-specific weapon records and overrides in this legacy table.
KoraCoreSeed.weapons = KoraCoreSeed.weapons or {
}

do
    local bundled = KoraCoreSeed.inventoryWeapons or {}
    local native = {}
    local ammoItems = KoraCoreSeed.ammoItems or {}
    for _, record in ipairs(bundled) do
        native[record.name] = record
    end
    for _, record in ipairs(KoraCoreSeed.weapons) do
        local current = native[record.name]
        if current then
            for field, value in pairs(record) do
                current[field] = value
            end
        else
            bundled[#bundled + 1] = record
            native[record.name] = record
        end
    end

    for _, record in ipairs(bundled) do
        if record.useable == true then
            local damage = damageSettings[record.name] or {}
            if record.ammoItem == nil then record.ammoItem = ammoItems[record.ammotype] end
            if record.damageModifier == nil then record.damageModifier = damage.modifier or 1.0 end
            if record.disableCriticalHits == nil then record.disableCriticalHits = damage.disableCriticalHits == true end
        end
    end

    local upstream = KoraCoreSeed.upstreamWeapons or {}
    local names = {}
    for name in pairs(upstream) do
        names[#names + 1] = name
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local source, current = upstream[name], native[name]
        if current then
            for field, value in pairs(source) do
                if current[field] == nil then current[field] = value end
            end
        else
            bundled[#bundled + 1] = source
        end
    end

    KoraCoreSeed.weapons = bundled
    KoraCoreSeed.inventoryWeapons = nil
    KoraCoreSeed.upstreamWeapons = nil
end

KoraCoreSeed.legacyWeaponMetadata = {
    gadget_parachute = { name = 'gadget_parachute', label = 'Parachute', weapontype = 'Miscellaneous', ammotype = nil, damagereason = 'Died' },
    weapon_advancedrifle = { name = 'weapon_advancedrifle', label = 'Advanced Rifle', weapontype = 'Assault Rifle', ammotype = 'AMMO_RIFLE', damagereason = 'Ended / Rifled / Shot down / Floored' },
    weapon_animal = { name = 'weapon_animal', label = 'Animal', weapontype = 'Animals', ammotype = nil, damagereason = 'Mauled' },
    weapon_appistol = { name = 'weapon_appistol', label = 'AP Pistol', weapontype = 'Pistol', ammotype = 'AMMO_PISTOL', damagereason = 'Pistoled / Blasted / Plugged / Bust a cap in' },
    weapon_assaultrifle = { name = 'weapon_assaultrifle', label = 'Assault Rifle', weapontype = 'Assault Rifle', ammotype = 'AMMO_RIFLE', damagereason = 'Ended / Rifled / Shot down / Floored' },
    weapon_assaultrifle_mk2 = { name = 'weapon_assaultrifle_mk2', label = 'Assault Rifle MK2', weapontype = 'Assault Rifle', ammotype = 'AMMO_RIFLE', damagereason = 'Ended / Rifled / Shot down / Floored' },
    weapon_assaultshotgun = { name = 'weapon_assaultshotgun', label = 'Assault Shotgun', weapontype = 'Shotgun', ammotype = 'AMMO_SHOTGUN', damagereason = 'Devastated / Pulverized / Shotgunned' },
    weapon_assaultsmg = { name = 'weapon_assaultsmg', label = 'Assault SMG', weapontype = 'Submachine Gun', ammotype = 'AMMO_SMG', damagereason = 'Riddled / Drilled / Finished / Submachine Gunned' },
    weapon_autoshotgun = { name = 'weapon_autoshotgun', label = 'Auto Shotgun', weapontype = 'Shotgun', ammotype = 'AMMO_SHOTGUN', damagereason = 'Devastated / Pulverized / Shotgunned' },
    weapon_ball = { name = 'weapon_ball', label = 'Ball', weapontype = 'Throwable', ammotype = 'AMMO_BALL', damagereason = 'Died' },
    weapon_barbed_wire = { name = 'weapon_barbed_wire', label = 'Barbed Wire', weapontype = 'Miscellaneous', ammotype = nil, damagereason = 'Prodded' },
    weapon_bat = { name = 'weapon_bat', label = 'Bat', weapontype = 'Melee', ammotype = nil, damagereason = 'Melee killed / Whacked / Executed / Beat down / Murdered / Battered' },
    weapon_battleaxe = { name = 'weapon_battleaxe', label = 'Battle Axe', weapontype = 'Melee', ammotype = nil, damagereason = 'Knifed / Stabbed / Eviscerated' },
    weapon_bleeding = { name = 'weapon_bleeding', label = 'Bleeding', weapontype = 'Miscellaneous', ammotype = nil, damagereason = 'Bled out' },
    weapon_bottle = { name = 'weapon_bottle', label = 'Broken Bottle', weapontype = 'Melee', ammotype = nil, damagereason = 'Knifed / Stabbed / Eviscerated' },
    weapon_bread = { name = 'weapon_bread', label = 'Baguette', weapontype = 'Melee', ammotype = nil, damagereason = 'Melee killed / Whacked / Executed / Beat down / Murdered / Battered' },
    weapon_briefcase = { name = 'weapon_briefcase', label = 'Briefcase', weapontype = 'Melee', ammotype = nil, damagereason = 'Melee killed / Whacked / Executed / Beat down / Murdered / Battered' },
    weapon_briefcase_02 = { name = 'weapon_briefcase_02', label = 'Briefcase', weapontype = 'Melee', ammotype = nil, damagereason = 'Melee killed / Whacked / Executed / Beat down / Murdered / Battered' },
    weapon_bullpuprifle = { name = 'weapon_bullpuprifle', label = 'Bullpup Rifle', weapontype = 'Assault Rifle', ammotype = 'AMMO_RIFLE', damagereason = 'Ended / Rifled / Shot down / Floored' },
    weapon_bullpuprifle_mk2 = { name = 'weapon_bullpuprifle_mk2', label = 'Bull Puprifle MK2', weapontype = 'Assault Rifle', ammotype = 'AMMO_RIFLE', damagereason = 'Ended / Rifled / Shot down / Floored' },
    weapon_bullpupshotgun = { name = 'weapon_bullpupshotgun', label = 'Bullpup Shotgun', weapontype = 'Shotgun', ammotype = 'AMMO_SHOTGUN', damagereason = 'Devastated / Pulverized / Shotgunned' },
    weapon_bzgas = { name = 'weapon_bzgas', label = 'BZ Gas', weapontype = 'Throwable', ammotype = nil, damagereason = 'Died' },
    weapon_candycane = { name = 'weapon_candycane', label = 'Candy Cane', weapontype = 'Melee', ammotype = nil, damagereason = 'Melee Killed / Whacked / Executed / Beat down / Musrdered / Battered / Candy Caned' },
    weapon_carbinerifle = { name = 'weapon_carbinerifle', label = 'Carbine Rifle', weapontype = 'Assault Rifle', ammotype = 'AMMO_RIFLE', damagereason = 'Ended / Rifled / Shot down / Floored' },
    weapon_carbinerifle_mk2 = { name = 'weapon_carbinerifle_mk2', label = 'Carbine Rifle MK2', weapontype = 'Assault Rifle', ammotype = 'AMMO_RIFLE', damagereason = 'Ended / Rifled / Shot down / Floored' },
    weapon_ceramicpistol = { name = 'weapon_ceramicpistol', label = 'Ceramic Pistol', weapontype = 'Pistol', ammotype = 'AMMO_PISTOL', damagereason = 'Pistoled / Blasted / Plugged / Bust a cap in' },
    weapon_combatmg = { name = 'weapon_combatmg', label = 'Combat MG', weapontype = 'Light Machine Gun', ammotype = 'AMMO_MG', damagereason = 'Machine gunned / Sprayed / Ruined' },
    weapon_combatmg_mk2 = { name = 'weapon_combatmg_mk2', label = 'Combat MG MK2', weapontype = 'Light Machine Gun', ammotype = 'AMMO_MG', damagereason = 'Machine gunned / Sprayed / Ruined' },
    weapon_combatpdw = { name = 'weapon_combatpdw', label = 'Combat PDW', weapontype = 'Submachine Gun', ammotype = 'AMMO_SMG', damagereason = 'Riddled / Drilled / Finished / Submachine Gunned' },
    weapon_combatpistol = { name = 'weapon_combatpistol', label = 'Combat Pistol', weapontype = 'Pistol', ammotype = 'AMMO_PISTOL', damagereason = 'Pistoled / Blasted / Plugged / Bust a cap in' },
    weapon_combatshotgun = { name = 'weapon_combatshotgun', label = 'Combat Shotgun', weapontype = 'Shotgun', ammotype = 'AMMO_SHOTGUN', damagereason = 'Devastated / Pulverized / Shotgunned' },
    weapon_compactlauncher = { name = 'weapon_compactlauncher', label = 'Compact Launcher', weapontype = 'Heavy Weapons', ammotype = nil, damagereason = 'Killed / Exploded / Obliterated / Destroyed / Erased / Annihilated' },
    weapon_compactrifle = { name = 'weapon_compactrifle', label = 'Compact Rifle', weapontype = 'Assault Rifle', ammotype = 'AMMO_RIFLE', damagereason = 'Ended / Rifled / Shot down / Floored' },
    weapon_cougar = { name = 'weapon_cougar', label = 'Cougar', weapontype = 'Animals', ammotype = nil, damagereason = 'Mauled' },
    weapon_crowbar = { name = 'weapon_crowbar', label = 'Crowbar', weapontype = 'Melee', ammotype = nil, damagereason = 'Melee killed / Whacked / Executed / Beat down / Murdered / Battered' },
    weapon_dagger = { name = 'weapon_dagger', label = 'Dagger', weapontype = 'Melee', ammotype = nil, damagereason = 'Knifed / Stabbed / Eviscerated' },
    weapon_dbshotgun = { name = 'weapon_dbshotgun', label = 'Double-barrel Shotgun', weapontype = 'Shotgun', ammotype = 'AMMO_SHOTGUN', damagereason = 'Devastated / Pulverized / Shotgunned' },
    weapon_doubleaction = { name = 'weapon_doubleaction', label = 'Double Action Revolver', weapontype = 'Pistol', ammotype = 'AMMO_PISTOL', damagereason = 'Pistoled / Blasted / Plugged / Bust a cap in' },
    weapon_drowning = { name = 'weapon_drowning', label = 'Drowning', weapontype = 'Miscellaneous', ammotype = nil, damagereason = 'Died' },
    weapon_drowning_in_vehicle = { name = 'weapon_drowning_in_vehicle', label = 'Drowning in a Vehicle', weapontype = 'Miscellaneous', ammotype = nil, damagereason = 'Died' },
    weapon_electric_fence = { name = 'weapon_electric_fence', label = 'Electric Fence', weapontype = 'Miscellaneous', ammotype = nil, damagereason = 'Fried' },
    weapon_emplauncher = { name = 'weapon_emplauncher', label = 'EMP Launcher', weapontype = 'Heavy Weapons', ammotype = 'AMMO_EMPLAUNCHER', damagereason = 'Died' },
    weapon_exhaustion = { name = 'weapon_exhaustion', label = 'Exhaustion', weapontype = 'Miscellaneous', ammotype = nil, damagereason = 'Died' },
    weapon_explosion = { name = 'weapon_explosion', label = 'Explosion', weapontype = 'Miscellaneous', ammotype = nil, damagereason = 'Killed / Exploded / Obliterated / Destroyed / Erased / Annihilated' },
    weapon_fall = { name = 'weapon_fall', label = 'Fall', weapontype = 'Miscellaneous', ammotype = nil, damagereason = 'Committed suicide' },
    weapon_fertilizercan = { name = 'weapon_fertilizercan', label = 'Fertilizer Can', weapontype = 'Miscellaneous', ammotype = 'AMMO_FERTILIZERCAN', damagereason = 'Died' },
    weapon_fire = { name = 'weapon_fire', label = 'Fire', weapontype = 'Miscellaneous', ammotype = nil, damagereason = 'Torched / Flambeed / Barbecued' },
    weapon_fireextinguisher = { name = 'weapon_fireextinguisher', label = 'Fire Extinguisher', weapontype = 'Miscellaneous', ammotype = nil, damagereason = 'Died' },
    weapon_firework = { name = 'weapon_firework', label = 'Firework Launcher', weapontype = 'Heavy Weapons', ammotype = nil, damagereason = 'Killed / Exploded / Obliterated / Destroyed / Erased / Annihilated' },
    weapon_flare = { name = 'weapon_flare', label = 'Flare pistol', weapontype = 'Throwable', ammotype = 'AMMO_FLARE', damagereason = 'Died' },
    weapon_flaregun = { name = 'weapon_flaregun', label = 'Flare Gun', weapontype = 'Pistol', ammotype = 'AMMO_FLARE', damagereason = 'Died' },
    weapon_flashlight = { name = 'weapon_flashlight', label = 'Flashlight', weapontype = 'Melee', ammotype = nil, damagereason = 'Melee killed / Whacked / Executed / Beat down / Murdered / Battered' },
    weapon_gadgetpistol = { name = 'weapon_gadgetpistol', label = 'Gadget Pistol', weapontype = 'Pistol', ammotype = 'AMMO_PISTOL', damagereason = 'Pistoled / Blasted / Plugged / Bust a cap in' },
    weapon_garbagebag = { name = 'weapon_garbagebag', label = 'Garbage Bag', weapontype = 'Melee', ammotype = nil, damagereason = 'Melee killed / Whacked / Executed / Beat down / Murdered / Battered' },
    weapon_golfclub = { name = 'weapon_golfclub', label = 'Golfclub', weapontype = 'Melee', ammotype = nil, damagereason = 'Melee killed / Whacked / Executed / Beat down / Murdered / Battered' },
    weapon_grenade = { name = 'weapon_grenade', label = 'Grenade', weapontype = 'Throwable', ammotype = nil, damagereason = 'Bombed / Exploded / Detonated / Blew up' },
    weapon_grenadelauncher = { name = 'weapon_grenadelauncher', label = 'Grenade Launcher', weapontype = 'Heavy Weapons', ammotype = 'AMMO_GRENADELAUNCHER', damagereason = 'Killed / Exploded / Obliterated / Destroyed / Erased / Annihilated' },
    weapon_grenadelauncher_smoke = { name = 'weapon_grenadelauncher_smoke', label = 'Smoke Grenade Launcher', weapontype = 'Heavy Weapons', ammotype = 'AMMO_GRENADELAUNCHER', damagereason = 'Killed / Exploded / Obliterated / Destroyed / Erased / Annihilated' },
    weapon_gusenberg = { name = 'weapon_gusenberg', label = 'Thompson SMG', weapontype = 'Light Machine Gun', ammotype = 'AMMO_MG', damagereason = 'Machine gunned / Sprayed / Ruined' },
    weapon_hammer = { name = 'weapon_hammer', label = 'Hammer', weapontype = 'Melee', ammotype = nil, damagereason = 'Melee killed / Whacked / Executed / Beat down / Murdered / Battered' },
    weapon_handcuffs = { name = 'weapon_handcuffs', label = 'Handcuffs', weapontype = 'Melee', ammotype = nil, damagereason = 'Melee killed / Whacked / Executed / Beat down / Murdered / Battered' },
    weapon_hatchet = { name = 'weapon_hatchet', label = 'Hatchet', weapontype = 'Melee', ammotype = nil, damagereason = 'Knifed / Stabbed / Eviscerated' },
    weapon_hazardcan = { name = 'weapon_hazardcan', label = 'Hazardcan', weapontype = 'Miscellaneous', ammotype = 'AMMO_PETROLCAN', damagereason = 'Died' },
    weapon_heavypistol = { name = 'weapon_heavypistol', label = 'Heavy Pistol', weapontype = 'Pistol', ammotype = 'AMMO_PISTOL', damagereason = 'Pistoled / Blasted / Plugged / Bust a cap in' },
    weapon_heavyrifle = { name = 'weapon_heavyrifle', label = 'Heavy Rifle', weapontype = 'Assault Rifle', ammotype = 'AMMO_RIFLE', damagereason = 'Ended / Rifled / Shot down / Floored' },
    weapon_heavyshotgun = { name = 'weapon_heavyshotgun', label = 'Heavy Shotgun', weapontype = 'Shotgun', ammotype = 'AMMO_SHOTGUN', damagereason = 'Devastated / Pulverized / Shotgunned' },
    weapon_heavysniper = { name = 'weapon_heavysniper', label = 'Heavy Sniper', weapontype = 'Sniper Rifle', ammotype = 'AMMO_SNIPER', damagereason = 'Sniped / Picked off / Scoped' },
    weapon_heavysniper_mk2 = { name = 'weapon_heavysniper_mk2', label = 'Heavysniper MK2', weapontype = 'Sniper Rifle', ammotype = 'AMMO_SNIPER', damagereason = 'Sniped / Picked off / Scoped' },
    weapon_heli_crash = { name = 'weapon_heli_crash', label = 'Heli Crash', weapontype = 'Miscellaneous', ammotype = nil, damagereason = 'Helicopter Crash' },
    weapon_hit_by_water_cannon = { name = 'weapon_hit_by_water_cannon', label = 'Water Cannon', weapontype = 'Miscellaneous', ammotype = nil, damagereason = 'Died' },
    weapon_hominglauncher = { name = 'weapon_hominglauncher', label = 'Homing Launcher', weapontype = 'Heavy Weapons', ammotype = 'AMMO_STINGER', damagereason = 'Killed / Exploded / Obliterated / Destroyed / Erased / Annihilated' },
    weapon_knife = { name = 'weapon_knife', label = 'Knife', weapontype = 'Melee', ammotype = nil, damagereason = 'Knifed / Stabbed / Eviscerated' },
    weapon_knuckle = { name = 'weapon_knuckle', label = 'Knuckle', weapontype = 'Melee', ammotype = nil, damagereason = 'Melee killed / Whacked / Executed / Beat down / Murdered / Battered' },
    weapon_machete = { name = 'weapon_machete', label = 'Machete', weapontype = 'Melee', ammotype = nil, damagereason = 'Knifed / Stabbed / Eviscerated' },
    weapon_machinepistol = { name = 'weapon_machinepistol', label = 'Tec-9', weapontype = 'Submachine Gun', ammotype = 'AMMO_PISTOL', damagereason = 'Riddled / Drilled / Finished / Submachine Gunned' },
    weapon_marksmanpistol = { name = 'weapon_marksmanpistol', label = 'Marksman Pistol', weapontype = 'Pistol', ammotype = 'AMMO_PISTOL', damagereason = 'Pistoled / Blasted / Plugged / Bust a cap in' },
    weapon_marksmanrifle = { name = 'weapon_marksmanrifle', label = 'Marksman Rifle', weapontype = 'Sniper Rifle', ammotype = 'AMMO_SNIPER', damagereason = 'Sniped / Picked off / Scoped' },
    weapon_marksmanrifle_mk2 = { name = 'weapon_marksmanrifle_mk2', label = 'Marksman Rifle MK2', weapontype = 'Sniper Rifle', ammotype = 'AMMO_SNIPER', damagereason = 'Sniped / Picked off / Scoped' },
    weapon_mg = { name = 'weapon_mg', label = 'Machinegun', weapontype = 'Light Machine Gun', ammotype = 'AMMO_MG', damagereason = 'Machine gunned / Sprayed / Ruined' },
    weapon_microsmg = { name = 'weapon_microsmg', label = 'Micro SMG', weapontype = 'Submachine Gun', ammotype = 'AMMO_SMG', damagereason = 'Riddled / Drilled / Finished / Submachine Gunned' },
    weapon_militaryrifle = { name = 'weapon_militaryrifle', label = 'Military Rifle', weapontype = 'Assault Rifle', ammotype = 'AMMO_RIFLE', damagereason = 'Ended / Rifled / Shot down / Floored' },
    weapon_minigun = { name = 'weapon_minigun', label = 'Minigun', weapontype = 'Heavy Weapons', ammotype = 'AMMO_MINIGUN', damagereason = 'Killed / Exploded / Obliterated / Destroyed / Erased / Annihilated' },
    weapon_minismg = { name = 'weapon_minismg', label = 'Mini SMG', weapontype = 'Submachine Gun', ammotype = 'AMMO_SMG', damagereason = 'Riddled / Drilled / Finished / Submachine Gunned' },
    weapon_molotov = { name = 'weapon_molotov', label = 'Molotov', weapontype = 'Throwable', ammotype = nil, damagereason = 'Torched / Flambeed / Barbecued' },
    weapon_musket = { name = 'weapon_musket', label = 'Musket', weapontype = 'Shotgun', ammotype = 'AMMO_SHOTGUN', damagereason = 'Devastated / Pulverized / Shotgunned' },
    weapon_navyrevolver = { name = 'weapon_navyrevolver', label = 'Navy Revolver', weapontype = 'Pistol', ammotype = 'AMMO_PISTOL', damagereason = 'Pistoled / Blasted / Plugged / Bust a cap in' },
    weapon_nightstick = { name = 'weapon_nightstick', label = 'Nightstick', weapontype = 'Melee', ammotype = nil, damagereason = 'Melee killed / Whacked / Executed / Beat down / Murdered / Battered' },
    weapon_petrolcan = { name = 'weapon_petrolcan', label = 'Petrol Can', weapontype = 'Miscellaneous', ammotype = 'AMMO_PETROLCAN', damagereason = 'Died' },
    weapon_pipebomb = { name = 'weapon_pipebomb', label = 'Pipe Bomb', weapontype = 'Throwable', ammotype = nil, damagereason = 'Bombed / Exploded / Detonated / Blew up' },
    weapon_pistol = { name = 'weapon_pistol', label = 'Pistol', weapontype = 'Pistol', ammotype = 'AMMO_PISTOL', damagereason = 'Pistoled / Blasted / Plugged / Bust a cap in' },
    weapon_pistol50 = { name = 'weapon_pistol50', label = 'Pistol .50 Cal', weapontype = 'Pistol', ammotype = 'AMMO_PISTOL', damagereason = 'Pistoled / Blasted / Plugged / Bust a cap in' },
    weapon_pistol_mk2 = { name = 'weapon_pistol_mk2', label = 'Pistol Mk2', weapontype = 'Pistol', ammotype = 'AMMO_PISTOL', damagereason = 'Pistoled / Blasted / Plugged / Bust a cap in' },
    weapon_pistolxm3 = { name = 'weapon_pistolxm3', label = 'Pistol XM3', weapontype = 'Pistol', ammotype = 'AMMO_PISTOL', damagereason = 'Pistoled / Blasted / Plaugged / Bust a cap in' },
    weapon_poolcue = { name = 'weapon_poolcue', label = 'Poolcue', weapontype = 'Melee', ammotype = nil, damagereason = 'Melee killed / Whacked / Executed / Beat down / Murdered / Battered' },
    weapon_proxmine = { name = 'weapon_proxmine', label = 'Proxmine Grenade', weapontype = 'Throwable', ammotype = nil, damagereason = 'Bombed / Exploded / Detonated / Blew up' },
    weapon_pumpshotgun = { name = 'weapon_pumpshotgun', label = 'Pump Shotgun', weapontype = 'Shotgun', ammotype = 'AMMO_SHOTGUN', damagereason = 'Devastated / Pulverized / Shotgunned' },
    weapon_pumpshotgun_mk2 = { name = 'weapon_pumpshotgun_mk2', label = 'Pump Shotgun MK2', weapontype = 'Shotgun', ammotype = 'AMMO_SHOTGUN', damagereason = 'Devastated / Pulverized / Shotgunned' },
    weapon_railgun = { name = 'weapon_railgun', label = 'Railgun', weapontype = 'Heavy Weapons', ammotype = nil, damagereason = 'Killed / Exploded / Obliterated / Destroyed / Erased / Annihilated' },
    weapon_railgunxm3 = { name = 'weapon_railgunxm3', label = 'Railgun XM3', weapontype = 'Heavy Weapons', ammotype = nil, damagereason = 'Killed / Exploded / Obliterated / Destroyed / Erased / Annihilated' },
    weapon_rammed_by_car = { name = 'weapon_rammed_by_car', label = 'Rammed - Vehicle', weapontype = 'Miscellaneous', ammotype = nil, damagereason = 'Flattened / Ran over / Ran down' },
    weapon_raycarbine = { name = 'weapon_raycarbine', label = 'Raycarbine', weapontype = 'Submachine Gun', ammotype = 'AMMO_SMG', damagereason = 'Riddled / Drilled / Finished / Submachine Gunned' },
    weapon_rayminigun = { name = 'weapon_rayminigun', label = 'Ray Minigun', weapontype = 'Heavy Weapons', ammotype = 'AMMO_MINIGUN', damagereason = 'Killed / Exploded / Obliterated / Destroyed / Erased / Annihilated' },
    weapon_raypistol = { name = 'weapon_raypistol', label = 'Ray Pistol', weapontype = 'Pistol', ammotype = 'AMMO_PISTOL', damagereason = 'Pistoled / Blasted / Plugged / Bust a cap in' },
    weapon_remotesniper = { name = 'weapon_remotesniper', label = 'Remote Sniper', weapontype = 'Sniper Rifle', ammotype = 'AMMO_SNIPER_REMOTE', damagereason = 'Sniped / Picked off / Scoped' },
    weapon_revolver = { name = 'weapon_revolver', label = 'Revolver', weapontype = 'Pistol', ammotype = 'AMMO_PISTOL', damagereason = 'Pistoled / Blasted / Plugged / Bust a cap in' },
    weapon_revolver_mk2 = { name = 'weapon_revolver_mk2', label = 'Revolver MK2', weapontype = 'Pistol', ammotype = 'AMMO_PISTOL', damagereason = 'Pistoled / Blasted / Plugged / Bust a cap in' },
    weapon_rpg = { name = 'weapon_rpg', label = 'RPG', weapontype = 'Heavy Weapons', ammotype = 'AMMO_RPG', damagereason = 'Killed / Exploded / Obliterated / Destroyed / Erased / Annihilated' },
    weapon_run_over_by_car = { name = 'weapon_run_over_by_car', label = 'Run Over - Vehicle', weapontype = 'Miscellaneous', ammotype = nil, damagereason = 'Flattened / Ran over / Ran down' },
    weapon_sawnoffshotgun = { name = 'weapon_sawnoffshotgun', label = 'Sawn-off Shotgun', weapontype = 'Shotgun', ammotype = 'AMMO_SHOTGUN', damagereason = 'Devastated / Pulverized / Shotgunned' },
    weapon_smg = { name = 'weapon_smg', label = 'SMG', weapontype = 'Submachine Gun', ammotype = 'AMMO_SMG', damagereason = 'Riddled / Drilled / Finished / Submachine Gunned' },
    weapon_smg_mk2 = { name = 'weapon_smg_mk2', label = 'SMG MK2', weapontype = 'Submachine Gun', ammotype = 'AMMO_SMG', damagereason = 'Riddled / Drilled / Finished / Submachine Gunned' },
    weapon_smokegrenade = { name = 'weapon_smokegrenade', label = 'Smoke Grenade', weapontype = 'Throwable', ammotype = nil, damagereason = 'Died' },
    weapon_sniperrifle = { name = 'weapon_sniperrifle', label = 'Sniper Rifle', weapontype = 'Sniper Rifle', ammotype = 'AMMO_SNIPER', damagereason = 'Sniped / Picked off / Scoped' },
    weapon_snowball = { name = 'weapon_snowball', label = 'Snowball', weapontype = 'Throwable', ammotype = nil, damagereason = 'Died' },
    weapon_snspistol = { name = 'weapon_snspistol', label = 'SNS Pistol', weapontype = 'Pistol', ammotype = 'AMMO_PISTOL', damagereason = 'Pistoled / Blasted / Plugged / Bust a cap in' },
    weapon_snspistol_mk2 = { name = 'weapon_snspistol_mk2', label = 'SNS Pistol MK2', weapontype = 'Pistol', ammotype = 'AMMO_PISTOL', damagereason = 'Pistoled / Blasted / Plugged / Bust a cap in' },
    weapon_specialcarbine = { name = 'weapon_specialcarbine', label = 'Special Carbine', weapontype = 'Assault Rifle', ammotype = 'AMMO_RIFLE', damagereason = 'Ended / Rifled / Shot down / Floored' },
    weapon_specialcarbine_mk2 = { name = 'weapon_specialcarbine_mk2', label = 'Specialcarbine MK2', weapontype = 'Assault Rifle', ammotype = 'AMMO_RIFLE', damagereason = 'Ended / Rifled / Shot down / Floored' },
    weapon_stickybomb = { name = 'weapon_stickybomb', label = 'C4', weapontype = 'Throwable', ammotype = nil, damagereason = 'Bombed / Exploded / Detonated / Blew up' },
    weapon_stone_hatchet = { name = 'weapon_stone_hatchet', label = 'Stone Hatchet', weapontype = 'Melee', ammotype = nil, damagereason = 'Knifed / Stabbed / Eviscerated' },
    weapon_stungun = { name = 'weapon_stungun', label = 'Taser', weapontype = 'Pistol', ammotype = 'AMMO_STUNGUN', damagereason = 'Died' },
    weapon_stungun_mp = { name = 'weapon_stungun_mp', label = 'Taser', weapontype = 'Pistol', ammotype = 'AMMO_STUNGUN', damagereason = 'Died' },
    weapon_switchblade = { name = 'weapon_switchblade', label = 'Switchblade', weapontype = 'Melee', ammotype = nil, damagereason = 'Knifed / Stabbed / Eviscerated' },
    weapon_unarmed = { name = 'weapon_unarmed', label = 'Fists', weapontype = 'Melee', ammotype = nil, damagereason = 'Melee killed / Whacked / Executed / Beat down / Murdered / Battered' },
    weapon_vintagepistol = { name = 'weapon_vintagepistol', label = 'Vintage Pistol', weapontype = 'Pistol', ammotype = 'AMMO_PISTOL', damagereason = 'Pistoled / Blasted / Plugged / Bust a cap in' },
    weapon_wrench = { name = 'weapon_wrench', label = 'Wrench', weapontype = 'Melee', ammotype = nil, damagereason = 'Melee killed / Whacked / Executed / Beat down / Murdered / Battered' },
}
KoraCoreSeed.legacyDamageCauses = {
    'gadget_parachute',
    'weapon_animal',
    'weapon_barbed_wire',
    'weapon_bleeding',
    'weapon_cougar',
    'weapon_drowning',
    'weapon_drowning_in_vehicle',
    'weapon_electric_fence',
    'weapon_exhaustion',
    'weapon_explosion',
    'weapon_fall',
    'weapon_fire',
    'weapon_heli_crash',
    'weapon_hit_by_water_cannon',
    'weapon_rammed_by_car',
    'weapon_run_over_by_car',
}
