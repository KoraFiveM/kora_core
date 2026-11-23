KoraCoreSeed = KoraCoreSeed or {}

KoraCoreSeed.ammoItems = {
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

local function ammo(name, label, ammoType, weight, rounds, image)
    return {
        name = name,
        label = label,
        weight = weight,
        type = 'item',
        shouldClose = true,
        description = ('%d-round %s.'):format(rounds, label:lower()),
        ammoType = ammoType,
        rounds = rounds,
        image = image,
    }
end

local function item(name, label, weight, image, unique, useable, shouldClose, description, container)
    if shouldClose == nil then
        shouldClose = true
    end
    return {
        name = name,
        label = label,
        weight = weight,
        type = 'item',
        image = image,
        unique = unique or nil,
        useable = useable or nil,
        shouldClose = shouldClose,
        container = container,
        description = description or ''
    }
end

-- Legacy extension table. Put server-specific core definitions here or
-- edit the bundled catalogue in kora_inventory/data/.
KoraCoreSeed.items = {
}

-- Several plain Lua module tests load only this file, without the boot merge.
if not LoadResourceFile and #KoraCoreSeed.items == 0 then
    KoraCoreSeed.inventoryWeapons = {}
    for _, path in ipairs({ 'data/items.lua', 'data/weapons.lua', 'data/food.lua', 'data/dranks.lua' }) do
        local catalogue = loadfile('../kora_inventory/' .. path)
        if catalogue then
            for _, record in ipairs(catalogue()) do
                local target = record.type == 'weapon' and KoraCoreSeed.inventoryWeapons or KoraCoreSeed.items
                target[#target + 1] = record
            end
        end
    end
end
