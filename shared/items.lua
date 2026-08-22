-- Seed item definitions. Plain data, no Core dependency -- loaded before the
-- registry module, which ingests QBCoreSeed.items at its own load time. A
-- server extends this list or registers items at runtime from other resources
-- (QB.shared.register('items', ...)). Shape matches legacy QBCore.Shared.Items.
QBCoreSeed = QBCoreSeed or {}

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
    }
end

QBCoreSeed.items = {
    { name = 'water_bottle', label = 'Water',    weight = 500,  type = 'item', image = 'water_bottle.png', unique = false, useable = true,  shouldClose = true,  description = 'Refreshing.' },
    { name = 'sandwich',     label = 'Sandwich', weight = 220,  type = 'item', image = 'sandwich.png',     unique = false, useable = true,  shouldClose = true,  description = 'Filling.' },
    { name = 'phone',        label = 'Phone',    weight = 190,  type = 'item', image = 'phone.png',        unique = true,  useable = true,  shouldClose = false, description = 'Smartphone.' },
    { name = 'id_card',      label = 'ID Card',  weight = 0,    type = 'item', image = 'id_card.png',      unique = true,  useable = true,  shouldClose = false, description = 'Identification.' },
    { name = 'lockpick',     label = 'Lockpick', weight = 160,  type = 'item', image = 'lockpick.png',     unique = false, useable = true,  shouldClose = true,  description = 'For locked things.' },
    { name = 'bread',        label = 'Bread',    weight = 120,  type = 'item', image = 'bread.png',        unique = false, useable = true,  shouldClose = true,  description = 'Bakery fresh.' },
    { name = 'cash',         label = 'Cash',     weight = 0,    type = 'item', image = 'cash.png',         unique = false, useable = false, shouldClose = true,  description = 'Physical money.' },

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
    { name = 'weaponlicense', label = 'Weapon Licence', weight = 0, type = 'item', image = 'weaponlicense.png', unique = true, useable = false, shouldClose = false, description = 'A valid weapon licence.' },
}
