-- Export smoke test -- loads the server scripts in the exact manifest order and
-- runs finalise.lua. This keeps Core's flat export namespace honest: a public
-- helper accidentally left on two module tables must fail here before startup.

local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua')
mocks.install()

dofile('config.lua')
dofile('build/initiate.lua')
dofile('shared/items.lua'); dofile('shared/vehicles.lua'); dofile('shared/jobs.lua')
dofile('shared/gangs.lua'); dofile('shared/weapons.lua'); dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua')
dofile('modules/player/shared.lua')
dofile('modules/inventory/shared.lua')
dofile('compat/shared/coreobject.lua')

dofile('modules/registry/server.lua')
dofile('modules/identity/server.lua')
dofile('modules/replication/server.lua')
dofile('modules/persistence/server.lua')
dofile('modules/persistence/migrate.lua')
dofile('modules/player/server.lua')
dofile('modules/money/server.lua')
dofile('modules/jobs/server.lua')
dofile('modules/metadata/server.lua')
dofile('modules/inventory/server.lua')
dofile('modules/multichar/server.lua')
dofile('modules/permissions/server.lua')
dofile('modules/commands/server.lua')
dofile('modules/logging/server.lua')
dofile('compat/server/qb-core.lua')
dofile('compat/server/qb-core-events.lua')
dofile('compat/server/qb-inventory.lua')
dofile('compat/server/qb-multicharacter.lua')

local flattened = {}
_G.exports = function(name, fn)
    h.assertTrue(flattened[name] == nil, ('%s exported twice'):format(name))
    flattened[name] = fn
end

h.test('finalise flattens the complete server surface without collisions', function()
    dofile('build/finalise.lua')
    h.assertTrue(type(flattened.deleteCharacter) == 'function', 'deleteCharacter is exported')
end)

h.report('exports')
