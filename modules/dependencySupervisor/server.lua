local lastRestartAt = {}

AddEventHandler('onResourceStart', function(resourceName)
    local cfg = Config.dependencySupervisor
    if not cfg or not cfg.enabled then return end

    local dependents = cfg.map and cfg.map[resourceName]
    if not dependents then return end

    local cooldownMs = cfg.cooldownMs or 15000
    local now = GetGameTimer()

    for _, dependent in ipairs(dependents) do
        if dependent ~= resourceName then
            if GetResourceState(dependent) == 'started' then
                local last = lastRestartAt[dependent]
                if not last or (now - last) >= cooldownMs then
                    lastRestartAt[dependent] = now
                    print(('[kora_core:dependencySupervisor] restarting %s (dependency %s started)'):format(dependent, resourceName))
                    ExecuteCommand(('restart %s'):format(dependent))
                else
                    print(('[kora_core:dependencySupervisor] skipping restart of %s -- cooldown active (%dms remaining)')
                        :format(dependent, cooldownMs - (now - last)))
                end
            end
        end
    end
end)
