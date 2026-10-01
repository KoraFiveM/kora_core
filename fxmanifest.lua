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
--
-- NOTE: `provide` covers exactly two things -- another resource's
-- `dependency 'qb-core'` check, and (together with the __cfx_export_ identity
-- hijack in compat/*) `exports['qb-core']:Fn()` calls. It does NOT make a
-- legacy consumer's `'@qb-core/shared/locale.lua'` FILE include resolve:
-- FiveM resolves an '@name/path' include against a real resource literally
-- named `name`, via a loader that never consults provide/exports. That is what
-- [compat]/qb-core exists for -- see its fxmanifest.lua and [compat]/README.md.
provide 'qb-core'

-- Both are shared_script (not shared_scripts) so they resolve BEFORE the table
-- below, qblib strictly before qbsql: '@qbsql/init.lua' extends and asserts on
-- the QB table '@qblib/init.lua' creates. '@qbcore/init.lua' is NOT included
-- here -- it's for OTHER resources to pull QB.shared.* into their own VM. It
-- must still be listed in `files` below so FiveM can resolve that @-import.
shared_script '@qblib/init.lua'
shared_script '@qbsql/init.lua'

files {
    'init.lua' -- '@qbcore/init.lua' -- shared registry mirror for consumers
    , 'shared/locale.lua' -- '@qb-core/shared/locale.lua' -- real qb-core's Locale class, for compat consumers
}

-- Explicit, never globbed. A `modules/**/shared.lua` glob expands in
-- alphabetical FOLDER order, which would put 'inventory' before 'registry' and
-- 'jobs' before 'player' -- both wrong. Order rationale:
--   config.lua          everything below reads Config.*
--   build/initiate.lua  creates the `Core` table the modules attach to
--   shared/*.lua        plain QBCoreSeed.* data, no Core dependency
--   modules/util        registry/player/inventory all call Core.util.*
--   modules/registry    runtime-registers defaults + owns indexed getter storage
--   ...rest             player/inventory shared shapes
--   compat/shared       builds the QBCore skeleton (needs Core.util + registries)
shared_scripts {
    'config.lua',
    'build/initiate.lua',
    'shared/locale.lua',
    'shared/items.lua',
    'shared/vehicles.lua',
    'shared/jobs.lua',
    'shared/gangs.lua',
    -- Canonical qb-core records fill gaps without replacing the purpose-built
    -- definitions above. The merge converts keyed data into registry seeds.
    'shared/upstream/items.lua',
    'shared/upstream/jobs.lua',
    'shared/upstream/gangs.lua',
    'shared/upstream/merge.lua',
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
--   dispatch/paycheck  need Core.jobs' index (dispatch also needs money for
--                      nothing itself, but paycheck does)
--   development        owns ephemeral per-player dev-mode state
--   needs              needs Core.metadata + Core.development
--   permissions/commands/logging
--   garage/consumables  no framework ordering need beyond what's already
--                       loaded above; grouped here rather than earlier
--   jail                needs Core.commands (registers /jail, /unjail) and
--                       Core.permissions (via addCommand's permission check)
--   dependencySupervisor  reactive-only (onResourceStart), no dependency on
--                         anything above; OFF by default via Config
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
    'modules/dispatch/server.lua',
    'modules/paycheck/server.lua',
    'modules/metadata/server.lua',
    'modules/development/server.lua',
    'modules/needs/server.lua',
    'modules/inventory/server.lua',
    'modules/inventory/gateway.lua',
    'modules/transaction/server.lua',
    'modules/multichar/server.lua',
    'modules/permissions/server.lua',
    'modules/commands/server.lua',
    'modules/logging/server.lua',
    'modules/garage/server.lua',
    'modules/consumables/server.lua',
    'modules/jail/server.lua',
    'modules/dependencySupervisor/server.lua',
    'compat/server/qb-core.lua',
    'compat/server/qb-core-events.lua',
    'compat/server/qb-multicharacter.lua',
    'compat/server/qb-spawn.lua',
    'build/finalise.lua'
}

client_scripts {
    'modules/garage/client.lua',
    'modules/registry/client.lua',
    'modules/pausemenu/client.lua',
    'modules/replication/client.lua',
    'modules/player/client.lua',
    'modules/development/client.lua',
    'modules/needs/client.lua',
    'modules/jail/client.lua',
    'modules/jobs/client.lua',
    'modules/inventory/client.lua',
    'modules/multichar/client.lua',
    'modules/commands/client.lua',
    'modules/locales/client.lua',
    'compat/client/qb-core.lua',
    'compat/client/qb-core-events.lua',
    'build/finalise.lua'
}
