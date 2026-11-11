-- Fake resource config for the ox_items generator: touches globals the sandbox
-- does not provide and registers items at runtime via Config.items.
Config = {}
Config.debug = GetConvar('fake_debug', 'false') == 'true'
Config.title = locale('title') .. ' Cards'
Config.spawn = vec3(1.0, 2.0, 3.0)
Config.timeout = lib.settings.timeout * 2
lib.locale()

Config.items = {
    blank_film = { name = 'blank_film', label = 'Blank Film', weight = 50, type = 'item', image = 'blank_film.svg',
        imageUrl = 'https://example.invalid/blank_film.svg', unique = false, useable = true, shouldClose = true,
        description = 'Unexposed film.' },
    card_cam = { label = 'Card Camera', weight = 800, unique = true, useable = true, shouldClose = false, image = 'card_cam.png' },
    water = { label = 'Resource Water', weight = 1 },
    money = { label = 'Resource Money', weight = 1 },
    weapon_cardgun = { label = 'Card Gun', weight = 1, type = 'weapon' },
}

-- stubbed adopt() returns the stub, which must not discard Config
if Kora and Kora.config and Kora.config.adopt then Config = Kora.config.adopt(Config) end
