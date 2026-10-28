-- dependencySupervisor (server realm) -- qb-banking is an
-- untouchable legacy scripts that never re-register themselves when a
-- resource they depend on (kora_core, kora_inventory, kora_target, PolyZone) restarts
-- mid-session. Since it can't self-heal, this restarts it instead,
-- driven entirely by Config.dependencySupervisor (disabled by default -- this
-- is new behavior with no existing convention to lean on).
--
-- Mechanism: Config.dependencySupervisor.map[provider] lists resources that
-- should be restarted whenever `provider` (re)starts. Restarting uses the
-- standard ExecuteCommand('restart <name>') idiom (see kora_admin's
-- /restartresource command, resources/kora_admin/server/commands/privileged.lua).
-- Two guards keep this safe:
--   * a dependent is only restarted if it is CURRENTLY 'started'. This is
--     what prevents firing on first boot -- server.cfg's ensure order means
--     a dependent that hasn't started yet has state 'missing' (or similar),
--     never 'started' -- and it also skips a dependent the operator
--     deliberately stopped.
--   * a per-resource cooldown (Config.dependencySupervisor.cooldownMs) blocks
--     restarting the SAME resource again within the window, so a restart
--     storm (e.g. two providers in a dependent's chain starting close
--     together) collapses to one restart instead of looping.
--
-- No `Core.dependencySupervisor` table -- this module is purely reactive
-- (same pattern as modules/consumables/server.lua's onUsingItem hook); it has
-- nothing worth exporting.

local lastRestartAt = {}   -- resourceName -> GetGameTimer() at the last restart WE issued

AddEventHandler('onResourceStart', function(resourceName)
    local cfg = Config.dependencySupervisor
    if not cfg or not cfg.enabled then return end

    local dependents = cfg.map and cfg.map[resourceName]
    if not dependents then return end

    local cooldownMs = cfg.cooldownMs or 15000
    local now = GetGameTimer()

    for _, dependent in ipairs(dependents) do
        -- Never restart the provider that just triggered this, even if it
        -- somehow lists itself as its own dependent.
        if dependent ~= resourceName then
            if GetResourceState(dependent) == 'started' then
                local last = lastRestartAt[dependent]
                if not last or (now - last) >= cooldownMs then
                    lastRestartAt[dependent] = now
                    print(('[qbcore:dependencySupervisor] restarting %s (dependency %s started)'):format(dependent, resourceName))
                    ExecuteCommand(('restart %s'):format(dependent))
                else
                    print(('[qbcore:dependencySupervisor] skipping restart of %s -- cooldown active (%dms remaining)')
                        :format(dependent, cooldownMs - (now - last)))
                end
            end
        end
    end
end)
