-- Seed weapon definitions (hash name -> label/ammo). Shape matches legacy
-- QBCore.Shared.Weapons, keyed by the lowercase weapon hash name.
QBCoreSeed = QBCoreSeed or {}

QBCoreSeed.weapons = {
    { name = 'weapon_pistol',      label = 'Pistol',       ammotype = 'AMMO_PISTOL', weight = 1000, type = 'weapon' },
    { name = 'weapon_knife',       label = 'Knife',        ammotype = nil,           weight = 500,  type = 'weapon' },
    { name = 'weapon_bat',         label = 'Bat',          ammotype = nil,           weight = 1200, type = 'weapon' },
    { name = 'weapon_carbinerifle',label = 'Carbine Rifle',ammotype = 'AMMO_RIFLE',  weight = 3000, type = 'weapon' },
}
