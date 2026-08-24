-- Core.consumables (server realm) -- the generic item-effect bridge. Reads
-- an item's shared `.effect` table (set by whichever resource registered the
-- item, e.g. qbambulance's bandage, qbdrugs' every drug item) and plays it
-- back via QB.status/QB.fx when the item is used -- ONE hook services every
-- effect-bearing item in the whole framework, so a new drug/medical item
-- needs only a data entry, never new game logic.
--
-- This layer is COSMETIC/STATUS ONLY and never denies an item use -- real
-- gameplay effects (actually healing HP, etc) stay in each job resource's own
-- Core.inventory.createUseable handler, which runs independently of this hook.
--
-- Two real integration constraints, both confirmed by reading qbinventory's
-- own source (not assumed):
--   1. qbcore is a DEPENDENCY of qbinventory, so FXServer starts qbcore
--      first -- registering the hook must be deferred to onResourceStart,
--      never called unconditionally at load time, or it errors against a
--      not-yet-running qbinventory.
--   2. qbinventory's runHooks passes (payload, src) to a 'usingItem' hook --
--      relies on that fix (see qbinventory/server.lua's runHooks) rather
--      than parsing src back out of payload.inventoryId.

local registered = false

local function onUsingItem(payload, src)
    if not payload or not payload.itemName or not src then return true end

    local def = Core.registry.getShared('items', payload.itemName)
        or Core.registry.getShared('weapons', payload.itemName)
    if not def or not def.effect then return true end

    local ok, err = QB.status.apply(src, payload.itemName, def.effect)
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
    if GetResourceState('qbinventory') ~= 'started' then return end

    -- Deliberately NOT gated on `registered` -- this must re-run every time
    -- qbinventory (re)starts. A qbinventory restart wipes ITS hook table
    -- (fresh resource instance), so the hook we registered before the
    -- restart is gone from qbinventory's side even though `registered`
    -- would still say true on our side. Re-registering here is always
    -- correct: either qbinventory has no hook yet (fresh boot / just
    -- restarted) and this adds it, or it's a duplicate onResourceStart
    -- fire for an instance we already registered against, which is a
    -- harmless no-op re-add (qbinventory's registerHook just appends).
    local ok = pcall(function() exports.qbinventory:registerHook('usingItem', onUsingItem) end)
    if not ok then
        -- Native qbinventory compatibility before the ox-style lowercase
        -- alias was added. Keep rolling-upgrade startup safe.
        ok = pcall(function() exports.qbinventory:RegisterHook('usingItem', onUsingItem) end)
    end
    if ok then registered = true end
end

register() -- covers qbinventory already running when qbcore starts (a restart, not a fresh boot)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == 'qbinventory' then register() end
end)

AddEventHandler('onResourceStop', function(resourceName)
    -- qbinventory stopping tears down its own hook table with it, so our
    -- last registration no longer exists on the other side. Reflect that
    -- in isRegistered() and let the onResourceStart handler above put it
    -- back the moment qbinventory comes back up.
    if resourceName == 'qbinventory' then registered = false end
end)

---@return boolean
function Core.consumables.isRegistered()
    return registered
end
