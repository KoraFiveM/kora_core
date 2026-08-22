fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbcore'
author 'Jamie'
version '1.0.0'
description 'Player/framework core built on qblib, persisted through qbsql'

dependency 'qblib'
dependency 'qbsql'

-- Only identities this resource actually implements. Deliberately NOT providing
-- 'qb-multicharacter' -- that compat is event-level only, and hijacking the name
-- would silently disable a real character-select UI a server wants to keep.
provide 'qb-core'

-- Both are shared_script (not shared_scripts) so they resolve BEFORE the table
-- below, qblib strictly before qbsql: '@qbsql/init.lua' extends and asserts on
-- the QB table '@qblib/init.lua' creates. '@qbcore/init.lua' is NOT included
-- here -- it's for OTHER resources to pull QB.shared.* into their own VM.
shared_script '@qblib/init.lua'
shared_script '@qbsql/init.lua'

-- Explicit, never globbed. A `modules/**/shared.lua` glob expands in
-- alphabetical FOLDER order, which would put 'inventory' before 'registry' and
-- 'jobs' before 'player' -- both wrong. Order rationale:
--   config.lua          everything below reads Config.*
--   build/initiate.lua  creates the `Core` table the modules attach to
--   shared/*.lua        plain QBCoreSeed.* data, no Core dependency
--   modules/util        registry/player/inventory all call Core.util.*
--   modules/registry    ingests the seeds + owns the Shared.* materialised tables
--   ...rest             player/inventory shared shapes
--   compat/shared       builds the QBCore skeleton (needs Core.util + registries)
shared_scripts {
    'config.lua',
    'build/initiate.lua',
    'shared/items.lua',
    'shared/vehicles.lua',
    'shared/jobs.lua',
    'shared/gangs.lua',
    'shared/weapons.lua',
    'shared/locations.lua',
    'modules/util/shared.lua',
    'modules/registry/shared.lua',
    'modules/player/shared.lua',
    'modules/inventory/shared.lua',
    'compat/shared/coreobject.lua'
}

-- Server order is load-bearing:
--   registry     creates the authoritative registries + ingests seeds
--   identity     identifier extraction (player.create uses it)
--   users        per-license account rows (character-slot cap override);
--                player.createCharacter calls Core.users.getMaxCharacters
--   replication  player.adopt registers into it
--   persistence  player.login/create call adopt()/insertNew(); migrate.lua runs here
--   player       the funnel + lifecycle (depends on replication + persistence)
--   money/jobs/metadata/inventory  wrappers over the funnel
--   inventory/gateway              delegates inventory operations to qbinventory
--                                  when it is running; keeps the legacy engine as
--                                  a staged-rollout fallback only
--   permissions/commands/logging
--   compat/*     LAST (before finalise) so it calls Core.* directly and
--                GetInvokingResource() resolves to the real external consumer
--   build/finalise.lua  absolutely last -- flattens Core.<module>.<fn> to exports
server_scripts {
    'modules/registry/server.lua',
    'modules/identity/server.lua',
    'modules/users/server.lua',
    'modules/replication/server.lua',
    'modules/persistence/server.lua',
    'modules/persistence/migrate.lua',
    'modules/player/server.lua',
    'modules/money/server.lua',
    'modules/jobs/server.lua',
    'modules/metadata/server.lua',
    'modules/inventory/server.lua',
    'modules/inventory/gateway.lua',
    'modules/multichar/server.lua',
    'modules/permissions/server.lua',
    'modules/commands/server.lua',
    'modules/logging/server.lua',
    'compat/server/qb-core.lua',
    'compat/server/qb-core-events.lua',
    'compat/server/qb-multicharacter.lua',
    'compat/server/qb-spawn.lua',
    'build/finalise.lua'
}

client_scripts {
    'modules/registry/client.lua',
    'modules/replication/client.lua',
    'modules/player/client.lua',
    'modules/jobs/client.lua',
    'modules/inventory/client.lua',
    'modules/multichar/client.lua',
    'modules/commands/client.lua',
    'compat/client/qb-core.lua',
    'compat/client/qb-core-events.lua',
    'build/finalise.lua'
}
