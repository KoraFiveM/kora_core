-- compat/shared/coreobject.lua -- assembles the QBCore table skeleton and the
-- QBCore.Shared.* helper functions once, for BOTH realms. The realm-specific
-- sections (Functions, Player, per-player method tables, event wiring) are
-- filled in by compat/{server,client}/qb-core.lua, which load after this.
--
-- QBCore is a plain global in qbcore's own VM. It is handed to other resources
-- verbatim via exports['qb-core']:GetCoreObject() (server/client qb-core.lua),
-- so its shape must match legacy qb-core exactly.

QBCore = QBCore or {}
QBCore.Functions = QBCore.Functions or {}
QBCore.Player = QBCore.Player or {}
QBCore.Players = QBCore.Players or {}        -- src -> QBPlayer (kept in sync by the server compat)
QBCore.Shared = QBCore.Shared or {}
QBCore.Commands = QBCore.Commands or {}
QBCore.Config = QBCore.Config or {}

-- Shared string/number helpers, delegated to Core.util so there is one
-- implementation. Legacy names (PascalCase) preserved.
QBCore.Shared.Round     = function(v, p) return Core.util.round(v, p) end
QBCore.Shared.Trim      = function(v) return Core.util.trim(v) end
QBCore.Shared.SplitStr  = function(s, d) return Core.util.splitStr(s, d) end
QBCore.Shared.RandomStr = function(n) return Core.util.randomStr(n) end
QBCore.Shared.RandomInt = function(n) return Core.util.randomInt(n) end

-- The Shared.* data tables (Items/Vehicles/Jobs/Gangs/Weapons) are the
-- MATERIALISED registry tables. They are wired in the realm files (after the
-- registries exist); a metatable here makes an early read return the live table
-- once it's available rather than nil, and keeps the reference stable.
setmetatable(QBCore.Shared, getmetatable(QBCore.Shared) or {
    __index = function(t, k)
        local map = { Items = 'items', Vehicles = 'vehicles', Jobs = 'jobs', Gangs = 'gangs', Weapons = 'weapons' }
        local regName = map[k]
        if regName and CoreInternal and CoreInternal.registry and CoreInternal.registry.registries[regName] then
            local mat = CoreInternal.registry.registries[regName].materialised
            rawset(t, k, mat)   -- cache the stable reference
            return mat
        end
        return nil
    end,
})

-- Debug helper (legacy QBCore.Debug prints a table).
function QBCore.Debug(tbl, indent)
    indent = indent or 0
    local pad = string.rep('  ', indent)
    if type(tbl) ~= 'table' then print(pad .. tostring(tbl)); return end
    for k, v in pairs(tbl) do
        if type(v) == 'table' then
            print(('%s%s:'):format(pad, tostring(k)))
            QBCore.Debug(v, indent + 1)
        else
            print(('%s%s: %s'):format(pad, tostring(k), tostring(v)))
        end
    end
end

function QBCore.ShowError(res, msg) print(('^1[%s] %s^7'):format(res or 'qbcore', msg or '')) end
function QBCore.ShowSuccess(res, msg) print(('^2[%s] %s^7'):format(res or 'qbcore', msg or '')) end
