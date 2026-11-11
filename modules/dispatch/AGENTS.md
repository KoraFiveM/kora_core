# dispatch module guide

## Purpose
Job-aware alert fan-out for job resources (police/ambulance dispatch, tow, mechanic, …) to push a structured alert to every on-duty member of one or more jobs, plus optional legacy event compatibility for police/ambulance. Server only. kora_core ships no NUI/UI of its own (see compat/AGENTS.md) — rendering (blips/sound/notify) is the receiving job resource's own client code.

## Public API
- `Core.dispatch.alert(payload)` — `payload = { jobs, title?, message?, coords?, code?, blip?, sound?, radius?, data? }`. Sends `kora_core:client:dispatchAlert` to every on-duty member of each job in `payload.jobs`, deduped. Returns the recipient count.

## Implementation notes
- **Recipients via `Core.jobs.getPlayersByJob`'s O(1) index**, one lookup per job in `payload.jobs`, not a scan of all players.
- **No native multi-target send.** `TriggerClientEvent` is looped per recipient — a `-1` broadcast + client-side filter would leak alert content (coords, message) to every connected client, not just the on-duty roster it's meant for.
- **Dedup by `src`.** A player who somehow matches more than one requested job (not possible today — `PlayerData.job` is single-valued — but `getPlayersByJob` is called once per job) is only notified once.
- **Legacy job events, gated by `Config.dispatch.legacyEvents`.** `LEGACY_JOB_EVENTS` maps `police`/`ambulance`/`ems` to the legacy client events (`police:client:policeAlert`, `hospital:client:ambulanceAlert`). `police` additionally fires a same-server `police:server:policeAlert` `TriggerEvent`; ambulance/EMS has no established local-event convention to mirror, so only the client push is legacy-preserved for it.

## Best practices
- Send one alert per incident, not per recipient — `Core.dispatch.alert` already fans out.
- Treat `payload.data` as the extension point for anything beyond the built-in fields; don't overload `message`/`code` for structured data a receiving resource needs to parse.
