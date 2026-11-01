-- Core.consumables (server realm) -- the generic item-effect bridge. Reads
-- an item's shared `.effect` table (set by whichever resource registered the
-- item, e.g. kora_ambulance's bandage, kora_drugs' every drug item) and plays it
-- back via Kora.status/Kora.fx when the item is used -- ONE hook services every
-- effect-bearing item in the whole framework, so a new drug/medical item
-- needs only a data entry, never new game logic.
--
-- This layer is COSMETIC/STATUS ONLY and never denies an item use -- real
-- gameplay effects (actually healing HP, etc) stay in each job resource's own
-- Core.inventory.createUseable handler, which runs independently of this hook.
--
-- Integration constraints:
--   1. kora_core starts before kora_inventory, so hook registration is deferred to
--      onResourceStart, never done unconditionally at load time.
--   2. kora_inventory's runHooks passes (payload, src) to a 'usingItem' hook; src is
--      not parsed back out of payload.inventoryId.

local registered = false

local function onUsingItem(payload, src)
    if not payload or not payload.itemName or not src then return true end

    local def = Core.registry.getShared('items', payload.itemName)
        or Core.registry.getShared('weapons', payload.itemName)
    if not def or not def.effect then return true end

    local ok, err = Kora.status.apply(src, payload.itemName, def.effect)
    if not ok then
        print(('[qbcore:consumables] failed to apply effect for %s: %s'):format(payload.itemName, tostring(err)))
    end

    local effect = def.effect
    if effect.hungerDelta then Core.metadata.incrementMetaData(src, 'hunger', effect.hungerDelta, 0, 100) end
    if effect.thirstDelta then Core.metadata.incrementMetaData(src, 'thirst', effect.thirstDelta, 0, 100) end
    if effect.stressDelta then Core.metadata.incrementMetaData(src, 'stress', effect.stressDelta, 0, 100) end

    return true -- never deny -- this hook is cosmetic/status-only, see file header
end

local function register()
    if not Config.consumables.enabled then return end
    if GetResourceState('kora_inventory') ~= 'started' then return end

    -- Deliberately NOT gated on `registered`: a kora_inventory restart wipes its hook
    -- table, so re-register every time (a duplicate re-add is harmless).
    local ok = pcall(function() exports.kora_inventory:registerHook('usingItem', onUsingItem) end)
    if not ok then
        -- Native kora_inventory compatibility before the ox-style lowercase
        -- alias was added. Keep rolling-upgrade startup safe.
        ok = pcall(function() exports.kora_inventory:RegisterHook('usingItem', onUsingItem) end)
    end
    if ok then registered = true end
end

register() -- covers kora_inventory already running when kora_core starts (a restart, not a fresh boot)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == 'kora_inventory' then register() end
end)

AddEventHandler('onResourceStop', function(resourceName)
    -- kora_inventory's hook table dies with it; reflect that in isRegistered().
    if resourceName == 'kora_inventory' then registered = false end
end)

---@return boolean
function Core.consumables.isRegistered()
    return registered
end
