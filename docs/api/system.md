---
title: "Locales, pause menu and other client systems"
sidebar_position: 18
---


# Locales, pause menu and other client systems

## Server

Dependency supervisor: an optional, default-off server hook that restarts configured dependent resources when a provider resource starts. It exists for legacy scripts (such as qb-banking) that never re-register themselves when something they depend on restarts mid-session. It has no exports and no `Core` table; it only listens to `onResourceStart`.

Namespace: `exports.kora_core` · Source: `modules/dependencySupervisor/server.lua`

### How it works

When `Config.dependencySupervisor.enabled` is true and a resource named as a key of `Config.dependencySupervisor.map` starts, every listed dependent is restarted with the console command `restart <name>`, subject to two guards: the dependent must currently be `started` (so nothing fires on first boot and an operator-stopped resource stays stopped), and a per-dependent cooldown (`cooldownMs`) collapses restart storms to one restart. A dependent equal to the provider is never restarted. Output is printed as `[kora_core:dependencySupervisor] restarting <dependent> (dependency <provider> started)` or `skipping restart of <dependent> -- cooldown active (<n>ms remaining)`. Note that kora_core itself is a provider key in the default map: with the supervisor on, starting kora_core restarts qb-banking. Because the restart is the plain `restart` console command it bypasses any restart allow-list or protection layered on top of the rcon `ensure` path.

### Config.dependencySupervisor

Defined in config.lua. Review the ensure order and the blast radius before enabling it. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `enabled?` | boolean | Master switch. Default `false`. |
| `map?` | table&lt;string, string[]> | Provider resource name to the ordered list of dependents restarted after it starts. Empty lists are valid. Default: `kora_inventory = { 'qb-banking' }`, `kora_target = { 'qb-banking' }`, `PolyZone = {}`, `kora_core = { 'qb-banking' }`. |
| `cooldownMs?` | number (ms) | A dependent is not restarted again within this many ms of its own last supervisor restart. Default 15000 (also used if the key is missing). |

### Related guides

- [Config.dependencySupervisor](./configuration.md)
- [Legacy resource support](./compatibility.md)

## Client

Client-only systems: the per-player language selector, the pause-menu title and the vehicle air-control restriction.

Namespace: `exports.kora_core` · Source: `modules/locales/client.lua, modules/pausemenu/client.lua, modules/vehicleAirControl/client.lua`

### How it works

Only `openSelector` is exported; the other systems are driven by config and game events.

### Client config keys

Defined in config.lua; the locale key, `vehicleAirControl.disable` and `vehicleAirControl.exemptClasses` are also registered with kora_lib config (client scope). A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `Config.locales.defaultKey?` | string | Default key of the "Open language selector" keybind. Default `F10`. An empty string means no default key (the `/language` command still works). Read once when the resource starts; players can rebind it under Settings > Key Bindings > FiveM. |
| `Config.server.name?` | string | Pause-menu title. Default `Roleplay Server Name`. An empty string leaves the FiveM default title. |
| `Config.vehicleAirControl.disable?` | boolean | When true the driver of a non-exempt vehicle cannot steer, pitch or roll it while airborne. Default `true`. Read when the driver enters a vehicle and again on each worker loop iteration. |
| `Config.vehicleAirControl.exemptClasses?` | integer[] | Vehicle classes (`GetVehicleClass`) that keep air control. Default in code `{ 8, 13, 14, 15, 16, 21 }`: motorcycles, cycles, boats, helicopters, planes, trains. Remove 8 to make motorcycles lose air control. Read when the driver enters a vehicle. |

### Language selector commands and key

The selector can be opened with `/language`, or with a key. Core registers `+language` (opens the selector) and `-language` (does nothing) and binds `+language` with `RegisterKeyMapping('+language', 'Open language selector', 'keyboard', Config.locales.defaultKey or '')`. The plus/minus pair means only the key press opens the menu; releases and focus-regain events after alt-tab are ignored. The chosen language belongs to the FiveM client and is stored by kora_lib in KVP, not in PlayerData. The menu lists the languages from `Kora.locale.getLanguages()` with native names for 20 codes (`ar, da, de, en, es, et, fi, fr, is, it, ja, lt, nl, pt, pt-br, ro, sk, th, tr, vn`; any other code is shown as is) and marks the current one.

### Pause menu

At script load, when `Config.server.name` is a non-empty string, core calls `AddTextEntry('FE_THDR_GTAO', name)` so the standard GTA/FiveM pause menu shows the server name as its title. It does not replace the pause menu and adds no NUI. It is evaluated once, so a changed value needs a resource restart.

### Vehicle air control

There is no permanent loop. A worker thread exists only while the local ped is in the driver seat (-1) of a vehicle whose class is not exempt and `disable` is true. While the vehicle is not airborne it polls every 250 ms (so an upside-down car on the road can still be rocked back). While it is airborne (`IsEntityInAir` and not `IsVehicleOnAllWheels`) it calls `DisableControlAction(0, control, true)` every frame for controls 59, 60, 61, 62, 63 and 64 (steering, pitch and roll). It never blocks controls on the ground. The worker restarts on every seat or vehicle change, and the disable flag is also re-read in its loop (turning it off stops the worker), whereas `exemptClasses` is read at vehicle entry.

### Functions

Functions exported by this realm.

#### `exports.kora_core:openSelector()`

Opens the per-player language selector menu (`Kora.nui.openMenu`). On a choice it calls `Kora.locale.setLanguage` and shows a success notification (`Language set to <name>.`) or the error text from kora_lib. Cancelling does nothing. Ignored while a selector is already open.

**Parameters**



**Returns**

- **nil** — no return value in every case (cancel, success, failure, already open, or the menu call raising).

**Example**

```lua
-- from a settings menu button
RegisterNUICallback('openLanguage', function(_, cb)
    exports.kora_core:openSelector()
    cb('ok')
end)
```

**Representative console output**

```text
Menu "Language" with the available languages; picking one shows: Language set to Deutsch.
```

### Common use cases

- Giving players a language picker from your own settings screen via `openSelector`.
- Branding the pause menu with the server name.
- Stopping "perfect landings" from stunt jumps without disabling air control for bikes, boats and aircraft.

### Limits and related APIs

The selector depends on kora_lib's locale and NUI menu modules. The pause-menu title is applied once at load. Air control is restricted for the driver only; passengers are unaffected.

### Related guides

- [Config.locales, Config.vehicleAirControl, Config.server](./configuration.md)
- [Related client events](./events.md)

## Utilities and client systems (code-derived)

### Utilities (both realms)

| Export | Returns | Description |
| --- | --- | --- |
| `round(value, places)` | number | Rounds half up; `0` for non-numbers. |
| `trim(value)` | string | Strips surrounding whitespace; non-strings are returned unchanged. |
| `splitStr(str, delimiter)` | string array | Splits on a single (escaped) character. |
| `randomStr(length)` | string | Random uppercase letters. |
| `randomInt(length)` | string | Random digits, returned as a string (legacy behaviour). |
| `randomAlnum(length)` | string | Random uppercase letters and digits. |
| `deepClone(value)` | any | Recursive copy without metatables or cycle handling. |
| `pathGet(t, path)` | any | Value at a key-array path or `nil`. |
| `pathSet(t, path, value)` | any | Writes the value (creating tables) and returns the previous value. |

### Language selector (client)

`openSelector()` (also `/language` and the "Open language selector" key mapping,
default `Config.locales.defaultKey`) opens a kora_lib NUI menu listing
`Kora.locale.getLanguages()`. The choice is stored by kora_lib on the client (KVP),
not in PlayerData, so it survives character changes.

`shared/locale.lua` is a copy of qb-core's `Locale` class (with `extend`, `clear`,
`replace`, `locale`, `has`, `delete`, the flat `phrases` field, `fallbackLang`
and `warnOnMissing` defaulting to true). It is listed in the manifest `files` so a
`[compat]/qb-core` resource can serve `@qb-core/shared/locale.lua` to legacy
resources.

### Pause-menu title (client)

When `Config.server.name` is a non-empty string, the pause-menu header shows it.

### Vehicle air control (client)

With `Config.vehicleAirControl.disable` on, the driver of a vehicle whose class is
not in `exemptClasses` cannot use controls 59 to 64 (steer, pitch, roll) while the
vehicle is in the air and not on all wheels. Grounded vehicles, including upside
down ones, are never affected. Settings are read when the driver seat or vehicle
changes.

### Dependency supervisor (server)

When `Config.dependencySupervisor.enabled` is on, the start of a resource listed as
a key in `map` triggers `restart` of each listed dependent that is already started,
at most once per `cooldownMs` per dependent. It is meant for legacy resources (for
example `qb-banking`) that cannot re-register after kora_core, kora_inventory,
kora_target or PolyZone restart. See [Configuration](./configuration.md#configdependencysupervisor).
