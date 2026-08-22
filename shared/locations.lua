-- Seed world locations (spawn points, garages, shops). Plain coordinate data
-- other resources read via QB.shared.get('locations', key) or QBCore.Shared.
QBCoreSeed = QBCoreSeed or {}

QBCoreSeed.locations = {
    { key = 'spawn_legion',  label = 'Legion Square', x = 195.17, y = -933.77, z = 30.69, h = 144.0 },
    { key = 'spawn_pillbox', label = 'Pillbox Hill',  x = 307.7,  y = -595.5,  z = 43.28, h = 90.0 },
    { key = 'garage_legion', label = 'Legion Garage', x = 215.9,  y = -810.1,  z = 30.7,  h = 160.0 },
}
