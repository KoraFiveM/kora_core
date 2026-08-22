-- compat/server/qb-inventory.lua -- the qb-inventory export + event surface,
-- backed by Core.inventory. Every export calls the internal impl directly (so
-- GetInvokingResource resolves to the real consumer), same rule as qb-core.lua.

if not (Config and Config.compat and Config.compat.provideQbInventory) then return end

local function provideExport(providedResource, exportName, func)
    AddEventHandler(('__cfx_export_%s_%s'):format(providedResource, exportName), function(setCB)
        setCB(func)
    end)
end

local registrations = {
    AddItem = function(src, name, amount, slot, info) return Core.inventory.addItem(src, name, amount, slot, info) end,
    RemoveItem = function(src, name, amount, slot) return Core.inventory.removeItem(src, name, amount, slot) end,
    GetItemByName = function(src, name) return Core.inventory.getItemByName(src, name) end,
    GetItemsByName = function(src, name) return Core.inventory.getItemsByName(src, name) end,
    GetItemBySlot = function(src, slot) return Core.inventory.getItemBySlot(src, slot) end,
    GetItemCount = function(src, name) return Core.inventory.getItemCount(src, name) end,
    HasItem = function(src, items, amount) return Core.inventory.hasItem(src, items, amount) end,
    ClearInventory = function(src, keep) return Core.inventory.clearInventory(src, keep) end,
    SetInventory = function(src, items) return Core.inventory.setItems(src, items) end,
    GetFreeSlot = function(src) return Core.inventory.getFreeSlot(src) end,
    CanAddItem = function(src, name, amount) return Core.inventory.canCarry(src, name, amount) end,
    GetFreeWeight = function(src) local w, m = Core.inventory.getWeight(src); return m - w end,
    CreateUsableItem = function(name, cb) return Core.inventory.createUseable(name, cb) end,
    OpenInventory = function(src, identifier, opts) return Core.inventory.stashOpen(src, identifier, opts) end,
    GetInventory = function(src) local p = CoreInternal.player.handle(src); return p and p.PlayerData.items or {} end,
}

for exportName, func in pairs(registrations) do
    provideExport('qb-inventory', exportName, func)
    -- qb-inventory historically also lived under the resource name 'qb-inventory'
    -- AND a few forks used 'ps-inventory'/'lj-inventory'; provide the core name
    -- only -- others can be added if a server needs them.
end

-- Legacy inventory events.
RegisterNetEvent('QBCore:Server:UseItem', function(item)
    -- Some resources fire this to trigger a useable; forward to the model.
    local src = source
    if type(item) == 'table' and item.name then Core.inventory.useItem(src, item.name) end
end)

RegisterNetEvent('inventory:server:SetInventoryData', function(itemsTable)
    Core.inventory.setItems(source, itemsTable)
end)
