# Server Authority & Replication

How state moves through this framework, and the rules that keep exploiters out.

## The one rule

**The server owns all state. The client renders it and asks for changes.**

A client can *request* ("open this egg", "fire at this position") and *predict*
(play the animation immediately), but the server decides what actually happened
and tells everyone through replication. If removing a line of client code could
give a player free items, that line was on the wrong side.

### Client-only world visuals

Bamboo follows the same rule without replicating thousands of Parts. `BambooService`
keeps stalk positions, health, rarity, growth, and rewards as server data, then
sends a compact snapshot plus cut/replant deltas through the Bamboo relay. The
client derives deterministic slot positions and builds only nearby visuals locally.
Growth uses a server timestamp, so it does not stream a per-stalk property every
half second.

## How state flows here

```
[client input] --Relay channel--> [server service validates + mutates]
                                          |
                                   DataService.Set / Update
                                          |
                              profile.Data (saved)  +  replica (replicated)
                                          |
[client UI] <--replica change-- [player's Replica]
```

1. Client sends a request on a `Relay` channel (`Relay.Shop.BuyItem.send{...}`).
2. The channel layer already enforced **schema validation** and **rate limiting**
   before your handler runs (see Channel.luau middleware).
3. The service re-checks everything the client claimed: can they afford it, do
   they own it, are they close enough, is it off cooldown.
4. The service mutates data with `DataService.Set / Update / Increment` — one
   call saves *and* replicates the affected key.
5. The client's UI reacts to the replica change. The client never "sets" data.

## Validation checklist for every c2s handler

- **Type/shape**: covered by the channel's `value` validators — always define them.
- **Rate**: covered by the default 60/s channel rate limit; set a tighter
  `rateLimit` for expensive actions, and use `Cooldown:Try(player)` for
  gameplay-rate actions (abilities, purchases).
- **Possibility**: could this player legitimately do this *right now*? Check
  funds, ownership, distance (`(root.Position - target).Magnitude`), state.
- **Physics claims**: never trust reported positions or hits. For projectiles,
  use `Projectile.Validate` — it re-simulates the trajectory server-side and
  rejects hits that aren't on an unobstructed path.
- **Identity**: the `player` argument comes from the engine and can't be forged;
  never accept a "who am I" field in the payload.

## What never goes to the client

- Top-level data keys starting with `_`, or listed in `Schema.PrivateKeys`,
  are saved but **never replicated** (receipts, moderation flags, server caches).
- Drop tables / odds *logic* can be shared (RNG module is shared so the client
  can show odds labels) — but the **roll happens on the server**.
- Validation thresholds and anti-exploit limits stay server-side where possible.

## Client prediction (making it feel instant without trusting the client)

- Play effects/animations immediately on input; reconcile when the server result
  arrives (e.g. the hatch animation starts on click, the item appears only when
  the server's `EggOpenResult` lands).
- Use `Cooldown` with the same duration on both sides: client predicts the
  cooldown bar on `workspace:GetServerTimeNow()`, server enforces it on the same
  clock — the UI is honest without being authoritative.
- For projectiles: `Projectile.Cast` on the client for visuals, report the hit,
  `Projectile.Validate` on the server before applying damage.

## Spotting leaks with the profiler

Press **L** (Studio / DeveloperIds) to open the performance profiler. Sort is by
bandwidth; the `Replica_PlayerData` row shows replica write traffic and the
`__Estimated_Untracked_Gap` row shows data-receive the framework can't attribute.
A fat replica row usually means something is syncing a whole table at high
frequency — switch it to a path-based `DataService.Set` on the specific key.

## Anti-cheat: server judges, client only hints

`AntiCheatService` is an extension of this same principle, not a replacement for
it. It never makes the client's word authoritative:

- **Server-side detection has the teeth.** Movement (speed/teleport/flight) is
  judged from server state on a 5 Hz Scheduler loop. Validating *actions*
  (funds, ownership, cooldowns) is still each service's own job — call
  `AntiCheat.ReportViolation(player, reason, points)` when you catch something.
- **Client signals are hints, never proof.** The PlayerGui injection scan and the
  liveness heartbeat run on the client (which the exploiter controls), so they
  only raise suspicion the server corroborates. The UI scan can't even see
  `CoreGui`, where serious menus inject — treat it as a tripwire for lazy cheats.
- **Don't hide scripts for "security."** Obscurity buys nothing against tools that
  dump/decompile. The heartbeat watchdog is the real version: a deleted client
  controller stops pinging and the server flags the silence.

Default response is **log + flag** — violations accrue a decaying score
(`GetViolations` / `GetTrust`) and fire `OnViolation`, but nobody is kicked until
you set `AutoKick = true`. Watch logs and tune thresholds before enabling it;
false-kicking real players (high-mobility games trip the speed check — call
`AntiCheat.Forgive(player)` after legit teleports) is worse than missing a cheat.

```lua
-- violations already flow through Log (and any Log.AddSink); OnViolation is the
-- structured hook for your own analytics / moderation dashboard:
AntiCheat.OnViolation:Connect(function(player, reason, severity, total) ... end)
```
