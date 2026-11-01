-- Core.inventory (server realm) -- the item model. Storage is the legacy
-- slot-keyed table PlayerData.items[slot] = { slot, name, amount, info, type,
-- unique, useable, image, imageUrl, label, weight, ... }. Every mutation goes through the
-- funnel Core.player.setPath(src, {'items', slot}, record) so inventory gets
-- per-slot dirty tracking + delta replication for free. No NUI is shipped; open
-- emits an event for a UI resource.

local PI = CoreInternal.player
local II = CoreInternal.inventory

-- Registered useable-item handlers: name -> { resource, handler(src, item) }.
-- OWNER-TRACKED via Kora.resources.serverRegistry so a restarted resource leaves no stale handlers.
local useables = {}

local useableRegistry = Kora.resources.serverRegistry(function(name)
    useables[name] = nil
end)

local function buildItem(name, amount, slot, info)
    local def = Core.registry.getShared('items', name) or Core.registry.getShared('weapons', name)
    if not def then return nil end
    return {
        slot = slot,
        name = name,
        amount = amount,
        info = info or {},
        type = def.type or 'item',
        unique = def.unique or false,
        useable = def.useable or false,
        image = def.image,
        imageUrl = def.imageUrl,
        label = def.label or name,
        weight = def.weight or 0,
        shouldClose = def.shouldClose,
        description = def.description,
        created = os.time(),
    }
end

local function items(src) local p = PI.handle(src); return p and p.PlayerData.items or nil end

local function validSlot(slot)
    return Kora.util.isInteger(slot) and slot >= 1 and slot <= Config.inventory.slots
end

---@param src integer
---@return number weight, number maxWeight
function Core.inventory.getWeight(src)
    local it = items(src)
    if not it then return 0, Config.inventory.maxWeight end
    return II.totalWeight(it), Config.inventory.maxWeight
end

---@param src integer
---@param name string
---@param amount integer|nil
---@return boolean, string|nil
function Core.inventory.canCarry(src, name, amount)
    local it = items(src)
    if not it then return false, 'no such player' end
    amount = amount or 1
    local def = Core.registry.getShared('items', name) or Core.registry.getShared('weapons', name)
    if not def then return false, 'unknown item' end
    local addWeight = (def.weight or 0) * amount
    local current = II.totalWeight(it)
    if current + addWeight > Config.inventory.maxWeight then return false, 'over weight' end
    if II.isUnique(name) then
        local needed = amount
        for slot = 1, Config.inventory.slots do
            if it[slot] == nil then
                needed = needed - 1
                if needed <= 0 then return true end
            end
        end
        return false, 'no free slot'
    end
    if not II.findStackSlot(it, name, nil) and II.firstFreeSlot(it) == nil then return false, 'no free slot' end
    return true
end

---@param src integer
---@param name string
---@param amount integer|nil
---@param slot integer|nil  -- force a slot; otherwise stack-or-first-free
---@param info table|nil
---@param reason string|nil
---@return boolean, string|nil
function Core.inventory.addItem(src, name, amount, slot, info, reason)
    local p = PI.handle(src)
    if not p then return false, 'no such player' end
    if p._loggingOut or Core.persistence._isColumnLocked and Core.persistence._isColumnLocked(p.citizenid, 'inventory') then return false, 'player data is busy' end
    amount = math.floor(tonumber(amount) or 1)
    if amount <= 0 then return false, 'amount must be positive' end
    local it = p.PlayerData.items

    local def = Core.registry.getShared('items', name) or Core.registry.getShared('weapons', name)
    if not def then return false, 'unknown item' end

    local unique = II.isUnique(name)
    if slot then
        if not validSlot(slot) then
            return false, 'invalid slot'
        end
        local existing = it[slot]
        -- Bulk unique grants have always used free slots rather than the requested slot.
        if existing and (not unique or amount == 1) then
            if unique or existing.name ~= name then return false, 'slot occupied' end
            if Config.inventory.matchInfoOnStack and not II.infoEquals(existing.info, info) then
                return false, 'slot occupied'
            end
        end
    end

    local can, err = Core.inventory.canCarry(src, name, amount)
    if not can then return false, err end

    if not unique then
        local stackSlot = slot or II.findStackSlot(it, name, info)
        if stackSlot and it[stackSlot] and it[stackSlot].name == name then
            local merged = it[stackSlot]
            merged.amount = merged.amount + amount
            Core.player.setPath(src, { 'items', stackSlot }, merged)
            TriggerClientEvent('qbcore:client:itemBox', src, def, 'add', amount)
            return true
        end
    end

    local target = slot or II.firstFreeSlot(it)
    if not target then return false, 'no free slot' end
    -- A unique item added with amount > 1 occupies multiple slots one at a time.
    if unique and amount > 1 then
        for _ = 1, amount do
            local free = II.firstFreeSlot(p.PlayerData.items)
            if not free then return false, 'no free slot' end
            Core.player.setPath(src, { 'items', free }, buildItem(name, 1, free, info))
        end
    else
        Core.player.setPath(src, { 'items', target }, buildItem(name, amount, target, info))
    end
    TriggerClientEvent('qbcore:client:itemBox', src, def, 'add', amount)
    return true
end

---@param src integer
---@param name string
---@param amount integer|nil
---@param slot integer|nil
---@param reason string|nil
---@return boolean, string|nil
function Core.inventory.removeItem(src, name, amount, slot, reason)
    local p = PI.handle(src)
    if not p then return false, 'no such player' end
    if p._loggingOut or Core.persistence._isColumnLocked and Core.persistence._isColumnLocked(p.citizenid, 'inventory') then return false, 'player data is busy' end
    amount = math.floor(tonumber(amount) or 1)
    if amount <= 0 then return false, 'amount must be positive' end
    local it = p.PlayerData.items

    -- Remove from a specific slot, or drain across matching slots lowest-first.
    if slot and it[slot] and it[slot].name == name then
        return Core.inventory._removeFromSlot(src, slot, amount)
    end

    local remaining = amount
    -- Deterministic order: lowest slot first.
    local slots = {}
    for s, item in pairs(it) do if item.name == name then slots[#slots + 1] = s end end
    table.sort(slots)
    -- Verify total first so we never partially remove.
    local total = 0
    for _, s in ipairs(slots) do total = total + it[s].amount end
    if total < amount then return false, 'not enough of item' end

    for _, s in ipairs(slots) do
        if remaining <= 0 then break end
        local take = math.min(remaining, it[s].amount)
        Core.inventory._removeFromSlot(src, s, take)
        remaining = remaining - take
    end
    return true
end

function Core.inventory._removeFromSlot(src, slot, amount)
    local p = PI.handle(src)
    if not p then return false, 'no such player' end
    if p._loggingOut or Core.persistence._isColumnLocked and Core.persistence._isColumnLocked(p.citizenid, 'inventory') then return false, 'player data is busy' end
    local item = p.PlayerData.items[slot]
    if not item then return false, 'empty slot' end
    if item.amount <= amount then
        Core.player.setPath(src, { 'items', slot }, nil)   -- nil -> delete op + dirty
    else
        item.amount = item.amount - amount
        Core.player.setPath(src, { 'items', slot }, item)
    end
    local def = Core.registry.getShared('items', item.name)
    if def then TriggerClientEvent('qbcore:client:itemBox', src, def, 'remove', amount) end
    return true
end

---@param src integer
---@param name string
---@return table|nil  -- the first matching item record
function Core.inventory.getItemByName(src, name)
    local it = items(src); if not it then return nil end
    local best
    for slot, item in pairs(it) do
        if item.name == name and (best == nil or slot < best.slot) then best = item end
    end
    return best
end

---@param src integer
---@param name string
---@return table[]
function Core.inventory.getItemsByName(src, name)
    local it = items(src); local out = {}
    if it then for _, item in pairs(it) do if item.name == name then out[#out + 1] = item end end end
    return out
end

---@param src integer
---@param slot integer
---@return table|nil
function Core.inventory.getItemBySlot(src, slot)
    local it = items(src); return it and it[slot] or nil
end

---@param src integer
---@param name string
---@return integer
function Core.inventory.getItemCount(src, name)
    local it = items(src); local n = 0
    if it then for _, item in pairs(it) do if item.name == name then n = n + (item.amount or 0) end end end
    return n
end

---@param src integer
---@param nameOrList string|string[]
---@param amount integer|nil
---@return boolean
function Core.inventory.hasItem(src, nameOrList, amount)
    if type(nameOrList) == 'table' then
        if nameOrList[1] == nil then
            for name, need in pairs(nameOrList) do
                if Core.inventory.getItemCount(src, name) < (amount or tonumber(need) or 1) then return false end
            end
            return true
        end
        for _, name in ipairs(nameOrList) do
            if Core.inventory.getItemCount(src, name) < (amount or 1) then return false end
        end
        return true
    end
    amount = amount or 1
    return Core.inventory.getItemCount(src, nameOrList) >= amount
end

---@param src integer
---@return integer|nil
function Core.inventory.getFreeSlot(src)
    local it = items(src); return it and II.firstFreeSlot(it) or nil
end

---@return boolean, string|nil
function Core.inventory.moveItem(src, fromSlot, toSlot, amount)
    local p = PI.handle(src)
    if not p then return false, 'no such player' end
    if p._loggingOut or Core.persistence._isColumnLocked and Core.persistence._isColumnLocked(p.citizenid, 'inventory') then return false, 'player data is busy' end
    if not validSlot(fromSlot) or not validSlot(toSlot) then return false, 'invalid slot' end
    local it = p.PlayerData.items
    local from = it[fromSlot]
    if not from then return false, 'empty source slot' end
    amount = tonumber(amount) or from.amount
    if not Kora.util.isFiniteNumber(amount) then return false, 'amount must be finite' end
    amount = math.min(math.floor(amount), from.amount)
    if amount <= 0 then return false, 'amount must be positive' end
    if fromSlot == toSlot then return true end

    local dest = it[toSlot]
    if dest and dest.name ~= from.name then return false, 'destination occupied' end

    if from.amount <= amount then
        Core.player.setPath(src, { 'items', fromSlot }, nil)
    else
        from.amount = from.amount - amount
        Core.player.setPath(src, { 'items', fromSlot }, from)
    end
    if dest then
        dest.amount = dest.amount + amount
        Core.player.setPath(src, { 'items', toSlot }, dest)
    else
        Core.player.setPath(src, { 'items', toSlot }, buildItem(from.name, amount, toSlot, from.info))
    end
    return true
end

---@param src integer
---@param keep string[]|nil
---@return boolean
function Core.inventory.clearInventory(src, keep)
    local p = PI.handle(src)
    if not p then return false end
    if p._loggingOut or Core.persistence._isColumnLocked and Core.persistence._isColumnLocked(p.citizenid, 'inventory') then return false, 'player data is busy' end
    local keepSet = {}
    if keep then for _, n in ipairs(keep) do keepSet[n] = true end end
    for slot, item in pairs(p.PlayerData.items) do
        if not keepSet[item.name] then
            Core.player.setPath(src, { 'items', slot }, nil)
        end
    end
    return true
end

---@param src integer
---@param newItems table
---@return boolean
function Core.inventory.setItems(src, newItems)
    local p = PI.handle(src)
    if not p then return false end
    return Core.player.setPath(src, { 'items' }, newItems or {})
end

---@param name string
---@param handler fun(src:integer, item:table)
function Core.inventory.createUseable(name, handler)
    local owner = GetInvokingResource() or GetCurrentResourceName()
    useables[name] = { resource = owner, handler = handler }
    -- track(resource, id) needs both args (one arg raised "table index is nil").
    if owner then useableRegistry.track(owner, name) end
end

---Return the registered callback record, not whether an item definition exists.
function Core.inventory.getUseable(name)
    local record = useables[name]
    if record then return { func = record.handler, resource = record.resource } end
end

---@param src integer
---@param slotOrName integer|string
---@return boolean
function Core.inventory.useItem(src, slotOrName)
    local p = PI.handle(src)
    if not p or p._loggingOut then return false end
    local item
    if type(slotOrName) == 'number' then
        item = Core.inventory.getItemBySlot(src, slotOrName)
    else
        item = Core.inventory.getItemByName(src, slotOrName)
    end
    if not item then return false end
    local u = useables[item.name]
    if not u then
        TriggerEvent('QBCore:Server:UseItem', src, item)   -- legacy hook
        return false
    end
    local ok, result = pcall(u.handler, src, item)
    if not ok then
        print(("^3[qbcore:inventory]^7 useable '%s' errored: %s"):format(item.name, tostring(result)))
        return false
    end
    return result ~= false
end

---@param identifier string
---@return table
function Core.inventory.stashGet(identifier)
    local row = Kora.sql.single('SELECT `items` FROM `inventories` WHERE `identifier` = ?', { identifier })
    if not row then return {} end
    local ok, v = pcall(json.decode, row.items or '')
    return ok and v or {}
end

---@param identifier string
---@param stashItems table
---@return boolean
function Core.inventory.stashSet(identifier, stashItems)
    Kora.sql.enqueue('inventories', 'identifier',
        { pk = identifier, cols = { items = json.encode(stashItems or {}), kind = 'stash' } },
        { mode = 'assign' })
    return true
end

---Open a stash for a player. Ships NO NUI: emits an event a UI resource handles,
---and warns if nothing does (an explicit non-goal, not a fake stub).
---@param src integer
---@param identifier string
---@param opts table|nil
---@return boolean, string|nil
function Core.inventory.stashOpen(src, identifier, opts)
    local handled = TriggerEvent('qbcore:inventory:open', src, {
        kind = 'stash', identifier = identifier,
        slots = opts and opts.slots or 50,
        maxweight = opts and opts.maxweight or 100000,
    })
    -- TriggerEvent returns nothing, so use an ack flag; warn if no UI resource set it.
    if Config.inventory.warnOnUnhandledOpen and not _G.__qbcoreInventoryUIHandled then
        print(("^3[qbcore:inventory]^7 stashOpen('%s') emitted qbcore:inventory:open but no UI resource "
            .. "handled it. Ship or bridge an inventory UI, or set Config.inventory.warnOnUnhandledOpen=false.")
            :format(identifier))
    end
    return true
end

local drops = {}   -- dropId -> { coords, items, created }
local nextDropId = 1

---@param coords table
---@param dropItems table
---@return integer dropId
function Core.inventory.dropCreate(coords, dropItems)
    local id = nextDropId
    nextDropId = nextDropId + 1
    drops[id] = { coords = coords, items = dropItems or {}, created = os.time() }
    TriggerClientEvent('qbcore:client:dropCreated', -1, id, coords)
    return id
end

---@param src integer
---@param dropId integer
---@param slot integer
---@param amount integer
---@return boolean, string|nil
function Core.inventory.dropTake(src, dropId, slot, amount)
    local drop = drops[dropId]
    if not drop then return false, 'no such drop' end
    local item = drop.items[slot]
    if not item then return false, 'empty slot' end
    amount = math.min(amount or item.amount, item.amount)
    local ok, err = Core.inventory.addItem(src, item.name, amount, nil, item.info)
    if not ok then return false, err end
    if item.amount <= amount then drop.items[slot] = nil else item.amount = item.amount - amount end
    if next(drop.items) == nil then
        drops[dropId] = nil
        TriggerClientEvent('qbcore:client:dropRemoved', -1, dropId)
    end
    return true
end

-- Uncollected drops otherwise live forever in memory for the life of the
-- process; periodically expire ones older than Config.inventory.dropTTL.
CreateThread(function()
    while true do
        Wait(Config.inventory.dropSweepInterval)
        local cutoff = os.time() - (Config.inventory.dropTTL / 1000)
        for id, drop in pairs(drops) do
            if drop.created and drop.created < cutoff then
                drops[id] = nil
                TriggerClientEvent('qbcore:client:dropRemoved', -1, id)
            end
        end
    end
end)
