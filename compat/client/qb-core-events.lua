-- compat/client/qb-core-events.lua -- client-side legacy event glue. The delta
-- apply in modules/replication/client.lua already fires
-- QBCore:Player:SetPlayerData / OnJobUpdate / OnGangUpdate locally; this file
-- handles the remaining inbound admin/command events.

RegisterNetEvent('QBCore:Command:TeleportToCoords', function(x, y, z)
    local ped = PlayerPedId()
    SetEntityCoords(ped, x + 0.0, y + 0.0, z + 0.0, false, false, false, false)
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    -- Ensure the mirror requests a snapshot if it somehow hasn't yet.
    if Core.replication.getData() == nil then Core.replication.requestResync() end
end)
