-- Seed vehicle definitions (spawn model + display + class + price). Shape aligns
-- with legacy QBCore.Shared.Vehicles entries (keyed by `model`/spawn name).
QBCoreSeed = QBCoreSeed or {}

QBCoreSeed.vehicles = {
    { model = 'sultan',   name = 'Sultan',   brand = 'Karin',    price = 12000, category = 'sedans',  shop = 'pdm' },
    { model = 'blista',   name = 'Blista',   brand = 'Dinka',    price = 8000,  category = 'compacts',shop = 'pdm' },
    { model = 'kuruma',   name = 'Kuruma',   brand = 'Karin',    price = 95000, category = 'sports',  shop = 'pdm' },
    { model = 'police',   name = 'Cruiser',  brand = 'Vapid',    price = 0,     category = 'emergency', shop = 'pdm' },
    { model = 'ambulance',name = 'Ambulance',brand = 'Brute',    price = 0,     category = 'emergency', shop = 'pdm' },
}
