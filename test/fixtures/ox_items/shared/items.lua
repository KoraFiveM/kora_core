-- Tiny fixture registry for the ox_items generator smoke test.
KoraCoreSeed = KoraCoreSeed or {}
KoraCoreSeed.ammoItems = { AMMO_PISTOL = 'pistol_ammo' }
KoraCoreSeed.items = {
    { name = 'water', label = 'Water', weight = 500, type = 'item', image = 'water.png', unique = false, useable = true, shouldClose = true, description = 'Refreshing.' },
    { name = 'phone', label = 'Phone', weight = 190, type = 'item', image = 'smartphone.png', unique = true, useable = true, shouldClose = false, description = '' },
    { name = 'cash', label = 'Cash', weight = 0, type = 'item', image = 'cash.png', unique = false, useable = false, shouldClose = true },
    { name = 'pistol_ammo', label = 'Pistol Magazine', weight = 180, type = 'item', ammoType = 'AMMO_PISTOL', unique = false },
    { name = 'weapon_pistol', label = 'Pistol', weight = 1100, type = 'weapon', unique = true },
}
