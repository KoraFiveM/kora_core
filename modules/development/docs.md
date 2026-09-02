# Development mode

Development mode is an ephemeral, per-player convenience activated by a server
export:

```lua
local ok, err = exports.qbcore:setDevMode(source, true)
local enabled = exports.qbcore:isDevMode(source)
exports.qbcore:setDevMode(source, false)
```

For that player while enabled:
- the local player ped is invincible;
- stamina is refilled every frame, so sprinting never drains it;
- passive hunger and thirst decay does not start or tick;
- zero-value hunger/thirst updates do not apply needs damage; and
- walking uses `Config.development.walkSpeed` every frame (`1.75` by default).

The mode does not overwrite hunger/thirst metadata. Explicit changes from
consumables, scripts, or admin tools still work; only core's passive decay and
damage are suppressed. Disabling through the export restores the normal ped
move rate and damage state immediately. State is cleared on disconnect or a
qbcore restart and is never persisted.

Client resources can read the local state with `exports.qbcore:isDevMode()`.
Activation remains server-only so the calling resource can enforce its own
permission policy.
