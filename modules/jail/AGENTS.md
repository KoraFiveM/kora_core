# jail module guide

## Purpose
A self-contained, minimal jail: teleport a player to `Config.jail.coords`, lock movement client-side for a duration, release on timer or `/unjail`. Defers to a real prison resource (`Config.jail.deferToResources`) if one is running, same detection pattern qbx_police uses for xt-prison/qbx_prison — so dropping in a fancier prison resource later needs no changes here or in a job resource calling `Core.jail.jailPlayer`.

## Public API
Server:
- `Core.jail.jailPlayer(src, minutes, reason)` — jails, or defers to an external prison resource if one is running.
- `Core.jail.release(src)` — releases from Core.jail's own jail (not an external resource's).
- `Core.jail.getRemaining(src)` — seconds remaining, `0` if not jailed/expired.
- `Core.jail.isJailed(src)` — `boolean`.
- `/jail <id> <minutes> [reason]`, `/unjail <id>` — admin commands, registered via `Core.commands.addCommand`.

Client: no public API — reacts to `kora_core:client:jailTeleport`/`kora_core:client:jailRelease` pushed by the server half.

## Implementation notes
- **Persisted via the existing `metadata.jailed` field**, storing a UNIX release timestamp (not a duration) — survives relog for free, no schema change. `jailed = 0` means "not jailed" (its existing default).
- **`deferToExternal` checks `Config.jail.deferToResources` in order**; if one is `started`, fires `kora_core:server:onJailRequest(src, minutes, reason, resourceName)` and `jailPlayer` returns `true` without touching `metadata.jailed` at all — the external resource owns the entire sentence from there, including its own release flow.
- **`release` only releases Core.jail's own jail.** It does not (and cannot) release a sentence an external prison resource is currently managing — that resource's release flow is independent.
- **Rejoin/reconnect re-applies the teleport.** `kora_core:server:playerLoaded` re-checks `getRemaining` and re-sends `kora_core:client:jailTeleport` if a sentence is still active, covering a relog/crash mid-sentence — skipped if an external prison resource is now running, since that resource owns its own rejoin handling.
- **Client containment is a `Kora.zones` sphere**, not a hard freeze: leaving `CONTAINMENT_RADIUS` (30.0) teleports the player straight back via `onExit`. No countdown UI/HUD of its own — kora_core ships no NUI, same as everywhere else; a job resource wanting a jail-time display reads `Core.jail.getRemaining(src)` itself.
- **`clearContainment` guards a race** between the zone's exit tick firing and the zone already having been released (`containmentZone` nilled) between those two events.

## Best practices
- Call `Core.jail.jailPlayer` rather than writing `metadata.jailed` directly — it handles the external-resource defer, the client push, and the `kora_core:server:playerJailed` event together.
- If you add another deferrable prison resource, add its resource name to `Config.jail.deferToResources` — no code change needed here.
