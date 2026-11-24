local function mergeRegistry(target, upstream)
    local existing = {}
    for _, record in ipairs(target) do
        existing[record.name] = record
    end

    local names = {}
    for name in pairs(upstream) do
        names[#names + 1] = name
    end
    table.sort(names)

    for _, name in ipairs(names) do
        local source = upstream[name]
        source.name = source.name or name

        local current = existing[name]
        if current then
            for field, value in pairs(source) do
                if current[field] == nil then current[field] = value end
            end
        else
            target[#target + 1] = source
        end
    end
end

local function splitUpstreamWeapons(target, upstream)
    local native = {}
    for _, record in ipairs(target) do
        native[record.name] = true
    end
    local weapons = {}
    for name, source in pairs(upstream) do
        if type(source) == 'table' and source.type == 'weapon' and not native[source.name or name] then
            source.name = source.name or name
            weapons[source.name] = source
            upstream[name] = nil
        end
    end
    return weapons
end

assert(KoraCoreSeed and QBCoreUpstream, 'shared seed tables must load before the qb-core compatibility merge')
local function inventoryData(path)
    if LoadResourceFile then
        -- Client registries receive these records in the server snapshot.
        if not IsDuplicityVersion() then return {} end
        local source = LoadResourceFile('kora_inventory', path)
        if not source then return {} end
        return assert(load(source, '@kora_inventory/' .. path, 't'))()
    end

    local catalogue = loadfile('../kora_inventory/' .. path)
    return catalogue and catalogue() or {}
end

local function mergeNativeItems(bundled, legacy)
    local index = {}
    for _, record in ipairs(bundled) do
        index[record.name] = record
    end
    for _, record in ipairs(legacy) do
        local existing = index[record.name]
        if existing then
            for field, value in pairs(record) do
                existing[field] = value
            end
        else
            bundled[#bundled + 1] = record
            index[record.name] = record
        end
    end
    return bundled
end

local bundledItems, bundledWeapons = {}, {}
for _, path in ipairs({
    'data/items.lua',
    'data/weapons.lua',
    'data/food.lua',
    'data/dranks.lua',
}) do
    for _, record in ipairs(inventoryData(path)) do
        local target = record.type == 'weapon' and bundledWeapons or bundledItems
        target[#target + 1] = record
    end
end
KoraCoreSeed.items = mergeNativeItems(bundledItems, KoraCoreSeed.items)
KoraCoreSeed.inventoryWeapons = bundledWeapons
local upstreamItems = inventoryData('data/qb-items.lua')
if LoadResourceFile and IsDuplicityVersion() and #bundledItems == 0 and #bundledWeapons == 0 and next(upstreamItems) == nil then
    Kora.logging.error(
        'registry.inventory_catalogue_missing',
        'No bundled items loaded from kora_inventory/data. Install the matching kora_inventory resource and restart kora_core.'
    )
end
for name, definition in pairs(QBCoreUpstream.items) do
    upstreamItems[name] = definition
end
QBCoreUpstream.items = upstreamItems

KoraCoreSeed.upstreamWeapons = splitUpstreamWeapons(KoraCoreSeed.items, QBCoreUpstream.items)
mergeRegistry(KoraCoreSeed.items, QBCoreUpstream.items)
mergeRegistry(KoraCoreSeed.jobs, QBCoreUpstream.jobs)
mergeRegistry(KoraCoreSeed.gangs, QBCoreUpstream.gangs)

QBCoreUpstream = nil
