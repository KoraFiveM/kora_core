# tools/ox_items

Offline generator: kora_core item registry -> stock ox_inventory `data/items.lua`
(Q-D8: kora_core is the source of truth, the ox file is generated). Plain Lua 5.4,
no DB, no network, read-only on its inputs.

    lua5.4 tools/ox_items/generate.lua [--out out/ox_items/items.lua] --ox-dir <path-to-ox_inventory>
                                       [--scan <dir>]... [--resource-items <dir>]... [--no-default-scan] [--image-url]
                                       [--use-export resource.fn] [--strict]

`out/` is gitignored. Outputs next to `--out`: `items.lua`, `mapping.json` (QB -> ox
names, for the migrator), `report.json`, `report.md`.

## How the registry is built
The generator loads `shared/items.lua`, `shared/upstream/items.lua`, the repo's own
`shared/upstream/merge.lua` and `shared/weapons.lua` into a private Lua environment, then
dedupes by name (last wins), exactly like `Core.registry.registerShared`. `--root` can point
at another tree with the same `shared/` layout (the test fixture does).

## Items resources register at runtime (`--resource-items`)
Some resources (e.g. kora_cards) do not ship their items in the registry seed: they define
`Config.items` in `config.lua` and call `Kora.shared.register('items', name, def)` at boot, only
for names the registry lacks. `--resource-items <resource-dir>` (repeatable) loads that
`config.lua` in a private sandbox and reads `Config.items`; the items then go through the same
field mapping and collision policy as registry items.
- Sandbox: `io`/`os`/`require` are absent; any other unknown global (`lib`, `Kora`, `locale`,
  `GetConvar`, `vec3`, ...) is an inert callable stub, so unrelated config code cannot break loading.
  A config that errors or has no `Config.items` table fails the run.
- Registry wins (matches runtime): a name already in the registry (or from an earlier
  `--resource-items`) is not taken from the resource and is listed as an overlap. `money`/`black_money`
  keep ox semantics; weapon items stay excluded. Both are listed per resource.
- `report.json` `resourceItems` / `report.md` list, per resource, the items it contributed and the
  overlap/reserved/weapon names. Pass the resource dir to `--scan` as well, or its own
  `AddItem` calls are not scanned.

## Field mapping
| kora | ox |
|---|---|
| name, label, weight | key, `label`, `weight` |
| `unique = true` | `stack = false` |
| `shouldClose = false` | `close = false` (ox default is true) |
| description | `description` (omitted if empty) |
| image | `client.image` (omitted when it equals `<name>.png`; `--image-url` prefers `imageUrl`) |
| useable | nothing by default: ox's qbx bridge asks the framework (`CanUseItem`). With `--use-export r.fn`: `server.export` plus `consume = 0` |

## Weapons and ammo (Q-D9)
`weapon_*` / `type = 'weapon'` items and ammo items are NOT emitted; stock `data/weapons.lua`
owns them. `mapping.json` holds `weapon_pistol -> WEAPON_PISTOL` and ammo name -> ox ammo item.
Ammo is mapped per GTA ammo type by majority vote over the stock weapons using it; the report
lists the alternatives (e.g. `.45`/`.50` pistols) so the migrator or a human can refine.
Weapons without a stock counterpart (`weapon_unarmed`, `weapon_stungun_mp`, ...) and ammo
without one (`taser_cartridge`, ...) are listed; unmapped ammo is emitted as a plain item.
Only the stock file is read, for names; nothing is copied.

## Collisions with stock `data/items.lua` (Q-D10)
- Kora wins for label, weight, stack, close, description, image (the generated file replaces
  the stock one wholesale). E.g. `water`, `lockpick`, `phone`, `radio`, `parachute`, `bandage`.
- `money` and `black_money` keep ox semantics: emitted label-only like stock (framework keeps
  bank; stock `inventory:accounts '["money"]'`). Kora's `cash` item is mapped to `money`
  (`aliases` in `mapping.json`), not emitted.
- Stock-only demo items (`testburger`, `scrapmetal`) are NOT carried over; they are listed.
  Every stock item that ox code names (`armour`, `bandage`, `clothing`, `garbage`,
  `identification`, `mastercard`, `paperbag`, `parachute`, `phone`, and the `init.lua` loot-table
  items `burger`, `sprunk`, `mustard`, `panties`) is defined in the kora registry
  (`shared/items.lua`); the report warns if one is ever missing. `money`/`black_money` are
  covered by the generator's reserved entries.

## Missing-item scan (heuristic)
Scans `*.lua` (excluding `test/`) under the kora_core checkout the script lives in, plus any
extra directories given with a repeatable `--scan <dir>` (e.g. `--scan <path-to-kora_inventory>
--scan <path-to-kora_consumables>`; `--no-default-scan` skips the checkout) for literal names in
`AddItem/RemoveItem/HasItem/GetItemCount/CreateUseableItem/...` calls. Dynamic names and shop/crafting tables are invisible,
so an empty list is necessary, not sufficient. ox_inventory silently drops unknown items on load:
the list must be empty before go-live (`--strict` exits 2 otherwise).
