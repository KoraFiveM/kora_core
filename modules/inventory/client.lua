RegisterNetEvent('kora_core:client:itemBox', function(itemDef, action, amount)
    local label = (itemDef and itemDef.label) or (itemDef and itemDef.name) or Kora.lang('Inventory.item')
    local removed = action == 'remove'
    local key = removed and 'Inventory.removed' or 'Inventory.received'
    Kora.bridge.sendNotify({
        message = Kora.lang(key, amount or 1, label),
        type = removed and 'error' or 'success',
    })
end)

---Local inventory table from the mirror.
---@return table
function Core.inventory.getInventory()
    return Core.replication.getData({ 'items' }) or {}
end
