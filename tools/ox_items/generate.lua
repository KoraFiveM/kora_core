-- ox_inventory item generator: kora_core item registry -> data/items.lua.
--
-- Read-only and offline: plain Lua 5.4, no DB, no network, no FiveM natives.
-- Run from the repo root:
--
--   lua5.4 tools/ox_items/generate.lua [options]
--
-- See tools/ox_items/README.md for options, outputs and the collision policy.
-- The registry is built by loading kora_core's own shared seed files
-- (shared/items.lua, shared/upstream/items.lua, shared/upstream/merge.lua,
-- shared/weapons.lua) into a private environment, so the merge logic is the
-- shipped one rather than a reimplementation. The stock ox data/ files are only
-- read for NAMES (collision check, weapon/ammo target list); nothing is copied.

local M = {}

local scriptDir = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local repoRoot = scriptDir .. '/../..'

-- QB item names that are the same thing as an ox item under a different name.
-- `cash` is kora_core's physical-cash item; stock ox keeps cash as the `money`
-- item (inventory:accounts '["money"]', Q-D10), so it is mapped, not emitted.
M.ALIASES = { cash = 'money' }

-- Reserved names ox_inventory's own code depends on. Emitted minimally (label
-- only, same as stock) when kora does not define them, so the generated file
-- never drops them. Engine-referenced stock names must be defined in the kora registry
-- (shared/items.lua); the report warns if one is not.
M.RESERVED = {
    money = { label = 'Money' },
    black_money = { label = 'Dirty Money' },
}
M.ENGINE_REFERENCED = {
    'armour', 'bandage', 'clothing', 'garbage', 'identification', 'mastercard',
    'paperbag', 'parachute', 'phone',                      -- named in ox modules/
    'burger', 'sprunk', 'mustard', 'panties',              -- named in ox init.lua loot tables
}

-- Fallback ammo mapping for ammo-looking items that carry no `ammoType`.
M.AMMO_BY_NAME = {
    pistol_ammo = 'AMMO_PISTOL', smg_ammo = 'AMMO_SMG', shotgun_ammo = 'AMMO_SHOTGUN',
    rifle_ammo = 'AMMO_RIFLE', mg_ammo = 'AMMO_MG', snp_ammo = 'AMMO_SNIPER',
}

----------------------------------------------------------------------------
-- small helpers
----------------------------------------------------------------------------

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

local function readFile(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local s = f:read('a')
    f:close()
    return s
end

local function writeFile(path, content)
    local f, err = io.open(path, 'wb')
    if not f then return nil, err end
    f:write(content)
    f:close()
    return true
end

local function shellQuote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

local function mkdirp(dir)
    os.execute('mkdir -p ' .. shellQuote(dir))
end

local function dirname(path) return path:match('^(.*)/[^/]*$') or '.' end

local function luaString(s) return ('%q'):format(s):gsub('\\\n', '\\n') end

local function jsonEncode(v, indent)
    indent = indent or ''
    local t = type(v)
    if t == 'string' then
        return '"' .. v:gsub('[%c"\\]', function(c)
            local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
            return map[c] or ('\\u%04x'):format(c:byte())
        end) .. '"'
    elseif t == 'number' or t == 'boolean' then
        return tostring(v)
    elseif t == 'table' then
        local inner = indent .. '  '
        local parts = {}
        if #v > 0 or next(v) == nil then
            for i = 1, #v do parts[#parts + 1] = inner .. jsonEncode(v[i], inner) end
            if #parts == 0 then return '[]' end
            return '[\n' .. table.concat(parts, ',\n') .. '\n' .. indent .. ']'
        end
        for _, k in ipairs(sortedKeys(v)) do
            parts[#parts + 1] = inner .. jsonEncode(tostring(k)) .. ': ' .. jsonEncode(v[k], inner)
        end
        return '{\n' .. table.concat(parts, ',\n') .. '\n' .. indent .. '}'
    end
    return 'null'
end
M.jsonEncode = jsonEncode

----------------------------------------------------------------------------
-- loading
----------------------------------------------------------------------------

-- Run a chunk in the shared private environment.
local function runIn(env, path)
    local src = readFile(path)
    if not src then return false end
    local fn, err = load(src, '@' .. path, 't', env)
    if not fn then error(err, 0) end
    fn()
    return true
end

---Build the item and weapon lists from a kora_core-shaped tree.
---@param root string directory holding shared/items.lua etc.
---@return table items ordered list of merged item records (deduplicated by name)
---@return table weapons ordered list of weapon registry records
function M.loadRegistry(root)
    local env = setmetatable({}, { __index = _G })
    local loaded = {}
    for _, rel in ipairs({ 'shared/items.lua', 'shared/upstream/items.lua' }) do
        loaded[rel] = runIn(env, root .. '/' .. rel)
    end
    assert(loaded['shared/items.lua'] or loaded['shared/upstream/items.lua'],
        'no shared/items.lua or shared/upstream/items.lua under ' .. root)

    env.QBCoreSeed = env.QBCoreSeed or {}
    env.QBCoreUpstream = env.QBCoreUpstream or {}
    env.QBCoreSeed.items = env.QBCoreSeed.items or {}
    env.QBCoreUpstream.items = env.QBCoreUpstream.items or {}
    -- merge.lua asserts jobs/gangs seeds exist; items-only trees get empty ones.
    for _, k in ipairs({ 'jobs', 'gangs' }) do
        env.QBCoreSeed[k] = env.QBCoreSeed[k] or {}
        env.QBCoreUpstream[k] = env.QBCoreUpstream[k] or {}
    end
    -- Always the repo's own merge logic, even when --root is a fixture.
    assert(runIn(env, repoRoot .. '/shared/upstream/merge.lua'), 'shared/upstream/merge.lua not found')
    runIn(env, root .. '/shared/weapons.lua')

    -- Core.registry.registerShared keys by name and the last record wins.
    local items, index = {}, {}
    for _, record in ipairs(env.QBCoreSeed.items) do
        local pos = index[record.name]
        if pos then items[pos] = record else
            items[#items + 1] = record
            index[record.name] = #items
        end
    end
    return items, env.QBCoreSeed.weapons or {}
end

-- Globals a resource config.lua may use. Anything else it touches (lib, Kora,
-- GetConvar, locale helpers, vec3, ...) resolves to an inert stub so loading
-- cannot fail on code unrelated to Config.items. No io/os/require: read-only.
local SAFE_GLOBALS = {}
for _, k in ipairs({ 'assert', 'error', 'ipairs', 'next', 'pairs', 'pcall', 'select', 'tonumber', 'tostring',
    'type', 'math', 'string', 'table', 'utf8' }) do SAFE_GLOBALS[k] = true end

local function newStub()
    local stub = {}
    local function same() return stub end
    local meta = { __index = same, __call = same, __concat = same, __unm = same,
        __len = function() return 0 end, __tostring = function() return '' end }
    for _, op in ipairs({ 'add', 'sub', 'mul', 'div', 'mod', 'pow', 'idiv' }) do meta['__' .. op] = same end
    return setmetatable(stub, meta)
end

---Load a resource's config.lua in a private sandbox and read `Config.items`.
---Returns the items as a list sorted by name, each with `name` set to its key.
---@param path string resource directory (holds config.lua)
---@return table|nil items
---@return string|nil err
function M.loadResourceItems(path)
    local file = path .. '/config.lua'
    local src = readFile(file)
    if not src then return nil, 'cannot read ' .. file end
    local stub = newStub()
    -- `Config = Kora.config.adopt(Config)` would replace Config with the stub; keep the
    -- first real table assigned to it as the fallback.
    local firstConfig
    local env = setmetatable({}, {
        __index = function(_, k)
            if SAFE_GLOBALS[k] then return _G[k] end
            return stub
        end,
        __newindex = function(t, k, v)
            if k == 'Config' and firstConfig == nil and type(v) == 'table' and v ~= stub then firstConfig = v end
            rawset(t, k, v)
        end,
    })
    local fn, err = load(src, '@' .. file, 't', env)
    if not fn then return nil, err end
    local ok, runErr = pcall(fn)
    if not ok then return nil, tostring(runErr) end
    local config = rawget(env, 'Config')
    if config == stub then config = firstConfig end
    local defs = type(config) == 'table' and rawget(config, 'items') or nil
    if type(defs) ~= 'table' then return nil, file .. ' defines no Config.items table' end
    local list = {}
    for _, name in ipairs(sortedKeys(defs)) do
        local def = defs[name]
        if type(name) == 'string' and type(def) == 'table' then
            local record = {}
            for k, v in pairs(def) do record[k] = v end
            record.name = name
            list[#list + 1] = record
        end
    end
    return list
end

---Names of the top-level keys of a stock ox data file (names only).
local function loadOxTable(path)
    local src = readFile(path)
    if not src then return nil, 'cannot read ' .. path end
    local env = setmetatable({}, { __index = function() return function() end end })
    -- FXServer's `hash` literal syntax is not plain Lua; names only matter here.
    src = src:gsub('`([^`\n]*)`', '"%1"')
    local fn, err = load(src, '@' .. path, 't', env)
    if not fn then return nil, err end
    local ok, result = pcall(fn)
    if not ok then return nil, result end
    return result
end

---@param oxDir string path to the stock ox_inventory resource
---@return table|nil, string|nil
function M.loadOxNames(oxDir)
    local weapons, err = loadOxTable(oxDir .. '/data/weapons.lua')
    if not weapons then return nil, err end
    local items, ierr = loadOxTable(oxDir .. '/data/items.lua')
    if not items then return nil, ierr end
    local names = { weapons = {}, ammo = {}, items = {}, weaponAmmo = {} }
    for name, def in pairs(weapons.Weapons or {}) do
        names.weapons[name] = true
        names.weaponAmmo[name] = def.ammoname
    end
    for name in pairs(weapons.Ammo or {}) do names.ammo[name] = true end
    for name in pairs(items) do names.items[name] = true end
    return names
end

----------------------------------------------------------------------------
-- classification and mapping
----------------------------------------------------------------------------

local function isWeapon(record)
    return record.type == 'weapon' or record.name:sub(1, 7) == 'weapon_'
end

local function ammoTypeOf(record)
    if record.ammoType then return record.ammoType end
    return M.AMMO_BY_NAME[record.name]
end

---Pick the ox ammo item for each GTA ammo type by majority vote over the stock
---weapons that use it (ties broken alphabetically), keeping the alternatives.
local function deriveAmmoMap(weapons, ox)
    local votes = {}
    for _, w in ipairs(weapons) do
        local oxWeapon = w.name:upper()
        local ammoname = ox.weaponAmmo[oxWeapon]
        if w.ammotype and ammoname and ox.ammo[ammoname] then
            votes[w.ammotype] = votes[w.ammotype] or {}
            votes[w.ammotype][ammoname] = (votes[w.ammotype][ammoname] or 0) + 1
        end
    end
    local map = {}
    for ammoType, counts in pairs(votes) do
        local best, bestN
        for _, name in ipairs(sortedKeys(counts)) do
            if not bestN or counts[name] > bestN then best, bestN = name, counts[name] end
        end
        local alternatives = {}
        for _, name in ipairs(sortedKeys(counts)) do
            if name ~= best then alternatives[#alternatives + 1] = name end
        end
        map[ammoType] = { ox = best, alternatives = alternatives }
    end
    return map
end

----------------------------------------------------------------------------
-- items.lua emission
----------------------------------------------------------------------------

---Translate one QB/kora record into an ox item definition (plain table).
function M.toOxItem(record, opts)
    local def = { label = record.label or record.name, weight = tonumber(record.weight) or 0 }
    if record.unique then def.stack = false end
    if record.shouldClose == false then def.close = false end
    if type(record.description) == 'string' and record.description ~= '' then
        def.description = record.description
    end
    local image = record.image
    if opts.imageUrl and record.imageUrl then image = record.imageUrl end
    if image and image ~= record.name .. '.png' then def.client = { image = image } end
    if record.useable and opts.useExport then
        def.consume = 0
        def.server = { export = opts.useExport }
    end
    return def
end

local ORDER = { 'label', 'weight', 'stack', 'close', 'description', 'consume' }

local function emitItem(name, def)
    local lines = { ('    [%s] = {'):format(luaString(name)) }
    for _, key in ipairs(ORDER) do
        local v = def[key]
        if v ~= nil then
            local lit = type(v) == 'string' and luaString(v) or tostring(v)
            lines[#lines + 1] = ('        %s = %s,'):format(key, lit)
        end
    end
    if def.client then
        lines[#lines + 1] = ('        client = { image = %s },'):format(luaString(def.client.image))
    end
    if def.server then
        lines[#lines + 1] = ('        server = { export = %s },'):format(luaString(def.server.export))
    end
    lines[#lines + 1] = '    },'
    return table.concat(lines, '\n')
end

----------------------------------------------------------------------------
-- missing-item scan (heuristic)
----------------------------------------------------------------------------

local ITEM_CALLS = {
    'AddItem', 'RemoveItem', 'HasItem', 'GetItem', 'GetItemByName', 'GetItemCount',
    'CanCarryItem', 'CanAddItem', 'CreateUseableItem', 'CanUseItem', 'GetItemInfo',
    'AddItems', 'DoesItemExist', 'ItemExists', 'HasItems', 'Search', 'SetItemData',
}

---Split top-level call arguments, only as far as `want` args, string-aware.
local function splitArgs(s, start, want)
    local args, depth, i, cur = {}, 0, start, start
    local quote
    while i <= #s and #args < want do
        local c = s:sub(i, i)
        if quote then
            if c == '\\' then i = i + 1 elseif c == quote then quote = nil end
        elseif c == '"' or c == "'" then quote = c
        elseif c == '(' or c == '{' or c == '[' then depth = depth + 1
        elseif c == ')' or c == '}' or c == ']' then
            if depth == 0 then args[#args + 1] = s:sub(cur, i - 1); return args end
            depth = depth - 1
        elseif c == ',' and depth == 0 then
            args[#args + 1] = s:sub(cur, i - 1)
            cur = i + 1
        end
        i = i + 1
    end
    return args
end

local function literal(arg)
    if not arg then return nil end
    return arg:match('^%s*"([%w_%-%.]+)"%s*$') or arg:match("^%s*'([%w_%-%.]+)'%s*$")
end

---Scan Lua source text for item-name literals. Returns name -> { {line=..} }.
function M.scanText(text)
    local found = {}
    local lineNo = 0
    for line in (text .. '\n'):gmatch('(.-)\r?\n') do
        lineNo = lineNo + 1
        local code = line:gsub('%-%-.*$', '')
        for _, fn in ipairs(ITEM_CALLS) do
            local from = 1
            while true do
                local s, e = code:find(fn .. '%s*%(', from)
                if not s then break end
                from = e + 1
                -- call must not be the tail of a longer identifier (e.g. xAddItem)
                local prev = s > 1 and code:sub(s - 1, s - 1) or ''
                if not prev:match('[%w_]') then
                    local args = splitArgs(code, e + 1, 2)
                    local name = literal(args[1]) or literal(args[2])
                    if name then
                        found[name] = found[name] or {}
                        found[name][#found[name] + 1] = lineNo
                    end
                end
            end
        end
    end
    return found
end

function M.scanDirs(dirs)
    local refs, files = {}, 0
    for _, dir in ipairs(dirs) do
        local p = io.popen('find ' .. shellQuote(dir) ..
            ' -type f -name "*.lua" -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/test/*" 2>/dev/null | sort')
        if p then
            for path in p:lines() do
                local text = readFile(path)
                if text then
                    files = files + 1
                    for name, lines in pairs(M.scanText(text)) do
                        refs[name] = refs[name] or {}
                        for _, ln in ipairs(lines) do
                            if #refs[name] < 5 then refs[name][#refs[name] + 1] = path .. ':' .. ln end
                        end
                    end
                end
            end
            p:close()
        end
    end
    return refs, files
end

----------------------------------------------------------------------------
-- build
----------------------------------------------------------------------------

---Run the whole pipeline in memory.
---@param opts table root, oxDir, scanDirs?, imageUrl?, useExport?
---@return table result { itemsLua, mapping, report }
function M.build(opts)
    local items, weapons = M.loadRegistry(opts.root)
    local ox, err = M.loadOxNames(opts.oxDir)
    assert(ox, 'stock ox_inventory data not readable: ' .. tostring(err))

    -- Runtime-registered items. Like the resources' own "register if absent", the
    -- registry wins; reserved ox names keep ox semantics.
    local inRegistry = {}
    for _, rec in ipairs(items) do inRegistry[rec.name] = true end
    local registryCount = #items
    local resourceReport, contributed = {}, {}
    for _, path in ipairs(opts.resourceItems or {}) do
        local list, lerr = M.loadResourceItems(path)
        assert(list, 'resource items not readable: ' .. tostring(lerr))
        local entry = { resource = path:match('([^/]+)/*$') or path, path = path,
            items = {}, overlapRegistry = {}, skippedReserved = {}, excludedWeapons = {} }
        for _, rec in ipairs(list) do
            if inRegistry[rec.name] then
                entry.overlapRegistry[#entry.overlapRegistry + 1] = rec.name
            elseif isWeapon(rec) then
                entry.excludedWeapons[#entry.excludedWeapons + 1] = rec.name
            elseif M.RESERVED[rec.name] then
                entry.skippedReserved[#entry.skippedReserved + 1] = rec.name
            elseif contributed[rec.name] then
                entry.overlapRegistry[#entry.overlapRegistry + 1] = rec.name .. ' (also from ' .. contributed[rec.name] .. ')'
            else
                contributed[rec.name] = entry.resource
                entry.items[#entry.items + 1] = rec.name
                items[#items + 1] = rec
            end
        end
        resourceReport[#resourceReport + 1] = entry
    end

    local ammoMap = deriveAmmoMap(weapons, ox)
    local mapping = { weapons = {}, ammo = {}, aliases = {} }
    local unmapped = { weapons = {}, ammo = {} }
    local emitted, defs = {}, {}
    local skippedWeaponItems = 0

    local function mapWeapon(name)
        local oxName = name:upper()
        if ox.weapons[oxName] then mapping.weapons[name] = oxName else
            unmapped.weapons[#unmapped.weapons + 1] = name
        end
    end

    for _, w in ipairs(weapons) do mapWeapon(w.name) end
    for _, rec in ipairs(items) do
        if isWeapon(rec) then
            skippedWeaponItems = skippedWeaponItems + 1
            if not mapping.weapons[rec.name] then mapWeapon(rec.name) end
        end
    end
    table.sort(unmapped.weapons)
    local seenUnmapped, dedup = {}, {}
    for _, n in ipairs(unmapped.weapons) do
        if not seenUnmapped[n] then seenUnmapped[n] = true; dedup[#dedup + 1] = n end
    end
    unmapped.weapons = dedup

    local ammoNotes = {}
    for _, rec in ipairs(items) do
        if not isWeapon(rec) then
            local alias = M.ALIASES[rec.name]
            local ammoType = ammoTypeOf(rec)
            if alias then
                mapping.aliases[rec.name] = alias
            elseif ammoType and ammoMap[ammoType] then
                mapping.ammo[rec.name] = ammoMap[ammoType].ox
                if #ammoMap[ammoType].alternatives > 0 then
                    ammoNotes[rec.name] = ('%s -> %s (other stock weapons using %s take: %s)'):format(
                        rec.name, ammoMap[ammoType].ox, ammoType, table.concat(ammoMap[ammoType].alternatives, ', '))
                end
            else
                if ammoType or rec.name:match('_ammo$') then
                    unmapped.ammo[#unmapped.ammo + 1] = rec.name
                end
                defs[rec.name] = M.toOxItem(rec, opts)
                emitted[#emitted + 1] = rec.name
            end
        end
    end
    table.sort(emitted)
    table.sort(unmapped.ammo)

    -- Reserved names: only when kora does not define them.
    local reservedAdded = {}
    for name, def in pairs(M.RESERVED) do
        if not defs[name] then
            defs[name] = def
            emitted[#emitted + 1] = name
            reservedAdded[#reservedAdded + 1] = name
        end
    end
    table.sort(emitted)
    table.sort(reservedAdded)

    -- Collisions with stock data/items.lua.
    local collisions = {}
    for _, name in ipairs(emitted) do
        if ox.items[name] then
            local reserved = M.RESERVED[name] ~= nil
            collisions[#collisions + 1] = {
                name = name,
                policy = reserved and 'ox-semantics (reserved)' or 'kora wins',
                kora = defs[name].label,
            }
        end
    end
    local stockOnly = {}
    for name in pairs(ox.items) do
        if not defs[name] then stockOnly[#stockOnly + 1] = name end
    end
    table.sort(stockOnly)
    local engineWarnings = {}
    for _, name in ipairs(M.ENGINE_REFERENCED) do
        if ox.items[name] and not defs[name] then engineWarnings[#engineWarnings + 1] = name end
    end

    -- Source text.
    local out = {
        '-- GENERATED by tools/ox_items/generate.lua from the kora_core item registry.',
        '-- Do not edit by hand: change the registry and regenerate (Q-D8).',
        '-- Weapons and ammo are intentionally absent: stock data/weapons.lua owns them (Q-D9).',
        'return {',
    }
    for _, name in ipairs(emitted) do out[#out + 1] = emitItem(name, defs[name]) end
    out[#out + 1] = '}'
    out[#out + 1] = ''

    -- Missing-item scan.
    local refs, scannedFiles = {}, 0
    if opts.scanDirs and #opts.scanDirs > 0 then refs, scannedFiles = M.scanDirs(opts.scanDirs) end
    local known = {}
    for _, name in ipairs(emitted) do known[name] = true end
    for qb, oxName in pairs(mapping.weapons) do known[qb] = true; known[oxName] = true; known[oxName:lower()] = true end
    for qb, oxName in pairs(mapping.ammo) do known[qb] = true; known[oxName] = true end
    for qb in pairs(mapping.aliases) do known[qb] = true end
    for name in pairs(ox.weapons) do known[name] = true end
    for name in pairs(ox.ammo) do known[name] = true end
    local missing = {}
    for _, name in ipairs(sortedKeys(refs)) do
        if not known[name] and not known[name:upper()] then
            missing[#missing + 1] = {
                name = name, stockItem = ox.items[name] == true or nil, at = refs[name],
            }
        end
    end

    local useable = 0
    for _, rec in ipairs(items) do if rec.useable and not isWeapon(rec) then useable = useable + 1 end end

    local report = {
        generatedItems = #emitted,
        registryItems = registryCount,
        resourceItems = resourceReport,
        weaponsMapped = #sortedKeys(mapping.weapons),
        ammoMapped = #sortedKeys(mapping.ammo),
        weaponItemsExcluded = skippedWeaponItems,
        unmappedWeapons = unmapped.weapons,
        unmappedAmmo = unmapped.ammo,
        ammoNotes = (function()
            local notes = {}
            for _, k in ipairs(sortedKeys(ammoNotes)) do notes[#notes + 1] = ammoNotes[k] end
            return notes
        end)(),
        reservedAdded = reservedAdded,
        collisions = collisions,
        stockOnlyItems = stockOnly,
        engineReferencedStockItemsDropped = engineWarnings,
        useableItems = useable,
        useExport = opts.useExport,
        scan = {
            heuristic = true,
            note = 'Literal item names in Add/Remove/Has/... calls only; dynamic names, data tables and ' ..
                'shop/crafting configs are not seen. Treat an empty list as necessary, not sufficient.',
            dirs = opts.scanDirs or {},
            files = scannedFiles,
            referencedNames = #sortedKeys(refs),
            missing = missing,
        },
    }
    return { itemsLua = table.concat(out, '\n'), mapping = mapping, report = report }
end

local function reportMarkdown(r)
    local L = {}
    local function add(s) L[#L + 1] = s or '' end
    add('# ox_inventory item generation report')
    add()
    add(('- Registry items: %d; emitted to items.lua: %d; useable (non-weapon): %d'):format(
        r.registryItems, r.generatedItems, r.useableItems))
    add(('- Weapons mapped QB -> ox: %d; ammo items mapped: %d; weapon-type items excluded from items.lua: %d'):format(
        r.weaponsMapped, r.ammoMapped, r.weaponItemsExcluded))
    add(r.useExport and ('- Useable items point at server export `%s`.'):format(r.useExport) or
        '- Useable items carry no server export: use goes through the framework bridge (`CanUseItem`).')
    if #r.resourceItems > 0 then
        add()
        add('## Items registered at runtime by resources (`--resource-items`)')
        add()
        for _, e in ipairs(r.resourceItems) do
            add(('- `%s`: %d item(s): %s'):format(e.resource, #e.items,
                #e.items > 0 and ('`' .. table.concat(e.items, '`, `') .. '`') or 'none'))
            if #e.overlapRegistry > 0 then
                add(('  - already defined, registry/earlier resource wins (not taken from this resource): `%s`'):format(
                    table.concat(e.overlapRegistry, '`, `')))
            end
            if #e.excludedWeapons > 0 then
                add(('  - weapon items, owned by stock data/weapons.lua (not emitted): `%s`'):format(
                    table.concat(e.excludedWeapons, '`, `')))
            end
            if #e.skippedReserved > 0 then
                add(('  - reserved ox names, ox semantics kept: `%s`'):format(table.concat(e.skippedReserved, '`, `')))
            end
        end
    end
    add()
    add('## Missing items (heuristic scan)')
    add()
    add('> ' .. r.scan.note)
    add()
    add(('Scanned %d file(s), %d distinct literal item name(s).'):format(r.scan.files, r.scan.referencedNames))
    add()
    if #r.scan.missing == 0 then add('**None.**') else
        add('**' .. #r.scan.missing .. ' name(s) would be dropped by ox_inventory. This must be empty before go-live.**')
        add()
        for _, m in ipairs(r.scan.missing) do
            add(('- `%s`%s -- %s'):format(m.name, m.stockItem and ' (stock ox item, not in generated file)' or '',
                table.concat(m.at, ', ')))
        end
    end
    add()
    add('## Collisions with stock data/items.lua')
    add()
    if #r.collisions == 0 then add('None.') else
        for _, c in ipairs(r.collisions) do add(('- `%s`: %s (kora label: %s)'):format(c.name, c.policy, c.kora)) end
    end
    add()
    add('Stock items absent from the generated file: ' ..
        (#r.stockOnlyItems > 0 and ('`' .. table.concat(r.stockOnlyItems, '`, `') .. '`') or 'none'))
    if #r.engineReferencedStockItemsDropped > 0 then
        add()
        add('**Warning:** ox_inventory code references these stock items by name and the registry does not ' ..
            'define them: `' .. table.concat(r.engineReferencedStockItemsDropped, '`, `') .. '`. Add them to the registry.')
    end
    add()
    add('## Weapons and ammo')
    add()
    add('Full QB -> ox name table is in `mapping.json`.')
    if #r.unmappedWeapons > 0 then
        add()
        add('Weapons with no stock ox counterpart (lost on migration unless added to data/weapons.lua): `' ..
            table.concat(r.unmappedWeapons, '`, `') .. '`')
    end
    if #r.unmappedAmmo > 0 then
        add()
        add('Ammo-like items with no mapping, emitted as plain items: `' .. table.concat(r.unmappedAmmo, '`, `') .. '`')
    end
    for _, note in ipairs(r.ammoNotes) do add('- ' .. note) end
    add()
    return table.concat(L, '\n')
end

----------------------------------------------------------------------------
-- CLI
----------------------------------------------------------------------------

local USAGE = [[
usage: lua5.4 tools/ox_items/generate.lua [options]
  --out <path>          items.lua output path (default ./out/ox_items/items.lua)
  --root <dir>          kora_core tree holding shared/ (default: this repo)
  --ox-dir <dir>        REQUIRED: stock ox_inventory resource (read for names only)
  --scan <dir>          extra directory to scan for item names (repeatable)
  --no-default-scan     do not scan --root (this kora_core checkout) by default
  --resource-items <dir>  resource whose config.lua Config.items it registers at runtime (repeatable)
  --image-url           use the registry imageUrl instead of the local image name
  --use-export <r.fn>   point useable items at a server export (also sets consume = 0)
  --strict              exit 2 if the missing-item report is not empty
  -h, --help]]

function M.main(argv)
    local opts = { out = './out/ox_items/items.lua', root = repoRoot, scanDirs = {}, resourceItems = {}, defaultScan = true }
    local i = 1
    while i <= #argv do
        local a = argv[i]
        local function value() i = i + 1; return argv[i] end
        if a == '--out' then opts.out = value()
        elseif a == '--root' then opts.root = value()
        elseif a == '--ox-dir' then opts.oxDir = value()
        elseif a == '--scan' then opts.scanDirs[#opts.scanDirs + 1] = value()
        elseif a == '--resource-items' then opts.resourceItems[#opts.resourceItems + 1] = value()
        elseif a == '--no-default-scan' then opts.defaultScan = false
        elseif a == '--image-url' then opts.imageUrl = true
        elseif a == '--use-export' then opts.useExport = value()
        elseif a == '--strict' then opts.strict = true
        elseif a == '-h' or a == '--help' then print(USAGE); return 0
        else io.stderr:write('unknown option: ' .. tostring(a) .. '\n' .. USAGE .. '\n'); return 1 end
        i = i + 1
    end

    if not opts.oxDir then
        io.stderr:write('--ox-dir <path-to-ox_inventory> is required\n' .. USAGE .. '\n')
        return 1
    end
    if opts.defaultScan then table.insert(opts.scanDirs, 1, opts.root) end

    local ok, result = pcall(M.build, opts)
    if not ok then io.stderr:write('generate: ' .. tostring(result) .. '\n'); return 1 end

    local dir = dirname(opts.out)
    mkdirp(dir)
    local writes = {
        { opts.out, result.itemsLua },
        { dir .. '/mapping.json', jsonEncode(result.mapping) .. '\n' },
        { dir .. '/report.json', jsonEncode(result.report) .. '\n' },
        { dir .. '/report.md', reportMarkdown(result.report) },
    }
    for _, w in ipairs(writes) do
        local wrote, err = writeFile(w[1], w[2])
        if not wrote then io.stderr:write('generate: ' .. tostring(err) .. '\n'); return 1 end
    end
    print(('wrote %d items to %s (+ mapping.json, report.json, report.md); %d missing name(s)'):format(
        result.report.generatedItems, opts.out, #result.report.scan.missing))
    if opts.strict and #result.report.scan.missing > 0 then return 2 end
    return 0
end

M.reportMarkdown = reportMarkdown

-- Run as a script, not when dofile'd by a test.
if arg and arg[0] and arg[0]:match('generate%.lua$') then os.exit(M.main(arg)) end

return M
