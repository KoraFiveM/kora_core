# Dispatch module

## Overview
Job-aware alert fan-out. A job resource (police, ambulance, tow, mechanic, …) calls `Core.dispatch.alert` to push a structured alert to every on-duty member of one or more jobs. Server only. Functions are defined on `Core.dispatch` and exported flat as `exports.kora_core:<fn>`.

## API

### `Core.dispatch.alert(payload)`
Sends `payload` to every on-duty player of each job in `payload.jobs` via `kora_core:client:dispatchAlert`.

#### Parameters
- `payload: table`
  - `jobs: string[]` — required, non-empty. Job names to notify (on-duty members only).
  - `title: string | nil`
  - `message: string | nil`
  - `coords: table | nil` — `{x,y,z}` or `vector3`/`vector4`.
  - `code: string | nil`
  - `blip: table | nil` — `{sprite, color, scale, duration}`, consumed by the receiving job resource's own client code.
  - `sound: string | nil`
  - `radius: number | nil`
  - `data: table | nil` — freeform, passed through untouched.

#### Returns
- `integer` — Number of distinct players notified.

#### Example
```lua
exports.kora_core:alert({
    jobs = { 'police' },
    title = '10-80',
    message = 'Robbery in progress',
    coords = coords,
    code = '10-80',
})
```

## Events

### `kora_core:server:dispatchAlert(payload, recipientCount)` — server
Fired once per alert, after the fan-out. This is the hook for a resource that
**owns** dispatch presentation (a dispatch/MDT UI with a call log) rather than
merely receiving one alert as a recipient.

Such a resource cannot key off the client push: `kora_core:client:dispatchAlert`
reaches every recipient, so each of their clients would ask the server to record
the same incident once per recipient. This fires exactly once.

### `kora_core:client:dispatchAlert(payload)` — client
The per-recipient push, delivered only to on-duty members of the requested jobs.

## Notes
- **Rendering is not this module's job.** kora_core ships no NUI/UI of its own — a job resource's own client code decides how to present the `kora_core:client:dispatchAlert` push (blips, sound, notify).
- **Legacy compatibility, gated by `Config.dispatch.legacyEvents`.** When enabled, a `police` alert also fires `police:server:policeAlert` and `police:client:policeAlert` to each recipient; `ambulance`/`ems` alerts also fire `hospital:client:ambulanceAlert`. Both legacy client events receive `(message or title, coords)`, not the full payload table.
- **Dedup, not multiplied sends.** A recipient matching more than one job in `payload.jobs` is still only notified once.
