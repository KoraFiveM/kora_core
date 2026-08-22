-- compat/server/qb-core-events.lua -- inbound legacy net events a third-party
-- resource might trigger on the server, wired to the internal Core.* functions.
-- Outbound legacy events (PlayerLoaded, OnJobUpdate, OnMoneyChange, ...) are
-- fired at their source inside the modules; this file only handles the inbound
-- side + a couple of admin command relays.

local PI = CoreInternal.player

RegisterNetEvent('QBCore:Server:SetMetaData', function(key, value)
    local src = source
    Core.metadata.setMetaData(src, key, value)
end)

RegisterNetEvent('QBCore:ToggleDuty', function()
    local src = source
    local job = Core.jobs.getJob(src)
    if job then Core.jobs.setJobDuty(src, not job.onduty) end
end)

RegisterNetEvent('QBCore:Server:Logout', function()
    Core.player.logout(source)
end)

-- Registered so the name is dispatchable at all -- FXServer silently drops a
-- client TriggerServerEvent for a net event name no resource has
-- RegisterNetEvent'd server-side, so real qb-spawn/qb-multicharacter's own
-- TriggerServerEvent('QBCore:Server:OnPlayerLoaded') (and any third-party
-- AddEventHandler for it) would otherwise be a complete no-op here. No Core.*
-- action needed: Core.player.login's adopt() already fires the equivalent
-- PlayerLoaded/OnPlayerLoaded signals, at character-select time rather than
-- at spawn-confirm time like upstream -- a pre-existing timing difference,
-- out of scope to rearchitect for this compat shim.
RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function() end)

-- UpdateObject: legacy resources call this to grab a fresh core object handle
-- server-side. It re-broadcasts the object to the caller via the client event.
RegisterNetEvent('QBCore:Server:UpdateObject', function()
    -- No-op server-side: the object is a live table already; nothing to refresh.
end)

-- Admin command relays (teleport / spawn) that legacy admin menus fire.
RegisterNetEvent('QBCore:Command:TeleportToCoords', function(x, y, z)
    TriggerClientEvent('QBCore:Command:TeleportToCoords', source, x, y, z)
end)
RegisterNetEvent('QBCore:CallCommand', function(name, args)
    ExecuteCommand(('%s %s'):format(name, table.concat(args or {}, ' ')))
end)
