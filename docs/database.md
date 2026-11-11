---
title: Database
sidebar_position: 7
---

# Database

kora_core has no SQL file to import. At boot it waits for kora_sql, then applies the
declarative schema in `modules/persistence/schema.lua` with `Kora.sql.ensureTables`.
That call creates missing tables, columns and indexes but never drops or reshapes
existing ones. Schema warnings are printed with the prefix `[kora_core:schema]`.
When everything is in place it prints `schema up to date.`, warms two prepared
statements and fires `kora_core:server:databaseReady`.

All tables use the `utf8mb4_unicode_ci` collation except
`kora_core_player_column_operations`, which uses the database default.

## players

One row per character.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | int unsigned, auto increment | Primary key. |
| `citizenid` | varchar(50) | Unique (`uk_players_citizenid`). |
| `license` | varchar(60) | Owner's primary identifier. |
| `cid` | tinyint unsigned, default 1 | Character slot. |
| `name` | varchar(255), default `unknown` | |
| `money` | longtext | JSON. |
| `charinfo` | longtext | JSON. |
| `job` | longtext | JSON (one-based grade level). |
| `gang` | longtext | JSON (one-based grade level). |
| `position` | longtext | JSON `x, y, z, h`. |
| `metadata` | longtext | JSON. |
| `inventory` | longtext, nullable | JSON of `PlayerData.items`. |
| `phone_number` | varchar(20), nullable | Unique (`uk_players_phone`). |
| `created_at` | timestamp | |
| `last_updated` | timestamp | Updated on change. |
| `deleted_at` | timestamp, nullable | Soft delete. Deleted rows are ignored everywhere. |
| `active_cid` | tinyint unsigned, generated | `cid` while not deleted, otherwise `NULL`. |

Indexes: `idx_players_license_deleted (license, deleted_at)`,
`idx_players_last_updated (last_updated)`, and the unique
`uk_players_license_active_cid (license, active_cid)`, which keeps one active
character per slot while letting a deleted slot be reused.

Saves are column-level `UPDATE`s through kora_sql's queue; `license` and `cid` are
never written after creation.

### Generated columns

With `Config.persistence.generatedColumns = true`, these virtual columns are added
to `players` so the data can be queried in SQL:

| Column | Expression |
| --- | --- |
| `cash` | `CAST(JSON_EXTRACT(money, '$.cash') AS SIGNED)` |
| `bank` | `CAST(JSON_EXTRACT(money, '$.bank') AS SIGNED)` |
| `job_name` | `JSON_UNQUOTE(JSON_EXTRACT(job, '$.name'))` |

with indexes `idx_players_bank` and `idx_players_job_name`. When the inventory
provider owns physical cash, the stored `cash` value is 0.

```sql
SELECT citizenid, name, bank FROM players WHERE job_name = 'police' ORDER BY bank DESC;
```

## player_identifiers

Identifiers seen per character, for alt and ban lookups.

| Column | Type | Notes |
| --- | --- | --- |
| `citizenid` | varchar(50) | Primary key part. |
| `kind` | varchar(20) | Primary key part (`license`, `discord`, `steam`, `ip`, ...). |
| `value` | varchar(128) | Without the `kind:` prefix. |
| `first_seen` | timestamp | |
| `last_seen` | timestamp | Updated on change. |

Index `idx_ident_lookup (kind, value)`.

## users

One row per license.

| Column | Type | Notes |
| --- | --- | --- |
| `license` | varchar(60) | Primary key. |
| `max_characters` | tinyint unsigned, nullable | Per-license slot override; `NULL` uses `Config.identity.maxCharacters`. |
| `discord` | varchar(50), nullable | Last Discord ID seen. Index `idx_users_discord`. |
| `created_at` | timestamp | |
| `last_seen` | timestamp | Updated on change. |

## inventories

Stash storage used by the fallback `stashGet`/`stashSet`.

| Column | Type | Notes |
| --- | --- | --- |
| `identifier` | varchar(64) | Primary key. |
| `kind` | varchar(20), default `stash` | |
| `items` | longtext | JSON. |
| `slots` | smallint unsigned, default 50 | |
| `maxweight` | int unsigned, default 100000 | |
| `updated_at` | timestamp | Updated on change. |

Index `idx_inventories_kind_updated (kind, updated_at)`.

## bans

Used by the legacy `QBCore.Functions.IsPlayerBanned` and `ExploitBan`. kora_core
does not check bans on connect by itself.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | int unsigned, auto increment | Primary key. |
| `name` | varchar(50), nullable | |
| `license` | varchar(60), nullable | With or without the `license:` prefix. |
| `discord` | varchar(50), nullable | |
| `ip` | varchar(50), nullable | |
| `reason` | text, nullable | |
| `expire` | int unsigned, nullable | UNIX time; `NULL` is permanent. |
| `bannedby` | varchar(255), default `LeBanhammer` | |

Indexes on `license`, `discord`, `ip` and `expire`.

## player_vehicles

Owned vehicles for `Core.garage` and garage/dealership resources.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | int unsigned, auto increment | Primary key; used for the `vehicleid` state bag. |
| `plate` | varchar(15) | Unique (`uk_vehicles_plate`). |
| `model` | varchar(60), nullable | Kora model name. Synced with `vehicle`. |
| `vehicle` | varchar(60), nullable | Stock column. |
| `citizenid` | varchar(50), nullable | Civilian owner. Index. |
| `job` | varchar(50), nullable | Fleet job. Index. |
| `state` | enum `out`, `garaged`, `impounded`, default `garaged` | Index. |
| `garage_id` | varchar(50), nullable | Synced with `garage`. |
| `fuel` | tinyint unsigned, default 100 | |
| `engine_health` | smallint unsigned, default 1000 | Synced with `engine`. |
| `body_health` | smallint unsigned, default 1000 | Synced with `body`. |
| `mods` | longtext, nullable | JSON vehicle properties. |
| `last_position` | longtext, nullable | JSON. |
| `impound_fee` | int unsigned, nullable | |
| `impound_lot` | varchar(50), nullable | |
| `impounded_at` | timestamp, nullable | |
| `created_at`, `last_updated` | timestamp | |
| `deleted_at` | timestamp, nullable | Soft delete. |
| `balance`, `paymentamount`, `paymentsleft`, `financetime` | int, default 0 | Finance columns shared with stock resources. |
| `license`, `hash`, `fakeplate`, `garage` | varchar(50), nullable | Stock columns. |
| `engine`, `body` | float, nullable | Stock columns. |
| `depotprice` | int, default 0 | Stock column. |
| `drivingdistance` | int, nullable | Stock column. |
| `status` | text, nullable | Stock column. |

Two triggers, `kora_core_player_vehicles_compat_insert` and
`kora_core_player_vehicles_compat_update`, keep the kora/stock column pairs in
sync. They are installed at boot only when missing. See
[`player_vehicles` compatibility](./vehicles-compat.md).

## kora_core_player_column_operations

Durable fences for provider column operations (see
[Player](./features/player.md#durable-provider-column-operations)).

| Column | Type | Notes |
| --- | --- | --- |
| `citizenid` | varchar(50) | Primary key part. |
| `column_name` | varchar(16) | Primary key part: `money`, `inventory` or `metadata`. |
| `resource` | varchar(64) | Owning provider. |
| `operation_key` | varchar(240) | |
| `fingerprint` | longtext | JSON of the fenced citizen IDs and columns. |
| `created_at` | timestamp | |

Index `idx_player_operation_owner (resource, operation_key)`.

## Requirements

The triggers and generated columns assume MariaDB 10.2 or later. kora_core reads
`information_schema.TRIGGERS` to detect existing triggers, so the database user
needs permission to create triggers.
