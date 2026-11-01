-- dependencySupervisor (server realm) -- qb-banking is an
-- untouchable legacy scripts that never re-register themselves when a
-- resource they depend on (kora_core, kora_inventory, kora_target, PolyZone) restarts
-- mid-session. Since it can't self-heal, this restarts it instead,
-- driven entirely by Config.dependencySupervisor (disabled by default -- this
-- is new behavior with no existing convention to lean on).
--
-- Config.dependencySupervisor.map[provider] lists resources restarted (via
-- ExecuteCommand('restart <name>')) whenever `provider` (re)starts. Two guards:
--   * a dependent is only restarted if it is CURRENTLY 'started' -- no firing on
--     first boot (ensure order), and an operator-stopped resource stays stopped.
--   * a per-resource cooldown (cooldownMs) collapses restart storms to one restart.
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
