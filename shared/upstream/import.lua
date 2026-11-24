local registryNames = { 'items', 'jobs', 'gangs', 'vehicles', 'weapons' }

local function validateData(value, parents)
    local valueType = type(value)
    if valueType == 'table' then
        assert(not parents[value], 'record contains a circular table')
        parents[value] = true
        for key, child in pairs(value) do
            assert(type(key) == 'string' or type(key) == 'number', 'record contains an invalid table key')
            validateData(child, parents)
        end
        parents[value] = nil
    else
        assert(valueType == 'string' or valueType == 'number' or valueType == 'boolean',
            'record contains an unsupported ' .. valueType .. ' value')
    end
end

local function readRecords(source, path, name, keyField, hash)
    local shared = {}
    local env = {
        QBShared = shared,
        QBCore = { Shared = shared },
        QBCoreUpstream = {},
        joaat = hash,
        GetHashKey = hash,
        ipairs = ipairs,
        pairs = pairs,
    }
    -- Load operator-provided data without access to Core or to the host globals.
    local chunk, err = load(source, '@' .. path, 't', env)
    assert(chunk, err)
    chunk()

    local capital = name:sub(1, 1):upper() .. name:sub(2)
    local sourceRecords = env.QBCoreUpstream[name]
    if sourceRecords == nil then sourceRecords = env.QBCore.Shared[capital] end
    if sourceRecords == nil then sourceRecords = env.QBShared[capital] end
    assert(type(sourceRecords) == 'table', ('expected a %s table'):format(capital))

    local records, keys = {}, {}
    for key, record in pairs(sourceRecords) do
        assert(type(record) == 'table', ('record %s is not a table'):format(tostring(key)))
        local id = record[keyField]
        if id == nil then id = key end
        assert(type(id) == 'string' and id ~= '', ('record %s needs a %s'):format(tostring(key), keyField))
        assert(not records[id], ('duplicate record %q'):format(id))
        validateData(record, {})
        record[keyField] = id
        records[id] = record
        keys[#keys + 1] = id
    end
    table.sort(keys)
    return records, keys
end

local function fillMissing(target, source, fallback)
    for field, value in pairs(source) do
        if target[field] == nil and (not fallback or fallback[field] == nil) then
            target[field] = value
        end
    end
end

---Add optional qb-core definitions to the native server seed before registration.
---@param seed table
---@param read fun(path: string): string?
---@param warn fun(path: string, reason: string)
---@param hash? fun(model: string): number
local function importLegacy(seed, read, warn, hash)
    local indices = {}
    local function index(name, keyField)
        if indices[name] then return indices[name] end
        local indexed = {}
        seed[name] = seed[name] or {}
        for _, record in ipairs(seed[name]) do
            indexed[record[keyField]] = record
        end
        indices[name] = indexed
        return indexed
    end

    for _, name in ipairs(registryNames) do
        local path = 'shared/upstream/' .. name .. '.lua'
        local source = read(path)
        if source then
            local keyField = name == 'vehicles' and 'model' or 'name'
            local ok, records, keys = pcall(readRecords, source, path, name, keyField, hash)
            if not ok then
                warn(path, tostring(records))
            else
                for _, id in ipairs(keys) do
                    local record = records[id]
                    local target = name
                    if name == 'items' and (index('weapons', 'name')[id]
                        or (record.type == 'weapon' and not index('items', 'name')[id])) then
                        target = 'weapons'
                    end
                    local byKey = index(target, keyField)
                    if byKey[id] then
                        local legacyMetadata = name == 'weapons' and seed.legacyWeaponMetadata
                        fillMissing(byKey[id], record, legacyMetadata and legacyMetadata[id])
                    elseif name ~= 'weapons' then
                        -- qb-core's weapons.lua also contains non-item damage causes.
                        seed[target][#seed[target] + 1] = record
                        byKey[id] = record
                    end
                end
            end
        end
    end
end

if LoadResourceFile and IsDuplicityVersion() then
    local resource = GetCurrentResourceName()
    importLegacy(KoraCoreSeed, function(path)
        return LoadResourceFile(resource, path)
    end, function(path, reason)
        Kora.logging.warn('registry.legacy_seed_import_failed', 'Could not import legacy shared data', {
            path = path,
            reason = reason,
        })
    end, joaat)
end

return importLegacy
