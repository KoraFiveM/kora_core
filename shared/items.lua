-- Seed item definitions. Plain data, no Core dependency -- loaded before the
-- registry module, which ingests QBCoreSeed.items at its own load time. A
-- server extends this list or registers items at runtime from other resources
-- (QB.shared.register('items', ...)). Shape matches legacy QBCore.Shared.Items.
QBCoreSeed = QBCoreSeed or {}

QBCoreSeed.items = {
    { name = 'water_bottle', label = 'Water',    weight = 500,  type = 'item', image = 'water_bottle.png', unique = false, useable = true,  shouldClose = true,  description = 'Refreshing.' },
    { name = 'sandwich',     label = 'Sandwich', weight = 220,  type = 'item', image = 'sandwich.png',     unique = false, useable = true,  shouldClose = true,  description = 'Filling.' },
    { name = 'phone',        label = 'Phone',    weight = 190,  type = 'item', image = 'phone.png',        unique = true,  useable = true,  shouldClose = false, description = 'Smartphone.' },
    { name = 'id_card',      label = 'ID Card',  weight = 0,    type = 'item', image = 'id_card.png',      unique = true,  useable = true,  shouldClose = false, description = 'Identification.' },
    { name = 'lockpick',     label = 'Lockpick', weight = 160,  type = 'item', image = 'lockpick.png',     unique = false, useable = true,  shouldClose = true,  description = 'For locked things.' },
    { name = 'bread',        label = 'Bread',    weight = 120,  type = 'item', image = 'bread.png',        unique = false, useable = true,  shouldClose = true,  description = 'Bakery fresh.' },
    { name = 'cash',         label = 'Cash',     weight = 0,    type = 'item', image = 'cash.png',         unique = false, useable = false, shouldClose = true,  description = 'Physical money.' },
}
