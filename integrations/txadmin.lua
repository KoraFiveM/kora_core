-- Installed into monitor, after its own server scripts. Its private intercom
-- token stays in txAdmin's runtime and is never exported to kora_core.
if not TX_SERVER_MODE then return end

local coreGeneration = 0
AddEventHandler('onResourceStop', function(resource)
    if resource == 'kora_core' then coreGeneration = coreGeneration + 1 end
end)

exports('qbcoreCheckFullAdmin', function(src, callback)
    if GetInvokingResource() ~= 'kora_core' then return false end
    if type(src) ~= 'number' or src < 1 or src % 1 ~= 0 or src == math.huge
        or not GetPlayerName(src) then
        callback(false)
        return false
    end

    if type(TX_LUACOMHOST) ~= 'string' or TX_LUACOMHOST == 'invalid'
        or type(TX_LUACOMTOKEN) ~= 'string' or TX_LUACOMTOKEN == 'invalid'
        or TX_LUACOMTOKEN == 'removed' then
        callback(false, 'txAdmin authentication is unavailable; use a full server startup.')
        return false
    end

    local generation = coreGeneration
    PerformHttpRequest('http://' .. TX_LUACOMHOST .. '/auth/self', function(status, body)
        -- A stopped kora_core VM no longer owns a callable function reference.
        if generation ~= coreGeneration then return end
        if status ~= 200 or type(body) ~= 'string' then
            callback(false, 'txAdmin permission lookup failed.')
            return
        end

        local ok, response = pcall(json.decode, body)
        if not ok or type(response) ~= 'table' then
            callback(false, 'txAdmin returned an invalid authentication response.')
            return
        end
        if response.logout then
            -- Ordinary players are expected to have no txAdmin account.
            local reason = response.reason ~= 'nui_admin_not_found'
                and 'txAdmin rejected the player authentication.' or nil
            callback(false, reason)
            return
        end
        if response.error or type(response.name) ~= 'string' or response.name == ''
            or type(response.permissions) ~= 'table' then
            callback(false, 'txAdmin returned an invalid authentication response.')
            return
        end

        -- txAdmin normalizes master accounts to all_permissions too.
        for _, permission in ipairs(response.permissions) do
            if permission == 'all_permissions' then
                callback(true)
                return
            end
        end
        callback(false)
    end, 'GET', '', {
        ['Content-Type'] = 'application/json',
        ['X-TxAdmin-Token'] = TX_LUACOMTOKEN,
        ['X-TxAdmin-Identifiers'] = table.concat(GetPlayerIdentifiers(src), ','),
    })
    return true
end)
