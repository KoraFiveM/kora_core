-- The standard GTA/FiveM pause menu reads this text-entry key for its title.
-- Registering it client-side makes the configured server identity visible without
-- replacing the native pause menu or adding another NUI layer.

local name = Config.server and Config.server.name

if type(name) == 'string' and name ~= '' then
    AddTextEntry('FE_THDR_GTAO', name)
end
