-- Merge the canonical qb-core defaults behind qbcore's purpose-built records.
-- Existing definitions keep their values because they carry server-specific
-- behaviour (service types, duty defaults, ballistics and container flags),
-- while fields and whole records absent locally are filled from the snapshot.

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

assert(QBCoreSeed and QBCoreUpstream, 'shared seed tables must load before the qb-core compatibility merge')
mergeRegistry(QBCoreSeed.items, QBCoreUpstream.items)
mergeRegistry(QBCoreSeed.jobs, QBCoreUpstream.jobs)
mergeRegistry(QBCoreSeed.gangs, QBCoreUpstream.gangs)

QBCoreUpstream = nil
