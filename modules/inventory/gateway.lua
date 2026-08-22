-- Core.inventory gateway (server realm). qbcore remains the owner of the
-- PlayerData.items persistence/replication funnel, while qbinventory becomes
-- the inventory authority when it is available. Keeping this boundary here
-- means all legacy QBCore Player.Functions calls continue to work without
-- qbcore claiming the qb-inventory resource identity itself.

local II = CoreInternal.inventory

-- Capture the existing funnel-backed implementation before replacing its public
-- methods with the provider gateway. It remains an explicit temporary fallback
-- for safe upgrades; qbinventory is never allowed to fall through partially.
local legacy = {}
for name, fn in pairs(Core.inventory) do
    if type(fn) == 'function' and name:sub(1, 1) ~= '_' then
        legacy[name] = fn
    end
end
II.legacy = legacy

local providerName = Config.inventory.provider or 'qbinventory'
local fallbackDepth = 0
local warnedUnavailable = false

local function providerState()
    if type(GetResourceState) ~= 'function' then return 'missing' end
    return GetResourceState(providerName)
end

local function callProvider(name, ...)
    local resourceExports = exports[providerName]
    local fn = resourceExports and resourceExports[name]
    if type(fn) ~= 'function' then
        return nil, ("qbinventory is started but is missing required qbcore gateway export '%s'"):format(name)
    end

    local results = table.pack(pcall(fn, resourceExports, ...))
    if not results[1] then
        return nil, ("qbinventory gateway export '%s' failed: %s"):format(name, tostring(results[2]))
    end
    return table.unpack(results, 2, results.n)
end

local function unavailable(name)
    local state = providerState()
    if state == 'started' then
        return nil, ("qbinventory is started but is missing required qbcore gateway export '%s'"):format(name)
    end

    if not Config.inventory.allowLegacyFallback then
        return nil, ("qbinventory is not started (state: %s); set Config.inventory.allowLegacyFallback=true for a temporary "
            .. "qbcore legacy fallback, or ensure qbinventory before resources that use inventory APIs."):format(state)
    end

    if not warnedUnavailable then
        warnedUnavailable = true
        print(("^3[qbcore:inventory]^7 qbinventory is not started (state: %s); using the temporary built-in "
            .. "legacy fallback. Start qbinventory to enable authoritative inventory sessions and live updates."):format(state))
    end
    return false
end

local function callLegacy(name, ...)
    -- Legacy methods call sibling Core.inventory functions. The depth guard keeps
    -- those internal calls inside the captured implementation instead of routing
    -- back through this gateway. It is only used while qbinventory is absent.
    fallbackDepth = fallbackDepth + 1
    local results = table.pack(pcall(legacy[name], ...))
    fallbackDepth = fallbackDepth - 1
    if not results[1] then error(results[2], 0) end
    return table.unpack(results, 2, results.n)
end

for name in pairs(legacy) do
    Core.inventory[name] = function(...)
        if fallbackDepth > 0 then return legacy[name](...) end

        if providerState() == 'started' then
            return callProvider(name, ...)
        end

        local ok, err = unavailable(name)
        if ok == nil then return nil, err end
        return callLegacy(name, ...)
    end
end
