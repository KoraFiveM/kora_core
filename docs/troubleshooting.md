---
title: Troubleshooting
sidebar_position: 11
---

# Troubleshooting

| Console message or symptom | Meaning and fix |
| --- | --- |
| `[kora_core:schema] still waiting for kora_sql; schema setup will resume automatically.` | kora_sql is not ready yet. Ensure `kora_sql` starts before kora_core and that the connection string is valid. |
| `[kora_core:schema] schema setup failed: ...` | `ensureTables` failed; check database permissions and the error text. Player loads will fail until the schema exists. |
| `[kora_core:schema] vehicle sync trigger setup failed: ...` | The database user cannot create triggers, or the database is not MariaDB 10.2 or later. Stock and Kora `player_vehicles` columns will not stay in sync. |
| `kora_core export collision: '<name>' ...` at boot | Two modules define the same public function name. This is a code error in a modified copy of kora_core. |
| `[kora_core:inventory] kora_inventory is not started ...; using the temporary built-in legacy fallback.` | The inventory provider is not running. Start it before resources that use inventory APIs, or set `Config.inventory.allowLegacyFallback = false` to get explicit errors instead. |
| Inventory calls return `nil` and `kora_inventory is started but is missing required kora_core gateway export '<name>'` | The provider version does not implement the gateway; update it. |
| `[kora_core:inventory] stashOpen('<id>') emitted kora_core:inventory:open but no UI resource handled it.` | No inventory UI handles the event; ship one or set `Config.inventory.warnOnUnhandledOpen = false`. |
| `[kora_core:money] transaction tax skipped: banking provider <name> is not running` | Tax is enabled but `Config.money.tax.provider` is stopped; transactions continue untaxed. |
| Money or item calls fail with `player data is busy` | A durable provider operation (banking or inventory) or a logout save holds the column. Retry after it completes. |
| Money calls fail with `physical cash provider unavailable` | The inventory provider registered physical cash and then stopped. Restart it; kora_core does not fall back to the ledger. |
| `[kora_core:rep] <resource> wrote PlayerData directly via the legacy event ...` | A resource fired `QBCore:Player:SetPlayerData` on the client. The write is temporary; change that resource to use server APIs. |
| `[kora_core:qb-core-bridge] SetPlayerData('<key>', ...) targets an unknown root key ...` | A legacy resource wrote a root key that has no column; the value is kept in memory only. Disable with `Config.compat.warnOnUnknownRoot = false`. |
| `[kora_core:qb-core-bridge] TriggerCallback("<name>") timed out waiting for a server reply` | No server handler answered within `Config.compat.callbackTimeoutMs`. |
| `[kora_core] rejected client metadata write from <src> for key '<key>'` | A client tried to set a metadata key not in `Config.compat.clientMetadataKeys`. |
| `[kora_core:commands] /<name> is already registered by another resource; keeping that one.` | A default qb-core command name is already taken; the other resource's command stays. |
| `[kora_core:qbx-facade] a real qbx_core/qbx_vehicles resource exists; the qbx facade stays OFF ...` | Remove the real resource or keep the facade off. |
| `[kora_core:dependencySupervisor] restarting <dependent> ...` | The supervisor restarted a dependent after its provider started (only when enabled). |
| `[Core.jobs] on-duty counts drifted, corrected.` | The periodic index rebuild found a mismatch and fixed it. Repeated drift points at a resource writing `job` in an unusual way. |
| Character never spawns on a bare server | The default flow needs no UI. If a UI resource calls `claimUI()` but does not drive selection, nothing happens; check that UI. |
| `QBCore:Client:OnPlayerLoaded` never fires | `Config.compat.deferClientPlayerLoaded` is on and the login path never sends `QBCore:Server:OnPlayerLoaded`. Turn it off. |
