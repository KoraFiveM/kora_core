-- Merge the canonical qb-core defaults behind kora_core's purpose-built records.
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

-- Upstream Items also lists every inventory weapon. Native weapons live in
-- their own registry (shared/weapons.lua, loaded after this file), and an
-- `items` record of the same name is an explicit override that wins over the
-- weapon record everywhere (kora_inventory's itemDef, the legacy Items view).
-- Merging them here shadowed every native weapon with qb-core's copy, which
-- has no weapontype, damageModifier or ammoItem and says useable = false:
-- throwables never registered as throwable, carry tiers, tier animations and
-- damage tuning all fell back to nothing. Hold them aside instead;
-- shared/weapons.lua fills gaps in the native weapon records from them.
local function splitUpstreamWeapons(target, upstream)
    local native = {}
    for _, record in ipairs(target) do
        native[record.name] = true
    end
    local weapons = {}
    for name, source in pairs(upstream) do
        -- A native item of the same name is a deliberate override: leave the
        -- upstream copy in place so the normal field merge still applies.
        if type(source) == 'table' and source.type == 'weapon' and not native[source.name or name] then
            source.name = source.name or name
            weapons[source.name] = source
            upstream[name] = nil
        end
    end
    return weapons
end

assert(QBCoreSeed and QBCoreUpstream, 'shared seed tables must load before the qb-core compatibility merge')
QBCoreSeed.upstreamWeapons = splitUpstreamWeapons(QBCoreSeed.items, QBCoreUpstream.items)
mergeRegistry(QBCoreSeed.items, QBCoreUpstream.items)
mergeRegistry(QBCoreSeed.jobs, QBCoreUpstream.jobs)
mergeRegistry(QBCoreSeed.gangs, QBCoreUpstream.gangs)

QBCoreUpstream = nil
