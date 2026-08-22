-- Flattens Core.<module>.<fn> into flat exports: exports.qbcore:<fn>(...).
-- Runs LAST in each realm (it lives in client_scripts/server_scripts, never
-- shared_scripts, because shared always loads before the realm-specific block,
-- and it must see the fully-populated Core table).
--
-- The public namespace is FLAT: module tables (Core.player, Core.money, ...)
-- are internal organisation only. A name defined in two modules is programmer
-- error and aborts at boot -- never in production traffic -- per this
-- codebase's `assert for programmer error` convention.

-- Internal cross-file helpers live on the `CoreInternal` table (never walked
-- here), so only curated public functions sit on Core.<module>. As a second
-- guard, a function whose name starts with '_' is treated as internal and NOT
-- exported, even on a Core.<module> table.
local seen = {}

for moduleName, moduleTable in pairs(Core) do
    if type(moduleTable) == "table" then
        for fnName, fn in pairs(moduleTable) do
            if type(fn) == "function" and fnName:sub(1, 1) ~= "_" then
                assert(not seen[fnName], ("qbcore export collision: '%s' is defined in both Core.%s and Core.%s")
                    :format(fnName, seen[fnName], moduleName))
                seen[fnName] = moduleName
                exports(fnName, fn)
            end
        end
    elseif type(moduleTable) == "function" then
        -- A bare function attached directly to Core (rare) exports under its
        -- own name too.
        assert(not seen[moduleName], ("qbcore export collision: '%s'"):format(moduleName))
        seen[moduleName] = "<root>"
        exports(moduleName, moduleTable)
    end
end
