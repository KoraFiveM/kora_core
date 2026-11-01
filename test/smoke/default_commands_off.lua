-- Config.compat.defaultCommands = false registers none of the stock commands.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); mocks.install()
dofile('config.lua')
dofile('shared/items.lua'); dofile('shared/jobs.lua'); dofile('shared/gangs.lua')
dofile('shared/vehicles.lua'); dofile('shared/weapons.lua'); dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua'); dofile('modules/registry/server.lua')
dofile('modules/player/shared.lua')
dofile('modules/replication/server.lua'); dofile('modules/persistence/server.lua')
dofile('modules/player/server.lua'); dofile('modules/money/server.lua')
dofile('modules/jobs/server.lua'); dofile('modules/metadata/server.lua')
dofile('modules/permissions/server.lua'); dofile('modules/commands/server.lua')
dofile('compat/shared/coreobject.lua')
dofile('compat/server/qb-core.lua')

h.test('the flag defaults to enabled', function()
    h.assertEqual(Config.compat.defaultCommands, true)
end)

h.test('defaultCommands = false registers nothing', function()
    Config.compat.defaultCommands = false
    dofile('compat/server/qb-commands.lua')
    h.assertEqual(next(QBCore.Commands.List), nil)
    h.assertEqual(#Core.commands.listCommands(), 0)
end)

h.report('default_commands_off')
