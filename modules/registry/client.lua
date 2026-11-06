-- Core.registry (client realm) -- the RECEIVE side. The server is authoritative;
-- the client mirrors the registries so getter reads work client-side with zero
-- network cost per read. Legacy QBCore.Shared maps are derived compatibility
-- views. On resource start the client requests a full snapshot, then applies deltas.

local RI = CoreInternal.registry

RI.create('items', 'name')
RI.create('vehicles', 'model')
RI.create('jobs', 'name')
RI.create('gangs', 'name')
RI.create('weapons', 'name')
RI.create('locations', 'key')

RegisterNetEvent('qbcore:registry:snapshotAll', function(all)
    for name, payload in pairs(all) do
        if RI.registries[name] then RI.reseed(name, payload.records, payload.epoch) end
    end
    TriggerEvent('qbcore:registry:synced')
end)

RegisterNetEvent('qbcore:registry:delta', function(name, action, key, record, epoch)
    local r = RI.registries[name]
    if not r then return end
    if epoch and epoch ~= r.epoch and action ~= 'remove' then
        -- Epoch gap: mirror is stale, pull a fresh snapshot rather than apply a
        -- delta onto stale data.
        TriggerServerEvent('qbcore:registry:requestSnapshot')
        return
    end
    local previous = Core.registry.getShared(name, key)
    if action == 'remove' then RI.remove(name, key) else RI.apply(name, key, record) end
    RI.dispatch(name, action, key, record, previous)
end)

-- Subscriptions work client-side too (local, in-VM) for HUD/UI code.
function Core.registry.onSharedChange(name, handler)
    local r = RI.registries[name]
    if not r then return nil, 'no such registry' end
    local subId = r.nextSubId
    r.nextSubId = r.nextSubId + 1
    r.subscribers[subId] = { resource = GetInvokingResource() or GetCurrentResourceName(), handler = handler }
    return subId
end

function Core.registry.offSharedChange(name, subId)
    local r = RI.registries[name]
    if r then r.subscribers[subId] = nil end
end

-- Client register is refused -- the server owns the registries.
function Core.registry.registerShared(name, key)
    print(("^3[kora_core:registry]^7 client-side registerShared('%s','%s') refused -- register on the server."):format(tostring(name), tostring(key)))
    return false, 'client-side registration is not supported'
end

CreateThread(function()
    Wait(0)
    TriggerServerEvent('qbcore:registry:requestSnapshot')
end)
