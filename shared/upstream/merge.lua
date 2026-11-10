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
KoraCoreSeed.upstreamWeapons = splitUpstreamWeapons(KoraCoreSeed.items, QBCoreUpstream.items)
mergeRegistry(KoraCoreSeed.items, QBCoreUpstream.items)
mergeRegistry(KoraCoreSeed.jobs, QBCoreUpstream.jobs)
mergeRegistry(KoraCoreSeed.gangs, QBCoreUpstream.gangs)

QBCoreUpstream = nil
