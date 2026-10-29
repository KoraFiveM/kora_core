-- Only this resource owns player.<id> -> qbcore.txadmin. Manual grants use
-- separate principals, so revoking txAdmin access cannot remove them.
if GetConvar('txAdminServerMode', 'false') ~= 'true' then return end

local grants = {}
local pending = {}
local stopped = false
local lastWarning

local function warn(message)
    if lastWarning == message then return end
    lastWarning = message
    print(('^3[qbcore:txadmin]^7 %s'):format(message))
end

local function revoke(src)
    if not grants[src] then return end
    grants[src] = nil
    ExecuteCommand(('remove_principal player.%d qbcore.txadmin'):format(src))
    TriggerEvent('qbcore:server:txAdminPermissionChanged', src)
end

local function clearGrants()
    pending = {}
    for src in pairs(grants) do revoke(src) end
end

local function checkPlayer(src)
    src = tonumber(src)
    if stopped or not src or src < 1 or src % 1 ~= 0 or src == math.huge then return end
    if not GetPlayerName(src) then return end

    revoke(src)
    local request = {}
    pending[src] = request

    local ok = pcall(function()
        exports.monitor:qbcoreCheckFullAdmin(src, function(allowed, reason)
            -- A permission change, disconnect or new session invalidates the
            -- old request even if its HTTP response arrives after the change.
            if pending[src] ~= request then return end
            pending[src] = nil
            if stopped or not GetPlayerName(src) then return end

            if reason then warn(reason) else lastWarning = nil end
            if allowed ~= true then return end

            grants[src] = true
            ExecuteCommand(('add_principal player.%d qbcore.txadmin'):format(src))
            TriggerEvent('qbcore:server:txAdminPermissionChanged', src)
        end)
    end)

    if not ok then
        pending[src] = nil
        warn('txAdmin bridge unavailable. Install the qbcore bridge before a full server startup.')
    end
end

AddEventHandler('playerJoining', function()
    checkPlayer(source)
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    pending[src] = nil
    revoke(src)
end)

AddEventHandler('txAdmin:events:adminsUpdated', function(onlineAdminIDs)
    if GetInvokingResource() ~= 'monitor' then return end
    clearGrants()
    if type(onlineAdminIDs) ~= 'table' then
        warn('txAdmin supplied an invalid online admin list; automatic access was removed.')
        return
    end

    local checked = {}
    for _, id in pairs(onlineAdminIDs) do
        local src = tonumber(id)
        if src and src >= 1 and src < math.huge and src % 1 == 0 and not checked[src] then
            checked[src] = true
            checkPlayer(src)
        end
    end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, src in ipairs(GetPlayers()) do checkPlayer(src) end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() and resource ~= 'monitor' then return end
    stopped = true
    clearGrants()
end)
