# kora_core agent guide

## What this is
The framework core: player management, money, jobs/gangs, metadata, inventory,
shared registries, and full backwards compatibility with legacy QBCore. Built ON
kora_lib (reusable helpers live in `Kora.*`, not reimplemented here) and persisted
through kora_sql. Every public function is a flat export: `exports.kora_core:getPlayer(src)`.

## The three load-bearing ideas

### 1. The single mutation funnel — `Core.player.setPath`
Every change to a player's data — money, job, metadata, an inventory slot —
routes through `Core.player.setPath(src, path, value)`. In one place it: writes
`PlayerData` at the path, marks the owning DB column dirty, queues a client
delta, and fires matching `onChange` subscribers. `Core.money.addMoney`,
`Core.jobs.setJob`, `Core.inventory.addItem` etc. are thin wrappers over it. This
is why dirty-tracking and delta replication are automatic and consistent: there
is exactly one write path.

`CoreInternal.player.COLUMN_FOR` maps a PlayerData root key to its DB column.
`license` and `cid` are deliberately absent — they are immutable after creation
and must never enter a write set (the two-unique-key corruption hazard in the
schema).

### 2. Delta replication, not full-blob resend
Legacy qb-core resends the ENTIRE PlayerData blob to a client on every field
change. `Core.replication` sends only deltas (`{ p = keyArray, v = value }`),
coalesced per player per frame via a single `SetTimeout(0)`. A per-player `seq`
lets the client detect a dropped batch and request a rate-limited resync. The
legacy `QBCore:Player:SetPlayerData` event is still fired — but CLIENT-SIDE from
the already-mirrored local table, so it never crosses the network. Full compat,
near-zero cost.

### 3. Minimum-write persistence
`Core.persistence` writes only what changed: dirty-column tracking + a
byte-identical-JSON gate mean a save encodes each column at most once and only
when it actually changed. A reverted change writes nothing. Position is sampled
server-side (OneSync) at flush time and only persisted past a movement epsilon.
Dirty rows across all players flush in ONE `Kora.sql.enqueueMany` — one Lua→JS
boundary crossing — which kora_sql then coalesces into a handful of batched upserts.

## Export namespace discipline
`build/finalise.lua` flattens `Core.<module>.<fn>` to `exports.kora_core:<fn>` and
ASSERTS there are no cross-module name collisions (a boot-time programmer-error
check). Two rules keep the flat namespace clean:
- Internal cross-file helpers live on the private `CoreInternal.<module>` table,
  which finalise never walks (e.g. `CoreInternal.player.freshData`,
  `CoreInternal.registry.apply`).
- A function on a `Core.<module>` table whose name starts with `_` is treated as
  internal and NOT exported (e.g. `Core.persistence._adopt`,
  `Core.replication._queueOp`). Use this for lifecycle plumbing that must be
  callable across module files but is not public API.
Run the collision check by loading all server modules + `build/finalise.lua`
under the mocks (see `test/`); it lists every exported name.

## Compat design
`compat/` follows the same rules as `kora_target/client/compat/ox-target.lua`:
- `exports['qb-core']:GetCoreObject()` returns the `QBCore` table via the
  `__cfx_export_` identity hijack; `provide 'qb-core'` alone does not do this.
- Every compat function calls the internal `Core.*` impl DIRECTLY, never
  `exports.kora_core:fn()`, so `GetInvokingResource()` inside resolves to the real
  external consumer — load-bearing for owner-tracked registrations (commands,
  useables, registry entries, subscriptions).
- `QBCore.Shared.Items/Vehicles/Jobs/Gangs/Weapons` are legacy-only live views.
  New code always calls `Core.registry.getShared`/`allShared` or
  `Kora.shared.get`/`all`; never index or capture those compatibility maps.
- Client helper functions (`GetClosestPed`, `Draw3DText`, `Progressbar`, ...) are
  thin forwards to `Kora.*`, not reimplementations.
- `compat/server/qbx.lua` is an OPT-IN (`kora:qbxFacade`) `qbx_core`/`qbx_vehicles` export+event facade for stock ox_inventory; it registers nothing while off, and it never publishes a resource/`provide` named qbx_core. See `docs/qbx-facade.md`.
- `compat/server/qb-commands.lua` registers qb-core's 20 default commands through `QBCore.Commands.Add`
  (flag `Config.compat.defaultCommands`, docs/default-commands.md). Handlers validate every arg because
  `QBCore:CallCommand` passes client input, use `Core.money`/`Core.jobs`, and audit through `Core.logging`.
- Physical-cash mirror (modules/money/server.lua): while kora_inventory owns the cash account the ledger is 0, and
  the real balance is overlaid onto the compat view (`Core.money._mirrorOverlay`) and onto outgoing replication
  ops/snapshots (`CoreInternal.player.mirrorOps/mirrorSnapshot`). It is refreshed on `Core.money` changes and
  `qbcore:server:inventoryChanged`, never persisted, never polled.
- Deliberately NOT `provide 'qb-multicharacter'`: that compat is event-level only,
  and hijacking the name would disable a real character-select UI.

## Shared registries and `@kora_core/init.lua`
The `/ideas` requirement — shared items/vehicles/jobs lists, runtime-updatable,
tracked across resources — is met by `Core.registry` (server-authoritative) plus
`@kora_core/init.lua`, which installs a LIVE-updating local mirror as `Kora.shared.*`
into any consumer's VM (same rawset trick as `@kora_sql/init.lua`; kora_lib's `Kora`
metatable has only `__index`). A registration broadcasts a delta; the mirror
patches locally and fires in-VM `onChange` handlers — so a change made in one
resource is seen, with handlers firing, in every resource that uses the list.
Each registry carries an epoch so a kora_core restart re-seeds mirrors rather than
drifting.

## Durability caveat (be honest in docs)
The coalescing save bounds worst-case data loss to `Config.persistence.interval`
(60s) on a hard crash. Clean paths — player drop, logout, txAdmin shutdown,
resource stop — flush immediately. FXServer gives no guarantee an `onResourceStop`
yield completes, so this BOUNDS loss, it does not eliminate it.

## Conventions
Follows kora_lib's: `fx_version 'cerulean'`, `lua54 'yes'`, explicit non-globbed load
order with reasoning comments, four-space indent, heavy LuaLS annotations,
`(value, errorString)` returns on fallible functions, `assert` for programmer
error / `print` for runtime misbehaviour. Every module folder has `AGENTS.md` +
`docs.md`; adding a module requires adding its `test/smoke/<module>.lua` in the
same change. Tests load one realm at a time to avoid the same-name-across-realms
collision (see kora_lib AGENTS.md).
