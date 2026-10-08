-- Default item definitions. Plain data, no Core dependency -- loaded before
-- the server registry module, which registers every record through the runtime
-- mutation API. Other resources extend the same registry with
-- QB.shared.register('items', ...).
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
    -- Retain legacy names for existing inventories, shops and integrations.
    { name = 'water_bottle', label = 'Water',    weight = 500,  type = 'item', image = 'water_bottle.png', imageUrl = QBCoreSeed.imageUrl('water_bottle'), unique = false, useable = true,  shouldClose = true,  description = 'Refreshing.' },
    { name = 'sandwich',     label = 'Sandwich', weight = 220,  type = 'item', image = 'sandwich.png',     imageUrl = QBCoreSeed.imageUrl('sandwich'), unique = false, useable = true,  shouldClose = true,  description = 'Filling.' },
    { name = 'beer',          label = 'Beer',          weight = 350, type = 'item', image = 'beer.png',          imageUrl = QBCoreSeed.imageUrl('beer'),          unique = false, useable = true, shouldClose = true, description = 'An alcoholic drink.' },
    { name = 'whiskey',       label = 'Whiskey',       weight = 400, type = 'item', image = 'whiskey.png',       imageUrl = QBCoreSeed.imageUrl('whiskey'),       unique = false, useable = true, shouldClose = true, description = 'Strong stuff.' },
    { name = 'weed',          label = 'Weed',          weight = 20,  type = 'item', image = 'weed.png',          imageUrl = QBCoreSeed.imageUrl('weed'),          unique = false, useable = true, shouldClose = true, description = 'Best used off duty.' },
    { name = 'phone',        label = 'Phone',    weight = 190,  type = 'item', image = 'phone.png',        imageUrl = QBCoreSeed.imageUrl('phone'), unique = true,  useable = true,  shouldClose = false, description = 'Smartphone.' },
    { name = 'id_card',      label = 'ID Card',  weight = 0,    type = 'item', image = 'id_card.png',      imageUrl = QBCoreSeed.imageUrl('id_card'), unique = true,  useable = true,  shouldClose = false, description = 'Identification.' },
    { name = 'lockpick',     label = 'Lockpick', weight = 160,  type = 'item', image = 'lockpick.png',     imageUrl = QBCoreSeed.imageUrl('lockpick'), unique = false, useable = true,  shouldClose = true,  description = 'For locked things.' },
    { name = 'vehiclekey',   label = 'Vehicle Key', weight = 20, type = 'item', image = 'vehiclekey.png',   imageUrl = QBCoreSeed.imageUrl('vehiclekey'), unique = true, useable = true, shouldClose = false, description = 'A key assigned to a vehicle.' },
    { name = 'bread',        label = 'Bread',    weight = 120,  type = 'item', image = 'bread.png',        imageUrl = QBCoreSeed.imageUrl('bread'), unique = false, useable = true,  shouldClose = true,  description = 'Filling.' },

    -- Further consumables (food/drink/alcohol/drugs). Their actual hunger/
    -- thirst/stress/drunk/high effects live in qbinventory's own useable
    -- handler (server/useables.lua), not here -- this registry only carries
    -- display/weight/useable metadata, same as every other item.
    { name = 'chocolate_bar', label = 'Chocolate Bar', weight = 80,  type = 'item', image = 'chocolate_bar.png', imageUrl = QBCoreSeed.imageUrl('chocolate_bar'), unique = false, useable = true, shouldClose = true, description = 'A quick snack.' },
    { name = 'soda',          label = 'Soda',          weight = 350, type = 'item', image = 'soda.png',          imageUrl = QBCoreSeed.imageUrl('soda'),          unique = false, useable = true, shouldClose = true, description = 'Sweet and fizzy.' },

    -- A unique item because qbinventory binds one durable secondary inventory
    -- to each physical backpack. Its capacity/access policy lives in
    -- qbinventory's server-side container configuration.
    { name = 'backpack',     label = 'Backpack', weight = 1500, type = 'item', image = 'backpack.png',     imageUrl = QBCoreSeed.imageUrl('backpack'), unique = true,  useable = true,  shouldClose = false, container = true, description = 'A personal carry pack.' },
    { name = 'cash',         label = 'Cash',     weight = 0,    type = 'item', image = 'cash.png',         imageUrl = QBCoreSeed.imageUrl('cash'), unique = false, useable = false, shouldClose = true,  description = 'Physical money.' },

    -- Recycling plant rewards are a public civilian activity,
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

    -- Crafting components and finished workshop supplies. Recipes and access
    -- policy live in qbcrafting; these records only define inventory metadata.
    { name = 'wire_bundle',        label = 'Wire Bundle',        weight = 180,  type = 'item', image = 'wire_bundle.png',        imageUrl = QBCoreSeed.imageUrl('wire_bundle'),        unique = false, useable = false, shouldClose = true, description = 'Insulated copper wiring for electrical projects.' },
    { name = 'metal_bracket',      label = 'Metal Bracket',      weight = 350,  type = 'item', image = 'metal_bracket.png',      imageUrl = QBCoreSeed.imageUrl('metal_bracket'),      unique = false, useable = false, shouldClose = true, description = 'A reinforced bracket for mechanical assemblies.' },
    { name = 'electronics_kit',    label = 'Electronics Kit',    weight = 650,  type = 'item', image = 'electronics_kit.png',    imageUrl = QBCoreSeed.imageUrl('electronics_kit'),    unique = false, useable = false, shouldClose = true, description = 'Packaged wiring and components for electronic repairs.' },
    { name = 'vehicle_repair_kit', label = 'Vehicle Repair Kit', weight = 1800, type = 'item', image = 'vehicle_repair_kit.png', imageUrl = QBCoreSeed.imageUrl('vehicle_repair_kit'), unique = false, useable = false, shouldClose = true, description = 'Workshop supplies for repairing a damaged vehicle.' },

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
    ammo('emp_round', 'EMP round', 'AMMO_EMPLAUNCHER', 1000, 1),

    -- Optional licence record for servers that choose to gate weapon-shop
    -- access through a player item rather than a metadata/ACE policy.
    { name = 'weaponlicense', label = 'Weapon Licence', weight = 0, type = 'item', image = 'weaponlicense.png', imageUrl = QBCoreSeed.imageUrl('weaponlicense'), unique = true, useable = false, shouldClose = false, description = 'A valid weapon licence.' },

    -- QB Drugs
    { name = "baking_soda", label = "Baking soda", weight = 1000, type = "item", image = "baking_soda.png", unique = false, useable = false, shouldClose = true, description = "I can use this for cakes or maybe something else" },
    { name = "gram_bag", label = "Gram Bag", weight = 1, type = "item", image = "gram_bag.png", unique = false, useable = false, shouldClose = true, description = "A small bag containing a gram." },

    { name = "coca_leaf", label = "Coca leaf", weight = 1000, type = "item", image = "coca_leaf.png", unique = false, useable = false, shouldClose = true, description = "A plant that may give you a little rush when processed" },
    { name = "cocaine_baggy", label = "Cocaine baggy", weight = 1000, type = "item", image = "cocaine_baggy.png", unique = false, useable = false, shouldClose = true, description = "A 1g bag of cocaine" },
    { name = "coke_powder", label = "Coke powder", weight = 1000, type = "item", image = "coke_powder.png", unique = false, useable = false, shouldClose = true, description = "refined powder of the coca plant" },
    { name = "cut_coke", label = "Cut coke", weight = 1000, type = "item", image = "cut_coke.png", unique = false, useable = false, shouldClose = true, description = "cocaine ready to be bagged up" },

    { name = "crack_rock", label = "Crack Rock", weight = 1, type = "item", image = "crack_rock.png", unique = false, useable = false, shouldClose = true, description = "A small rock of crack." },
    { name = "crack_bag", label = "Bag of Crack", weight = 1, type = "item", image = "crack_bag.png", unique = false, useable = false, shouldClose = true, description = "A bag containing crack." },

    { name = "empty_vial", label = "Empty Vial", weight = 1, type = "item", image = "empty_vial.png", unique = false, useable = false, shouldClose = true, description = "An empty glass vial." },
    { name = "heroin_powder", label = "Heroin Powder", weight = 1, type = "item", image = "heroin_powder.png", unique = false, useable = false, shouldClose = true, description = "A small amount of heroin powder." },
    { name = "heroin_syringe", label = "Heroin Syringe", weight = 1, type = "item", image = "heroin_syringe.png", unique = false, useable = false, shouldClose = true, description = "A syringe containing heroin." },
    { name = "heroin_vial", label = "Heroin Vial", weight = 1, type = "item", image = "heroin_vial.png", unique = false, useable = false, shouldClose = true, description = "A vial containing heroin." },
    { name = "metal_spoon", label = "Metal Spoon", weight = 1, type = "item", image = "metal_spoon.png", unique = false, useable = false, shouldClose = true, description = "A small metal spoon." },
    { name = "poppy_resin", label = "Poppy Resin", weight = 1, type = "item", image = "poppy_resin.png", unique = false, useable = false, shouldClose = true, description = "Raw resin collected from poppies." },
    { name = "syringe", label = "Syringe", weight = 1, type = "item", image = "syringe.png", unique = false, useable = false, shouldClose = true, description = "A clean medical syringe." },

    { name = "ak47_1g", label = "AK47 1g", weight = 100, type = "item", image = "ak47_1g.png", unique = false, useable = false, shouldClose = true, description = "A sealed 1g bag of AK47 cannabis." },
    { name = "ak47_joint", label = "AK47 Joint", weight = 100, type = "item", image = "ak47_joint.png", unique = false, useable = true, shouldClose = true, description = "A hand-rolled joint containing AK47 cannabis." },
    { name = "ak47_weed", label = "AK47 Nug", weight = 100, type = "item", image = "ak47_weed.png", unique = false, useable = false, shouldClose = true, description = "A nug of dried AK47 cannabis." },
    { name = "amensia_weed", label = "Amensia Nug", weight = 100, type = "item", image = "amensia_weed.png", unique = false, useable = false, shouldClose = true, description = "A nug of dried Amensia cannabis." },
    { name = "amnesia_1g", label = "Amnesia 1g", weight = 100, type = "item", image = "amnesia_1g.png", unique = false, useable = false, shouldClose = true, description = "A sealed 1g bag of Amnesia cannabis." },
    { name = "amnesia_joint", label = "Amnesia Joint", weight = 100, type = "item", image = "amnesia_joint.png", unique = false, useable = true, shouldClose = true, description = "A hand-rolled joint containing Amnesia cannabis." },
    { name = "blue_dream_1g", label = "Blue Dream 1g", weight = 100, type = "item", image = "blue_dream_1g.png", unique = false, useable = false, shouldClose = true, description = "A sealed 1g bag of Blue Dream cannabis." },
    { name = "blue_dream_joint", label = "Blue Dream Joint", weight = 100, type = "item", image = "blue_dream_joint.png", unique = false, useable = true, shouldClose = true, description = "A hand-rolled joint containing Blue Dream cannabis." },
    { name = "blue_dream_weed", label = "Blue Dream Nug", weight = 100, type = "item", image = "blue_dream_weed.png", unique = false, useable = false, shouldClose = true, description = "A nug of dried Blue Dream cannabis." },
    { name = "dried_cola", label = "Dried Cola", weight = 100, type = "item", image = "dried_cola.png", unique = false, useable = false, shouldClose = true, description = "A dried cannabis cola ready for processing." },
    { name = "og_kush_1g", label = "OG Kush 1g", weight = 100, type = "item", image = "og_kush_1g.png", unique = false, useable = false, shouldClose = true, description = "A sealed 1g bag of OG Kush cannabis." },
    { name = "og_kush_joint", label = "OG Kush Joint", weight = 100, type = "item", image = "og_kush_joint.png", unique = false, useable = true, shouldClose = true, description = "A hand-rolled joint containing OG Kush cannabis." },
    { name = "og_kush_weed", label = "OG Kush Nug", weight = 100, type = "item", image = "og_kush_weed.png", unique = false, useable = false, shouldClose = true, description = "A nug of dried OG Kush cannabis." },
    { name = "purple_haze_1g", label = "Purple Haze 1g", weight = 100, type = "item", image = "purple_haze_1g.png", unique = false, useable = false, shouldClose = true, description = "A sealed 1g bag of Purple Haze cannabis." },
    { name = "purple_haze_joint", label = "Purple Haze Joint", weight = 100, type = "item", image = "purple_haze_joint.png", unique = false, useable = true, shouldClose = true, description = "A hand-rolled joint containing Purple Haze cannabis." },
    { name = "purple_haze_weed", label = "Purple Haze Nug", weight = 100, type = "item", image = "purple_haze_weed.png", unique = false, useable = false, shouldClose = true, description = "A nug of dried Purple Haze cannabis." },
    { name = "skunk_1g", label = "Skunk 1g", weight = 100, type = "item", image = "skunk_1g.png", unique = false, useable = false, shouldClose = true, description = "A sealed 1g bag of Skunk cannabis." },
    { name = "skunk_joint", label = "Skunk Joint", weight = 1000, type = "item", image = "skunk_joint.png", unique = false, useable = true, shouldClose = true, description = "A hand-rolled joint containing Skunk cannabis." },
    { name = "skunk_weed", label = "Skunk Nug", weight = 100, type = "item", image = "skunk_weed.png", unique = false, useable = false, shouldClose = true, description = "A nug of dried Skunk cannabis." },
    { name = "wet_cola", label = "Wet Cola", weight = 100, type = "item", image = "wet_cola.png", unique = false, useable = false, shouldClose = true, description = "A freshly harvested cannabis cola that has not been dried." },
    { name = "ephedrine", label = "Ephedrine", weight = 100, type = "item", image = "ephedrine.png", unique = false, useable = false, shouldClose = true, description = "Hmm toxic chemicals?" },
    { name = "acetone", label = "Acetone", weight = 100, type = "item", image = "acetone.png", unique = false, useable = false, shouldClose = true, description = "I use this to remove nail polish" },
    { name = 'shrooms',    label = 'Shrooms',    weight = 100,    type = 'item',    image = 'shrooms.png',    unique = false,    useable = true,    shouldClose = false,    description = ''},
    { name = 'cactus_bulb',    label = 'Cactus Bulb',    weight = 100,    type = 'item',    image = 'cactus_bulb.png',    unique = false,    useable = false,    shouldClose = false,    description = ''},
    { name = 'dried_mescaline',    label = 'Dried Mescaline',    weight = 100,    type = 'item',    image = 'dried_mescaline.png',    unique = false,    useable = true,    shouldClose = false,    description = ''},
    -- Fishing
     { name = 'bass',                label = 'Bass',                weight = 100, type = 'item', image = 'bass.png',                unique = false, useable = false, shouldClose = false, description = 'A feisty freshwater bass, hooked fresh from the water.' },
    { name = 'blue_fish',           label = 'Blue Fish',           weight = 100, type = 'item', image = 'blue_fish.png',           unique = false, useable = false, shouldClose = false, description = 'A slick, silvery bluefish with a sharp bite.' },
    { name = 'catfish',             label = 'Catfish',             weight = 100, type = 'item', image = 'catfish.png',             unique = false, useable = false, shouldClose = false, description = 'A whiskered bottom-feeder pulled up from the murky depths.' },
    { name = 'closed_safe',         label = 'Closed Safe',         weight = 100, type = 'item', image = 'closed_safe.png',         unique = false, useable = false, shouldClose = false, description = 'A heavy, rusted safe, still sealed shut. Who knows what is inside.' },
    { name = 'copper_pipe',         label = 'Copper Pipe',         weight = 100, type = 'item', image = 'copper_pipe.png',         unique = false, useable = false, shouldClose = false, description = 'A length of tarnished copper piping, worth a bit of scrap value.' },
    { name = 'fishing_pole',        label = 'Fishing Pole',        weight = 100, type = 'item', image = 'fishing_pole.png',        unique = false, useable = false, shouldClose = false, description = 'A sturdy pole for casting a line and reeling in a catch.' },
    { name = 'flounder',            label = 'Flounder',            weight = 100, type = 'item', image = 'flounder.png',            unique = false, useable = false, shouldClose = false, description = 'A flat-bodied fish plucked from the shallows.' },
    { name = 'halibut',             label = 'Halibut',             weight = 100, type = 'item', image = 'halibut.png',             unique = false, useable = false, shouldClose = false, description = 'A large, meaty flatfish prized by anglers.' },
    { name = 'magnet_2lb',          label = 'Magnet 2lb',          weight = 100, type = 'item', image = 'magnet_2lb.png',          unique = false, useable = false, shouldClose = false, description = 'A lightweight 2lb fishing magnet, only strong enough for small, light objects.' },
    { name = 'magnet_5lb',          label = 'Magnet 5lb',          weight = 100, type = 'item', image = 'magnet_5lb.png',          unique = false, useable = false, shouldClose = false, description = 'A 5lb fishing magnet with enough pull for mid-weight junk.' },
    { name = 'magnet_10lb',         label = 'Magnet 10lb',         weight = 100, type = 'item', image = 'magnet_10lb.png',         unique = false, useable = false, shouldClose = false, description = 'A 10lb fishing magnet, strong enough to drag up heavier items.' },
    { name = 'magnet_20lb',         label = 'Magnet 20lb',         weight = 100, type = 'item', image = 'magnet_20lb.png',         unique = false, useable = false, shouldClose = false, description = 'A powerful 20lb fishing magnet capable of hauling up the heaviest finds.' },
    { name = 'magnet_pole',         label = 'Magnet Pole',         weight = 100, type = 'item', image = 'fishing_pole.png',        unique = false, useable = false, shouldClose = false, description = 'A rugged pole rigged for magnet fishing, used to lower and retrieve a magnet.' },
    { name = 'plug_bait',           label = 'Plug Bait',           weight = 100, type = 'item', image = 'plug_bait.png',           unique = false, useable = false, shouldClose = false, description = 'A hard-bodied lure that mimics an injured baitfish.' },
    { name = 'reddrum',             label = 'Reddrum',             weight = 100, type = 'item', image = 'reddrum.png',             unique = false, useable = false, shouldClose = false, description = 'A coppery red drum fish, a solid catch for any angler.' },
    { name = 'rusty_ak',            label = 'Rusty Ak',            weight = 100, type = 'item', image = 'rusty_ak.png',            unique = false, useable = false, shouldClose = false, description = 'A corroded AK-pattern rifle, long since abandoned in the water.' },
    { name = 'rusty_antenna',       label = 'Rusty Antenna',       weight = 100, type = 'item', image = 'rusty_antenna.png',       unique = false, useable = false, shouldClose = false, description = 'A bent, rust-covered antenna pulled up on your magnet.' },
    { name = 'rusty_bike',          label = 'Rusty Bike',          weight = 100, type = 'item', image = 'rusty_bike.png',          unique = false, useable = false, shouldClose = false, description = 'An old bicycle frame, eaten away by rust after years underwater.' },
    { name = 'rusty_box',           label = 'Rusty Box',           weight = 100, type = 'item', image = 'rusty_box.png',           unique = false, useable = false, shouldClose = false, description = 'A dented metal box, rusted shut from years submerged.' },
    { name = 'rusty_chain',         label = 'Rusty Chain',         weight = 100, type = 'item', image = 'rusty_chain.png',         unique = false, useable = false, shouldClose = false, description = 'A length of heavy chain, caked in rust.' },
    { name = 'rusty_pistol',        label = 'Rusty Pistol',        weight = 100, type = 'item', image = 'rusty_pistol.png',        unique = false, useable = false, shouldClose = false, description = 'A corroded handgun, likely dumped to hide the evidence.' },
    { name = 'rusty_motherboard',   label = 'Rusty Motherboard',   weight = 100, type = 'item', image = 'rusty_motherboard.png',   unique = false, useable = false, shouldClose = false, description = 'A water-damaged circuit board, barely recognizable under the rust and grime.' },
    { name = 'rusty_scanner',       label = 'Rusty Scanner',       weight = 100, type = 'item', image = 'rusty_scanner.png',       unique = false, useable = false, shouldClose = false, description = 'An old barcode scanner, corroded from its time underwater.' },
    { name = 'rusty_scrap_metal',   label = 'Rusty Scrap Metal',   weight = 100, type = 'item', image = 'rusty_scrap_metal.png',   unique = false, useable = false, shouldClose = false, description = 'A twisted chunk of scrap metal, good for melting down.' },
    { name = 'rusty_shotgun',       label = 'Rusty Shotgun',       weight = 100, type = 'item', image = 'rusty_shotgun.png',       unique = false, useable = false, shouldClose = false, description = 'A rust-caked shotgun, its barrel clogged with silt.' },
    { name = 'rusty_sign',          label = 'Rusty Sign',          weight = 100, type = 'item', image = 'rusty_sign.png',          unique = false, useable = false, shouldClose = false, description = 'A faded, rusted street sign fished up from the bottom.' },
    { name = 'rusty_tire',          label = 'Rusty Tire',          weight = 100, type = 'item', image = 'rusty_tire.png',          unique = false, useable = false, shouldClose = false, description = 'An old tire with a rusted rim, dumped long ago.' },
    { name = 'rusty_usb',           label = 'Rusty Usb',           weight = 100, type = 'item', image = 'rusty_usb.png',           unique = false, useable = false, shouldClose = false, description = 'A tiny corroded USB drive, its contents long lost to water damage.' },
    { name = 'rusty_wheelchair',    label = 'Rusty Wheelchair',    weight = 100, type = 'item', image = 'rusty_wheelchair.png',    unique = false, useable = false, shouldClose = false, description = 'A rusted wheelchair frame, heavy and awkward to reel in.' },
    { name = 'salmon',              label = 'Salmon',              weight = 100, type = 'item', image = 'salmon.png',              unique = false, useable = false, shouldClose = false, description = 'A prized pink-fleshed salmon, fresh off the line.' },
    { name = 'soft_plastic_bait',   label = 'Soft Plastic Bait',   weight = 100, type = 'item', image = 'soft_plastic_bait.png',   unique = false, useable = false, shouldClose = false, description = 'A flexible plastic lure shaped to imitate live prey.' },
    { name = 'spinner_bait',        label = 'Spinner Bait',        weight = 100, type = 'item', image = 'spinner_bait.png',        unique = false, useable = false, shouldClose = false, description = 'A flashy lure with spinning blades that attract predatory fish.' },
    { name = 'steelhead',           label = 'Steelhead',           weight = 100, type = 'item', image = 'steelhead.png',           unique = false, useable = false, shouldClose = false, description = 'A muscular steelhead trout, a rewarding catch for any angler.' },
    { name = 'trout',               label = 'Trout',               weight = 100, type = 'item', image = 'trout.png',               unique = false, useable = false, shouldClose = false, description = 'A speckled trout, freshly reeled in.' },
    { name = 'tuna',                label = 'Tuna',                weight = 100, type = 'item', image = 'tuna.png',                unique = false, useable = false, shouldClose = false, description = 'A sizeable tuna, prized for its rich, meaty flesh.' },
    { name = 'white_bass',          label = 'White Bass',          weight = 100, type = 'item', image = 'white_bass.png',          unique = false, useable = false, shouldClose = false, description = 'A silvery white bass caught from open water.' },
    { name = 'worm',                label = 'Worm',                weight = 100, type = 'item', image = 'worm.png',                unique = false, useable = false, shouldClose = false, description = 'A wriggling worm, perfect for baiting a hook.' },

    --- Metal Detecting
    { name = 'antique_coin',    label = 'Antique Coin',    weight = 100,    type = 'item',    image = 'antique_coin.png',    unique = false,    useable = false,    shouldClose = false,    description = ''},
    { name = 'bobby_pin',    label = 'Bobby Pin',    weight = 100,    type = 'item',    image = 'bobby_pin.png',    unique = false,    useable = false,    shouldClose = false,    description = ''},
    { name = 'bottle_cap',    label = 'Bottle Cap',    weight = 100,    type = 'item',    image = 'bottle_cap.png',    unique = false,    useable = false,    shouldClose = false,    description = ''},
    { name = 'car_keys_md',    label = ' Found Car Keys',    weight = 100,    type = 'item',    image = 'car_keys_md.png',    unique = false,    useable = false,    shouldClose = false,    description = ''},
    { name = 'clump',    label = 'Clump',    weight = 100,    type = 'item',    image = 'clump.png',    unique = false,    useable = false,    shouldClose = false,    description = ''},
    { name = 'corno',    label = 'Corno',    weight = 100,    type = 'item',    image = 'corno.png',    unique = false,    useable = false,    shouldClose = false,    description = ''},
    { name = 'diamond_earring_md',    label = ' Found Diamond Earring',    weight = 100,    type = 'item',    image = 'diamond_earring_md.png',    unique = false,    useable = false,    shouldClose = false,    description = ''},
    { name = 'diamond_ring_md',    label = 'Found Diamond Ring',    weight = 100,    type = 'item',    image = 'diamond_ring_md.png',    unique = false,    useable = false,    shouldClose = false,    description = ''},
    { name = 'gold_bracelet_md',    label = ' Found Gold Bracelet',    weight = 100,    type = 'item',    image = 'gold_bracelet_md.png',    unique = false,    useable = false,    shouldClose = false,    description = ''},
    { name = 'gold_chain_md',    label = ' Found Gold Chain',    weight = 100,    type = 'item',    image = 'gold_chain_md.png',    unique = false,    useable = false,    shouldClose = false,    description = ''},
    { name = 'gold_diamond_ring_md',    label = ' Found Gold Diamond Ring',    weight = 100,    type = 'item',    image = 'gold_diamond_ring_md.png',    unique = false,    useable = false,    shouldClose = false,    description = ''},
    { name = 'gold_ring_md',    label = ' Found Gold Ring',    weight = 100,    type = 'item',    image = 'gold_ring_md.png',    unique = false,    useable = false,    shouldClose = false,    description = ''},
    { name = 'metaldetector',    label = 'Metal Detector',    weight = 100,    type = 'item',    image = 'metaldetector.png',    unique = false,    useable = false,    shouldClose = false,    description = ''},
    { name = 'nails',    label = 'Nails',    weight = 100,    type = 'item',    image = 'nails.png',    unique = false,    useable = false,    shouldClose = false,    description = ''},
    { name = 'ruby_ring_md',    label = 'Found Ruby Ring ',    weight = 100,    type = 'item',    image = 'ruby_ring_md.png',    unique = false,    useable = false,    shouldClose = false,    description = ''},
    { name = 'silver_ring_md',    label = ' Found Silver Ring',    weight = 100,    type = 'item',    image = 'silver_ring_md.png',    unique = false,    useable = false,    shouldClose = false,    description = ''},
    { name = 'toy_car',    label = 'Toy Car',    weight = 100,    type = 'item',    image = 'toy_car.png',    unique = false,    useable = false,    shouldClose = false,    description = ''},

   }
