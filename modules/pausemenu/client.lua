local name = Config.server and Config.server.name

if type(name) == 'string' and name ~= '' then
    AddTextEntry('FE_THDR_GTAO', name)
end
