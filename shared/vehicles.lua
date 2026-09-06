-- Default vehicle definitions (spawn model + display + class + price). The
-- server registry registers them at runtime, keyed by `model`/spawn name.
QBCoreSeed = QBCoreSeed or {}

QBCoreSeed.vehicles = {
    { model = 'sultan',   name = 'Sultan',   brand = 'Karin',    price = 12000, category = 'sedans',  shop = 'pdm' },
    { model = 'blista',   name = 'Blista',   brand = 'Dinka',    price = 8000,  category = 'compacts',shop = 'pdm' },
    { model = 'kuruma',   name = 'Kuruma',   brand = 'Karin',    price = 95000, category = 'sports',  shop = 'pdm' },
    { model = 'police',   name = 'Cruiser',  brand = 'Vapid',    price = 0,     category = 'emergency', shop = 'pdm' },
    { model = 'ambulance',name = 'Ambulance',brand = 'Brute',    price = 0,     category = 'emergency', shop = 'pdm' },
}

-- Broad, vanilla quick-pick catalogue for qbadmin. This is deliberately only
-- a convenience list, not an allow-list: qbadmin also accepts any native GTA
-- or streamed addon vehicle model that passes its server-side model check.
-- Keep the compact seed records above as the canonical priced shop examples;
-- these entries exist so an admin does not need to remember every common
-- spawn code just to browse the menu.
local function addCatalogueVehicles(category, vehicles)
    for _, vehicle in ipairs(vehicles) do
        QBCoreSeed.vehicles[#QBCoreSeed.vehicles + 1] = {
            model = vehicle[1], name = vehicle[2], brand = vehicle[3] or 'GTA',
            price = 0, category = category, shop = 'admin',
        }
    end
end

addCatalogueVehicles('compacts', {
    { 'asbo', 'Asbo', 'Maxwell' }, { 'brioso', 'Brioso', 'Grotti' }, { 'brioso2', 'Brioso 300', 'Grotti' },
    { 'club', 'Club', 'BF' }, { 'dilettante', 'Dilettante', 'Karin' }, { 'issi2', 'Issi', 'Weeny' },
    { 'panto', 'Panto', 'Benefactor' }, { 'prairie', 'Prairie', 'Bollokan' }, { 'rhapsody', 'Rhapsody', 'Declasse' },
    { 'weevil', 'Weevil', 'BF' },
})

addCatalogueVehicles('sedans', {
    { 'asea', 'Asea', 'Declasse' }, { 'asterope', 'Asterope', 'Karin' }, { 'cognoscenti', 'Cognoscenti', 'Enus' },
    { 'deity', 'Deity', 'Enus' }, { 'emperor', 'Emperor', 'Albany' }, { 'fugitive', 'Fugitive', 'Cheval' },
    { 'glendale', 'Glendale', 'Benefactor' }, { 'ingot', 'Ingot', 'Vulcar' }, { 'intruder', 'Intruder', 'Karin' },
    { 'premier', 'Premier', 'Declasse' }, { 'primo', 'Primo', 'Albany' }, { 'regina', 'Regina', 'Dundreary' },
    { 'schafter2', 'Schafter', 'Benefactor' }, { 'stanier', 'Stanier', 'Vapid' }, { 'stratum', 'Stratum', 'Zirconium' },
    { 'superd', 'Super Diamond', 'Enus' }, { 'surge', 'Surge', 'Cheval' }, { 'tailgater', 'Tailgater', 'Obey' },
    { 'warrener', 'Warrener', 'Vulcar' }, { 'washington', 'Washington', 'Albany' },
})

addCatalogueVehicles('coupes', {
    { 'cogcabrio', 'Cognoscenti Cabrio', 'Enus' }, { 'exemplar', 'Exemplar', 'Dewbauchee' },
    { 'f620', 'F620', 'Ocelot' }, { 'felon', 'Felon', 'Lampadati' }, { 'felon2', 'Felon GT', 'Lampadati' },
    { 'jackal', 'Jackal', 'Ocelot' }, { 'oracle2', 'Oracle XS', 'Ubermacht' }, { 'sentinel2', 'Sentinel XS', 'Ubermacht' },
    { 'windsor', 'Windsor', 'Enus' }, { 'zion', 'Zion', 'Ubermacht' },
})

addCatalogueVehicles('sports', {
    { 'alpha', 'Alpha', 'Albany' }, { 'banshee', 'Banshee', 'Bravado' }, { 'bestia', 'Bestia GTS', 'Grotti' },
    { 'buffalo', 'Buffalo', 'Bravado' }, { 'calico', 'Calico GTF', 'Karin' }, { 'carbonizzare', 'Carbonizzare', 'Grotti' },
    { 'comet2', 'Comet', 'Pfister' }, { 'coquette', 'Coquette', 'Invetero' }, { 'elegy', 'Elegy Retro', 'Annis' },
    { 'euros', 'Euros', 'Annis' }, { 'feltzer2', 'Feltzer', 'Benefactor' }, { 'futo', 'Futo', 'Karin' },
    { 'growler', 'Growler', 'Pfister' }, { 'jester', 'Jester', 'Dinka' }, { 'jugular', 'Jugular', 'Ocelot' },
    { 'locust', 'Locust', 'Ocelot' }, { 'lynx', 'Lynx', 'Ocelot' }, { 'massacro', 'Massacro', 'Dewbauchee' },
    { 'neo', 'Neo', 'Vysser' }, { 'pariah', 'Pariah', 'Ocelot' }, { 'penumbra', 'Penumbra', 'Maibatsu' },
    { 'raiden', 'Raiden', 'Coil' }, { 'remus', 'Remus', 'Annis' }, { 'schlagen', 'Schlagen GT', 'Benefactor' },
    { 'schwartzer', 'Schwartzer', 'Benefactor' }, { 'specter', 'Specter', 'Dewbauchee' }, { 'surano', 'Surano', 'Benefactor' },
    { 'tenf', '10F', 'Obey' }, { 'vectre', 'Vectre', 'Emperor' },
})

addCatalogueVehicles('super', {
    { 'adder', 'Adder', 'Truffade' }, { 'autarch', 'Autarch', 'Ocelot' }, { 'bullet', 'Bullet', 'Vapid' },
    { 'cheetah', 'Cheetah', 'Grotti' }, { 'cyclone', 'Cyclone', 'Coil' }, { 'deveste', 'Deveste Eight', 'Principe' },
    { 'emerus', 'Emerus', 'Progen' }, { 'entity2', 'Entity XXR', 'Overflod' }, { 'entityxf', 'Entity XF', 'Overflod' },
    { 'fmj', 'FMJ', 'Vapid' }, { 'furia', 'Furia', 'Grotti' }, { 'gp1', 'GP1', 'Progen' },
    { 'ignus', 'Ignus', 'Pegassi' }, { 'infernus', 'Infernus', 'Pegassi' }, { 'italirsx', 'Itali RSX', 'Grotti' },
    { 'krieger', 'Krieger', 'Benefactor' }, { 'lm87', 'LM87', 'Benefactor' }, { 'nero', 'Nero', 'Truffade' },
    { 'osiris', 'Osiris', 'Pegassi' }, { 'pfister811', '811', 'Pfister' }, { 'reaper', 'Reaper', 'Pegassi' },
    { 's80', 'S80RR', 'Annis' }, { 'sc1', 'SC1', 'Ubermacht' }, { 'sheava', 'ETR1', 'Emperor' },
    { 't20', 'T20', 'Progen' }, { 'taipan', 'Taipan', 'Cheval' }, { 'tezeract', 'Tezeract', 'Pegassi' },
    { 'thrax', 'Thrax', 'Truffade' }, { 'tigon', 'Tigon', 'Lampadati' }, { 'turismor', 'Turismo R', 'Grotti' },
    { 'tyrant', 'Tyrant', 'Overflod' }, { 'vacca', 'Vacca', 'Pegassi' }, { 'vagner', 'Vagner', 'Dewbauchee' },
    { 'visione', 'Visione', 'Grotti' }, { 'voltic', 'Voltic', 'Coil' }, { 'xa21', 'XA-21', 'Ocelot' },
    { 'zentorno', 'Zentorno', 'Pegassi' }, { 'zorrusso', 'Zorrusso', 'Pegassi' },
})

addCatalogueVehicles('muscle', {
    { 'blade', 'Blade', 'Vapid' }, { 'buccaneer', 'Buccaneer', 'Albany' }, { 'dominator', 'Dominator', 'Vapid' },
    { 'dukes', 'Dukes', 'Imponte' }, { 'ellie', 'Ellie', 'Vapid' }, { 'gauntlet', 'Gauntlet', 'Bravado' },
    { 'greenwood', 'Greenwood', 'Bravado' }, { 'hermes', 'Hermes', 'Albany' }, { 'hotknife', 'Hotknife', 'Vapid' },
    { 'impaler', 'Impaler', 'Declasse' }, { 'nightshade', 'Nightshade', 'Imponte' }, { 'phoenix', 'Phoenix', 'Imponte' },
    { 'ruiner', 'Ruiner', 'Imponte' }, { 'sabregt', 'Sabre Turbo', 'Declasse' }, { 'slamvan', 'Slamvan', 'Vapid' },
    { 'stalion', 'Stallion', 'Declasse' }, { 'tampa', 'Tampa', 'Declasse' }, { 'tulip', 'Tulip', 'Declasse' },
    { 'vigero', 'Vigero', 'Declasse' }, { 'virgo', 'Virgo', 'Albany' }, { 'yosemite', 'Yosemite', 'Declasse' },
})

addCatalogueVehicles('offroad', {
    { 'bfinjection', 'BF Injection', 'BF' }, { 'bifta', 'Bifta', 'BF' }, { 'blazer', 'Blazer', 'Nagasaki' },
    { 'bodhi2', 'Bodhi', 'Canis' }, { 'caracara2', 'Caracara 4x4', 'Vapid' }, { 'dubsta3', 'Dubsta 6x6', 'Benefactor' },
    { 'dune', 'Dune Buggy', 'BF' }, { 'everon', 'Everon', 'Karin' }, { 'freecrawler', 'Freecrawler', 'Canis' },
    { 'hellion', 'Hellion', 'Annis' }, { 'insurgent', 'Insurgent', 'HVY' }, { 'kalahari', 'Kalahari', 'Canis' },
    { 'kamacho', 'Kamacho', 'Canis' }, { 'mesa3', 'Mesa', 'Canis' }, { 'nightshark', 'Nightshark', 'HVY' },
    { 'outlaw', 'Outlaw', 'Nagasaki' }, { 'rancherxl', 'Rancher XL', 'Declasse' }, { 'rebel2', 'Rebel', 'Karin' },
    { 'riata', 'Riata', 'Vapid' }, { 'sandking', 'Sandking XL', 'Vapid' }, { 'trophytruck', 'Trophy Truck', 'Vapid' },
    { 'vagrant', 'Vagrant', 'Maxwell' }, { 'verus', 'Verus', 'Dinka' }, { 'winky', 'Winky', 'Vapid' },
})

addCatalogueVehicles('suvs', {
    { 'baller', 'Baller', 'Gallivanter' }, { 'bjxl', 'BeeJay XL', 'Karin' }, { 'cavalcade', 'Cavalcade', 'Albany' },
    { 'contender', 'Contender', 'Vapid' }, { 'dubsta', 'Dubsta', 'Benefactor' }, { 'granger', 'Granger', 'Declasse' },
    { 'gresley', 'Gresley', 'Bravado' }, { 'habanero', 'Habanero', 'Emperor' }, { 'huntley', 'Huntley S', 'Enus' },
    { 'landstalker', 'Landstalker', 'Dundreary' }, { 'patriot', 'Patriot', 'Mammoth' }, { 'radi', 'Radius', 'Vapid' },
    { 'rebla', 'Rebla GTS', 'Ubermacht' }, { 'rocoto', 'Rocoto', 'Obey' }, { 'seminole', 'Seminole', 'Canis' },
    { 'serrano', 'Serrano', 'Benefactor' }, { 'toros', 'Toros', 'Pegassi' }, { 'xls', 'XLS', 'Benefactor' },
})

addCatalogueVehicles('motorcycles', {
    { 'akuma', 'Akuma', 'Dinka' }, { 'bati', 'Bati 801', 'Pegassi' }, { 'bf400', 'BF400', 'Nagasaki' },
    { 'carbonrs', 'Carbon RS', 'Nagasaki' }, { 'daemon', 'Daemon', 'Western' }, { 'defiler', 'Defiler', 'Shitzu' },
    { 'double', 'Double-T', 'Dinka' }, { 'enduro', 'Enduro', 'Dinka' }, { 'faggio', 'Faggio', 'Pegassi' },
    { 'hakuchou', 'Hakuchou', 'Shitzu' }, { 'innovation', 'Innovation', 'LCC' }, { 'lectro', 'Lectro', 'Principe' },
    { 'manchez', 'Manchez', 'Maibatsu' }, { 'nemesis', 'Nemesis', 'Principe' }, { 'nightblade', 'Nightblade', 'Western' },
    { 'pcj', 'PCJ 600', 'Shitzu' }, { 'ruffian', 'Ruffian', 'Pegassi' }, { 'sanchez', 'Sanchez', 'Maibatsu' },
    { 'shotaro', 'Shotaro', 'Nagasaki' }, { 'sovereign', 'Sovereign', 'Western' }, { 'thrust', 'Thrust', 'Dinka' },
    { 'vader', 'Vader', 'Shitzu' }, { 'vortex', 'Vortex', 'Pegassi' }, { 'wolfsbane', 'Wolfsbane', 'Western' },
    { 'zombiea', 'Zombie Chopper', 'Western' },
})
