-- compat/server/qb-core-events.lua -- inbound legacy net events a third-party
-- resource might trigger on the server, wired to the internal Core.* functions.
-- Outbound legacy events (PlayerLoaded, OnJobUpdate, OnMoneyChange, ...) are
-- fired at their source inside the modules; this file only handles the inbound
-- side + a couple of admin command relays.

local PI = CoreInternal.player

RegisterNetEvent('QBCore:Server:SetMetaData', function(key, value)
    local src = source
    if type(key) ~= 'string' or Config.compat.clientMetadataKeys[key] ~= true then
        print(("^3[qbcore]^7 rejected client metadata write from %s for key '%s'"):format(src, tostring(key)))
        return
    end
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

-- QBCore:UpdatePlayer -- the stock qb-hud fires this on a timer to have the
-- server tick hunger/thirst down and persist. Our `needs` module ALREADY owns
-- hunger/thirst decay on its own timer, so we deliberately do NOT decrement here
-- (that would double-tick); we honor the event's other duties -- refresh the
-- stock HUD with the current values and persist -- so a stock qb-hud keeps
-- working without fighting our decay loop.
RegisterNetEvent('QBCore:UpdatePlayer', function()
    local src = source
    local handle = PI.handle(src)
    if not handle then return end
    local md = handle.PlayerData.metadata or {}
    TriggerClientEvent('hud:client:UpdateNeeds', src, md.hunger or 100, md.thirst or 100)
    Core.persistence.saveNow(handle)
end)

-- Server open/close (admin menus). Guarded by the same 'admin' permission real
-- qb-core uses; on close, kick every connected player without the whitelist
-- permission. QBCore + QBCore.Config.Server are assembled in
-- compat/server/qb-core.lua, which loads before this file.
RegisterNetEvent('QBCore:Server:CloseServer', function(reason)
    local src = source
    if not QBCore.Functions.HasPermission(src, 'admin') then
        QBCore.Functions.Kick(src, 'You do not have permission to do that.')
        return
    end
    reason = reason or 'No reason specified'
    QBCore.Config.Server.Closed = true
    QBCore.Config.Server.ClosedReason = reason
    for k in pairs(QBCore.Players) do
        if not QBCore.Functions.HasPermission(k, QBCore.Config.Server.WhitelistPermission) then
            QBCore.Functions.Kick(k, reason)
        end
    end
end)
RegisterNetEvent('QBCore:Server:OpenServer', function()
    local src = source
    if not QBCore.Functions.HasPermission(src, 'admin') then
        QBCore.Functions.Kick(src, 'You do not have permission to do that.')
        return
    end
    QBCore.Config.Server.Closed = false
end)

-- Admin command relays (teleport / spawn) that legacy admin menus fire.
RegisterNetEvent('QBCore:Command:TeleportToCoords', function(x, y, z)
    TriggerClientEvent('QBCore:Command:TeleportToCoords', source, x, y, z)
end)
RegisterNetEvent('QBCore:CallCommand', function(name, args)
    local src = source
    if type(name) ~= 'string' or name == '' then return end

    -- ExecuteCommand runs in server-console context (source 0), which bypasses
    -- every per-player ACE check a command's own handler would normally do --
    -- so the permission check has to happen here, against the *invoking*
    -- player, before we ever call it.
    local allowed = false
    for _, cmd in ipairs(Core.commands.listCommands()) do
        if cmd.name == name then
            -- Same check qbcore's own command wrapper uses (Core.commands.addCommand).
            allowed = Core.permissions.hasPermission(src, cmd.permission)
            break
        end
    end
    if not allowed then
        -- Not a command registered through the qbcore/qblib wrapper (a raw
        -- native or another resource's RegisterCommand) -- fall back to
        -- FiveM's own command-ACE convention rather than defaulting to allow.
        allowed = IsPlayerAceAllowed(src, 'command.' .. name)
    end

    if not allowed then
        print(("^3[qbcore]^7 QBCore:CallCommand denied: src=%s has no permission to run '%s'"):format(src, name))
        return
    end

    ExecuteCommand(('%s %s'):format(name, table.concat(args or {}, ' ')))
end)
