RegisterNetEvent('kora_core:client:itemBox', function(itemDef, action, amount)
    local label = (itemDef and itemDef.label) or (itemDef and itemDef.name) or 'item'
    local verb = action == 'remove' and 'Removed' or 'Received'
    Kora.notify.send({ message = ('%s %dx %s'):format(verb, amount or 1, label), type = action == 'remove' and 'error' or 'success' })
end)

---Local inventory table from the mirror.
---@return table
function Core.inventory.getInventory()
    return Core.replication.getData({ 'items' }) or {}
end
