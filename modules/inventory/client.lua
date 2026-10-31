-- Core.inventory (client realm) -- minimal client glue. The server owns the
-- model; the client only surfaces the item-pickup box and reads the local
-- inventory from the mirror. No NUI is shipped (see AGENTS.md).

RegisterNetEvent('qbcore:client:itemBox', function(itemDef, action, amount)
    -- Default to a kora_lib notification; a UI resource can also listen for this.
    local label = (itemDef and itemDef.label) or (itemDef and itemDef.name) or 'item'
    local verb = action == 'remove' and 'Removed' or 'Received'
    Kora.notify.send({ message = ('%s %dx %s'):format(verb, amount or 1, label), type = action == 'remove' and 'error' or 'success' })
end)

---Local inventory table from the mirror.
---@return table
function Core.inventory.getInventory()
    return Core.replication.getData({ 'items' }) or {}
end
