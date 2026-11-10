local registered = false

local function onUsingItem(payload, src)
    if not payload or not payload.itemName or not src then return true end

    local def = Core.registry.getShared('items', payload.itemName)
        or Core.registry.getShared('weapons', payload.itemName)
    if not def or not def.effect then return true end

    local ok, err = Kora.status.apply(src, payload.itemName, def.effect)
    if not ok then
        print(('[kora_core:consumables] failed to apply effect for %s: %s'):format(payload.itemName, tostring(err)))
    end

    local effect = def.effect
    if effect.hungerDelta then Core.metadata.incrementMetaData(src, 'hunger', effect.hungerDelta, 0, 100) end
    if effect.thirstDelta then Core.metadata.incrementMetaData(src, 'thirst', effect.thirstDelta, 0, 100) end
    if effect.stressDelta then Core.metadata.incrementMetaData(src, 'stress', effect.stressDelta, 0, 100) end

    return true
end

local function register()
    if not Config.consumables.enabled then return end
    if GetResourceState('kora_inventory') ~= 'started' then return end

    local ok = pcall(function() exports.kora_inventory:registerHook('usingItem', onUsingItem) end)
    if not ok then
        ok = pcall(function() exports.kora_inventory:RegisterHook('usingItem', onUsingItem) end)
    end
    if ok then registered = true end
end

register()

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == 'kora_inventory' then register() end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == 'kora_inventory' then registered = false end
end)

---@return boolean
function Core.consumables.isRegistered()
    return registered
end
