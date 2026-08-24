-- Seed item definitions. Plain data, no Core dependency -- loaded before the
-- registry module, which ingests QBCoreSeed.items at its own load time. A
-- server extends this list or registers items at runtime from other resources
-- (QB.shared.register('items', ...)). Shape matches legacy QBCore.Shared.Items.
QBCoreSeed = QBCoreSeed or {}

-- Temporary remote artwork catalogue. `image` remains the legacy local-file
-- field; `imageUrl` is an optional, browser-ready source that UI resources can
-- use while this collection is hosted on GitHub. Only exact, reviewed paths
-- are listed so a missing community image falls back cleanly instead of making
-- a guessed remote request. Server owners can replace the base or set a direct
-- `imageUrl` on their own shared-item record.
QBCoreSeed.itemImageBaseUrl = QBCoreSeed.itemImageBaseUrl
    or 'https://raw.githubusercontent.com/aifazi/items-images/main/'
QBCoreSeed.itemImagePaths = {
    bread = "ingredients/bread.png",
    id_card = "license/id_card.png",
    lockpick = "tools/lockpicks/lockpick.png",
    mg_ammo = "weapons/ammo/mg_ammo.png",
    phone = "tech/phone/phone.png",
    pistol_ammo = "weapons/ammo/pistol_ammo.png",
    rifle_ammo = "weapons/ammo/rifle_ammo.png",
    sandwich = "food/cafe/sandwich.png",
    shotgun_ammo = "weapons/ammo/shotgun_ammo.png",
    smg_ammo = "weapons/ammo/smg_ammo.png",
    water_bottle = "drinks/softdrinks/water_bottle.png",
    weapon_advancedrifle = "weapons/weapon_advancedrifle.png",
    weapon_appistol = "weapons/pistol/weapon_appistol.png",
    weapon_assaultrifle = "weapons/ar/weapon_assaultrifle.png",
    weapon_assaultrifle_mk2 = "weapons/ar/weapon_assaultrifle_mk2.png",
    weapon_assaultshotgun = "weapons/shotgun/weapon_assaultshotgun.png",
    weapon_assaultsmg = "weapons/smg/weapon_assaultsmg.png",
    weapon_autoshotgun = "weapons/shotgun/weapon_autoshotgun.png",
    weapon_ball = "weapons/throwables/weapon_ball.png",
    weapon_bat = "weapons/meele/weapon_bat.png",
    weapon_battleaxe = "weapons/meele/weapon_battleaxe.png",
    weapon_bottle = "weapons/meele/weapon_bottle.png",
    weapon_bullpuprifle = "weapons/weapon_bullpuprifle.png",
    weapon_bullpuprifle_mk2 = "weapons/weapon_bullpuprifle_mk2.png",
    weapon_bullpupshotgun = "weapons/shotgun/weapon_bullpupshotgun.png",
    weapon_carbinerifle = "weapons/weapon_carbinerifle.png",
    weapon_carbinerifle_mk2 = "weapons/weapon_carbinerifle_mk2.png",
    weapon_ceramicpistol = "weapons/pistol/weapon_ceramicpistol.png",
    weapon_combatmg = "weapons/weapon_combatmg.png",
    weapon_combatmg_mk2 = "weapons/weapon_combatmg_mk2.png",
    weapon_combatpdw = "weapons/weapon_combatpdw.png",
    weapon_combatpistol = "weapons/pistol/weapon_combatpistol.png",
    weapon_compactlauncher = "weapons/launcher/weapon_compactlauncher.png",
    weapon_compactrifle = "weapons/weapon_compactrifle.png",
    weapon_crowbar = "weapons/meele/weapon_crowbar.png",
    weapon_dagger = "weapons/meele/weapon_dagger.png",
    weapon_dbshotgun = "weapons/shotgun/weapon_dbshotgun.png",
    weapon_doubleaction = "weapons/pistol/weapon_doubleaction.png",
    weapon_fireextinguisher = "weapons/meele/weapon_fireextinguisher.png",
    weapon_firework = "weapons/launcher/weapon_firework.png",
    weapon_flare = "weapons/throwables/weapon_flare.png",
    weapon_flaregun = "weapons/pistol/weapon_flaregun.png",
    weapon_flashlight = "weapons/meele/weapon_flashlight.png",
    weapon_golfclub = "weapons/meele/weapon_golfclub.png",
    weapon_grenade = "weapons/throwables/weapon_grenade.png",
    weapon_grenadelauncher = "weapons/launcher/weapon_grenadelauncher.png",
    weapon_gusenberg = "weapons/weapon_gusenberg.png",
    weapon_hammer = "weapons/meele/weapon_hammer.png",
    weapon_hatchet = "weapons/meele/weapon_hatchet.png",
    weapon_hazardcan = "weapons/weapon_hazardcan.png",
    weapon_heavypistol = "weapons/pistol/weapon_heavypistol.png",
    weapon_heavyshotgun = "weapons/weapon_heavyshotgun.png",
    weapon_heavysniper = "weapons/sniper/weapon_heavysniper.png",
    weapon_heavysniper_mk2 = "weapons/sniper/weapon_heavysniper_mk2.png",
    weapon_hominglauncher = "weapons/launcher/weapon_hominglauncher.png",
    weapon_knife = "weapons/meele/weapon_knife.png",
    weapon_knuckle = "weapons/meele/weapon_knuckle.png",
    weapon_machete = "weapons/meele/weapon_machete.png",
    weapon_machinepistol = "weapons/pistol/weapon_machinepistol.png",
    weapon_marksmanpistol = "weapons/pistol/weapon_marksmanpistol.png",
    weapon_marksmanrifle = "weapons/weapon_marksmanrifle.png",
    weapon_marksmanrifle_mk2 = "weapons/weapon_marksmanrifle_mk2.png",
    weapon_mg = "weapons/weapon_mg.png",
    weapon_microsmg = "weapons/weapon_microsmg.png",
    weapon_minigun = "weapons/weapon_minigun.png",
    weapon_minismg = "weapons/weapon_minismg.png",
    weapon_molotov = "weapons/throwables/weapon_molotov.png",
    weapon_musket = "weapons/weapon_musket.png",
    weapon_navyrevolver = "weapons/pistol/weapon_navyrevolver.png",
    weapon_nightstick = "weapons/meele/weapon_nightstick.png",
    weapon_petrolcan = "weapons/weapon_petrolcan.png",
    weapon_pipebomb = "weapons/throwables/weapon_pipebomb.png",
    weapon_pistol = "weapons/pistol/weapon_pistol.png",
    weapon_pistol50 = "weapons/pistol/weapon_pistol50.png",
    weapon_pistol_mk2 = "weapons/pistol/weapon_pistol_mk2.png",
    weapon_poolcue = "weapons/meele/weapon_poolcue.png",
    weapon_proxmine = "weapons/throwables/weapon_proxmine.png",
    weapon_pumpshotgun = "weapons/shotgun/weapon_pumpshotgun.png",
    weapon_pumpshotgun_mk2 = "weapons/shotgun/weapon_pumpshotgun_mk2.png",
    weapon_railgun = "weapons/weapon_railgun.png",
    weapon_raycarbine = "weapons/weapon_raycarbine.png",
    weapon_rayminigun = "weapons/weapon_rayminigun.png",
    weapon_raypistol = "weapons/pistol/weapon_raypistol.png",
    weapon_revolver = "weapons/pistol/weapon_revolver.png",
    weapon_revolver_mk2 = "weapons/pistol/weapon_revolver_mk2.png",
    weapon_rpg = "weapons/launcher/weapon_rpg.png",
    weapon_sawnoffshotgun = "weapons/shotgun/weapon_sawnoffshotgun.png",
    weapon_smg = "weapons/weapon_smg.png",
    weapon_smg_mk2 = "weapons/weapon_smg_mk2.png",
    weapon_sniperrifle = "weapons/sniper/weapon_sniperrifle.png",
    weapon_snowball = "weapons/throwables/weapon_snowball.png",
    weapon_snspistol = "weapons/pistol/weapon_snspistol.png",
    weapon_snspistol_mk2 = "weapons/pistol/weapon_snspistol_mk2.png",
    weapon_specialcarbine = "weapons/weapon_specialcarbine.png",
    weapon_specialcarbine_mk2 = "weapons/weapon_specialcarbine_mk2.png",
    weapon_stickybomb = "weapons/throwables/weapon_stickybomb.png",
    weapon_stone_hatchet = "weapons/meele/weapon_stone_hatchet.png",
    weapon_switchblade = "weapons/meele/weapon_switchblade.png",
    weapon_vintagepistol = "weapons/pistol/weapon_vintagepistol.png",
    weapon_wrench = "weapons/meele/weapon_wrench.png",
    weaponlicense = "license/weaponlicense.png",
}

function QBCoreSeed.imageUrl(name)
    local path = QBCoreSeed.itemImagePaths[name]
    return path and (QBCoreSeed.itemImageBaseUrl .. path) or nil
end

-- Native ammo type -> qbinventory item id. The six magazine records use the
-- long-standing QB names (`snp_ammo` is deliberately retained for backwards
-- compatibility). Specialised ammunition is included as stockable data too,
-- but shops decide what to sell; defining it here does not make it available.
QBCoreSeed.ammoItems = {
    AMMO_PISTOL = 'pistol_ammo',
    AMMO_SMG = 'smg_ammo',
    AMMO_SHOTGUN = 'shotgun_ammo',
    AMMO_RIFLE = 'rifle_ammo',
    AMMO_MG = 'mg_ammo',
    AMMO_SNIPER = 'snp_ammo',
    AMMO_STUNGUN = 'taser_cartridge',
    AMMO_FLARE = 'flare_ammo',
    AMMO_MUSKET = 'musket_ammo',
    AMMO_RPG = 'rpg_ammo',
    AMMO_GRENADELAUNCHER = 'grenade_launcher_ammo',
    AMMO_GRENADELAUNCHER_SMOKE = 'smoke_grenade_ammo',
    AMMO_MINIGUN = 'minigun_ammo',
    AMMO_FIREWORK = 'firework_ammo',
    AMMO_RAILGUN = 'railgun_ammo',
    AMMO_HOMINGLAUNCHER = 'homing_missile',
    AMMO_EMPLAUNCHER = 'emp_round',
}

local function ammo(name, label, ammoType, weight, rounds)
    return {
        name = name,
        label = label,
        weight = weight,
        type = 'item',
        unique = false,
        useable = false,
        shouldClose = true,
        description = ('%d-round %s.'):format(rounds, label:lower()),
        ammoType = ammoType,
        rounds = rounds,
        image = name .. '.png',
        imageUrl = QBCoreSeed.imageUrl(name),
    }
end

QBCoreSeed.items = {
    { name = 'water_bottle', label = 'Water',    weight = 500,  type = 'item', image = 'water_bottle.png', imageUrl = QBCoreSeed.imageUrl('water_bottle'), unique = false, useable = true,  shouldClose = true,  description = 'Refreshing.' },
    { name = 'sandwich',     label = 'Sandwich', weight = 220,  type = 'item', image = 'sandwich.png',     imageUrl = QBCoreSeed.imageUrl('sandwich'), unique = false, useable = true,  shouldClose = true,  description = 'Filling.' },
    { name = 'phone',        label = 'Phone',    weight = 190,  type = 'item', image = 'phone.png',        imageUrl = QBCoreSeed.imageUrl('phone'), unique = true,  useable = true,  shouldClose = false, description = 'Smartphone.' },
    { name = 'id_card',      label = 'ID Card',  weight = 0,    type = 'item', image = 'id_card.png',      imageUrl = QBCoreSeed.imageUrl('id_card'), unique = true,  useable = true,  shouldClose = false, description = 'Identification.' },
    { name = 'lockpick',     label = 'Lockpick', weight = 160,  type = 'item', image = 'lockpick.png',     imageUrl = QBCoreSeed.imageUrl('lockpick'), unique = false, useable = true,  shouldClose = true,  description = 'For locked things.' },
    { name = 'bread',        label = 'Bread',    weight = 120,  type = 'item', image = 'bread.png',        imageUrl = QBCoreSeed.imageUrl('bread'), unique = false, useable = true,  shouldClose = true,  description = 'Filling.' },

    -- Further consumables (food/drink/alcohol/drugs). Their actual hunger/
    -- thirst/stress/drunk/high effects live in qbinventory's own useable
    -- handler (server/useables.lua), not here -- this registry only carries
    -- display/weight/useable metadata, same as every other item.
    { name = 'chocolate_bar', label = 'Chocolate Bar', weight = 80,  type = 'item', image = 'chocolate_bar.png', imageUrl = QBCoreSeed.imageUrl('chocolate_bar'), unique = false, useable = true, shouldClose = true, description = 'A quick snack.' },
    { name = 'soda',          label = 'Soda',          weight = 350, type = 'item', image = 'soda.png',          imageUrl = QBCoreSeed.imageUrl('soda'),          unique = false, useable = true, shouldClose = true, description = 'Sweet and fizzy.' },
    { name = 'beer',          label = 'Beer',          weight = 350, type = 'item', image = 'beer.png',          imageUrl = QBCoreSeed.imageUrl('beer'),          unique = false, useable = true, shouldClose = true, description = 'An alcoholic drink.' },
    { name = 'whiskey',       label = 'Whiskey',       weight = 400, type = 'item', image = 'whiskey.png',       imageUrl = QBCoreSeed.imageUrl('whiskey'),       unique = false, useable = true, shouldClose = true, description = 'Strong stuff.' },
    { name = 'weed',          label = 'Weed',          weight = 20,  type = 'item', image = 'weed.png',          imageUrl = QBCoreSeed.imageUrl('weed'),          unique = false, useable = true, shouldClose = true, description = 'Best used off duty.' },

    -- A unique item because qbinventory binds one durable secondary inventory
    -- to each physical backpack. Its capacity/access policy lives in
    -- qbinventory's server-side container configuration.
    { name = 'backpack',     label = 'Backpack', weight = 1500, type = 'item', image = 'backpack.png',     imageUrl = QBCoreSeed.imageUrl('backpack'), unique = true,  useable = true,  shouldClose = false, container = true, description = 'A personal carry pack.' },
    { name = 'cash',         label = 'Cash',     weight = 0,    type = 'item', image = 'cash.png',         imageUrl = QBCoreSeed.imageUrl('cash'), unique = false, useable = false, shouldClose = true,  description = 'Physical money.' },

    -- Recycling plant rewards. qb-recyclejob is a public civilian activity,
    -- but its server-side payout still travels through qbcore's shared item
    -- registry and qbinventory's authoritative add/remove path. Keeping these
    -- here means a completed package can be received, displayed, and sold
    -- instead of failing as an unknown item.
    { name = 'metalscrap', label = 'Metal Scrap', weight = 100, type = 'item', image = 'metalscrap.png', imageUrl = QBCoreSeed.imageUrl('metalscrap'), unique = false, useable = false, shouldClose = true, description = 'Salvaged mixed metal.' },
    { name = 'plastic',    label = 'Plastic',     weight = 100, type = 'item', image = 'plastic.png',    imageUrl = QBCoreSeed.imageUrl('plastic'),    unique = false, useable = false, shouldClose = true, description = 'Sorted recyclable plastic.' },
    { name = 'copper',     label = 'Copper',      weight = 100, type = 'item', image = 'copper.png',     imageUrl = QBCoreSeed.imageUrl('copper'),     unique = false, useable = false, shouldClose = true, description = 'Recovered copper.' },
    { name = 'rubber',     label = 'Rubber',      weight = 100, type = 'item', image = 'rubber.png',     imageUrl = QBCoreSeed.imageUrl('rubber'),     unique = false, useable = false, shouldClose = true, description = 'Reclaimed rubber.' },
    { name = 'iron',       label = 'Iron',        weight = 100, type = 'item', image = 'iron.png',       imageUrl = QBCoreSeed.imageUrl('iron'),       unique = false, useable = false, shouldClose = true, description = 'Recovered iron.' },
    { name = 'aluminum',   label = 'Aluminum',    weight = 100, type = 'item', image = 'aluminum.png',   imageUrl = QBCoreSeed.imageUrl('aluminum'),   unique = false, useable = false, shouldClose = true, description = 'Recovered aluminum.' },
    { name = 'steel',      label = 'Steel',       weight = 100, type = 'item', image = 'steel.png',      imageUrl = QBCoreSeed.imageUrl('steel'),      unique = false, useable = false, shouldClose = true, description = 'Recovered steel.' },
    { name = 'glass',      label = 'Glass',       weight = 100, type = 'item', image = 'glass.png',      imageUrl = QBCoreSeed.imageUrl('glass'),      unique = false, useable = false, shouldClose = true, description = 'Sorted glass.' },
    { name = 'cryptostick', label = 'Crypto Stick', weight = 20, type = 'item', image = 'cryptostick.png', imageUrl = QBCoreSeed.imageUrl('cryptostick'), unique = false, useable = false, shouldClose = true, description = 'A lucky recycling find.' },

    -- Standard Ammu-Nation ammunition. These are ordinary stackable inventory
    -- items, allowing shops and a future weapon system to move them through the
    -- same authoritative qbinventory transfer path as every other item.
    ammo('pistol_ammo', 'Pistol Magazine', 'AMMO_PISTOL', 180, 12),
    ammo('smg_ammo', 'SMG Magazine', 'AMMO_SMG', 300, 30),
    ammo('shotgun_ammo', 'Shotgun Shell Box', 'AMMO_SHOTGUN', 360, 12),
    ammo('rifle_ammo', 'Rifle Magazine', 'AMMO_RIFLE', 360, 30),
    ammo('mg_ammo', 'MG Belt', 'AMMO_MG', 900, 100),
    ammo('snp_ammo', 'Sniper Cartridge Box', 'AMMO_SNIPER', 420, 10),

    -- Specialised native ammunition. They are registered for valid future
    -- stock/loot recipes but are not implicitly offered by any shop.
    ammo('taser_cartridge', 'Taser Cartridge', 'AMMO_STUNGUN', 80, 1),
    ammo('flare_ammo', 'Flare Cartridge', 'AMMO_FLARE', 120, 1),
    ammo('musket_ammo', 'Musket Ball', 'AMMO_MUSKET', 70, 1),
    ammo('rpg_ammo', 'Rocket', 'AMMO_RPG', 2200, 1),
    ammo('grenade_launcher_ammo', '40mm Grenade', 'AMMO_GRENADELAUNCHER', 600, 1),
    ammo('smoke_grenade_ammo', '40mm Smoke Grenade', 'AMMO_GRENADELAUNCHER_SMOKE', 450, 1),
    ammo('minigun_ammo', 'Minigun Belt', 'AMMO_MINIGUN', 1800, 100),
    ammo('firework_ammo', 'Firework Rocket', 'AMMO_FIREWORK', 500, 1),
    ammo('railgun_ammo', 'Railgun Charge', 'AMMO_RAILGUN', 750, 1),
    ammo('homing_missile', 'Homing Missile', 'AMMO_HOMINGLAUNCHER', 2400, 1),
    ammo('emp_round', 'EMP Round', 'AMMO_EMPLAUNCHER', 1000, 1),

    -- Optional licence record for servers that choose to gate weapon-shop
    -- access through a player item rather than a metadata/ACE policy.
    { name = 'weaponlicense', label = 'Weapon Licence', weight = 0, type = 'item', image = 'weaponlicense.png', imageUrl = QBCoreSeed.imageUrl('weaponlicense'), unique = true, useable = false, shouldClose = false, description = 'A valid weapon licence.' },
}
