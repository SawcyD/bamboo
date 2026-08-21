# Phase 1.5 — World Feel Pass

A summary of what this session added to the game, from the player's side. Everything
below is presentation only — no reward, odds, cost, or timer changed as gameplay,
except the two items called out in **Economy impact**.

## Bamboo forest

- **Taller bamboo.** Normal stalks are now 18 studs (up from ~10.5), Tall stalks
  reach ~28 studs, Thick stalks are ~19 studs. The field reads as a dense forest
  instead of a low crop.
- **Thick is wide, not tall.** Thick bamboo's height barely changed — its
  thickness did (2.1x → 2.4x), so it now reads as a heavy trunk rather than
  competing with Tall for height.
- **Denser field.** Base stalk count per plot went from 180 to 240 (max Density
  upgrade now caps at 360, up from 300).
- **Idle sway.** Mature bamboo gently sways in the field, each stalk on its own
  timing so the whole field doesn't move in lockstep. Shoots and young stalks
  barely move; only mature (cuttable) bamboo sways noticeably, which keeps it
  easy to tell what's ready to cut.
- **Growth pop.** When a stalk advances a growth stage — especially the moment
  it becomes mature — it gives a small scale punch and settle, so growth is
  something you notice happening rather than something you check on.

## Cutting bamboo

- **Vertical break cascade.** Bamboo no longer just vanishes or falls as one
  piece. A felled stalk now breaks upward through its joints — bottom segment
  snaps first, then the next, then the next, up to the top — each one kicking
  outward with a wood-chip burst and its own snap sound. Taller stalks (Tall)
  have more joints and a longer cascade; heavier stalks (Thick) fall slower and
  hit harder.
- **Hit reactions.** A stalk that's been hit but not yet broken now visibly
  flashes, bends away from the impact, and throws a small puff of leaves and
  wood chips — scaled by how close to breaking it is.
- **Rotor feel.** The sickle rotor now idles with a subtle hover, kicks back on
  a confirmed hit, shoves outward and jolts harder on a break, and its trail
  stretches and thickens as your combo heats up.
- **Rare bamboo effects.** Crystal and above now get a proper reveal: shards
  bursting outward plus an expanding ground ring, colored to the mutation.
  Common bamboo gets nothing extra, so a rare find still feels rare.

## Break sounds

- Four new sound variations, all built from the existing pop sample (no new
  audio imported): a light snap for Normal bamboo, a heavy snap for Thick, a
  hollower ring for Tall, and a stronger finale sound that plays once per
  cascade when the last segment lets go. Each snap is pitched and timed
  slightly differently so a cascade sounds like a run of hollow pops climbing
  the stalk, not one sound repeated.

## Collecting drops

- Ground drops now pop up out of the ground with a little overshoot when they
  spawn, instead of just appearing.
- Collection now arcs in on a wider, slightly longer path so it reads as being
  pulled toward you rather than teleporting, and flashes on arrival.
- Bigger piles send a visibly fatter orb rather than more orbs, so a huge pile
  never turns into a screen full of parts.

## Combo streak

- Hitting a milestone now triggers a ground ring and a swirl of leaves around
  you, colored to your current combo tier.
- When your streak is about to run out, you get one quiet warning ring — not a
  nagging pulse — so you know to keep cutting.

## Selling

- Selling is now a real staged event instead of an instant number change:
  bamboo visibly bundles up and flies into the sell pad, the pad flashes and
  pulses, cash bursts outward and hovers for a moment, then flies back to you
  and dissolves.
- The show scales with how much you sold — a bigger sale gets a wider burst and
  a stronger pulse — but never spawns more than a capped, fixed number of
  objects, so selling a huge stack costs the same as selling a handful.

## Upgrade boards

- A board you can afford now glows faintly; the one you're standing at glows
  brighter and leans slightly toward you.
- Buying an upgrade makes the board visibly react — a scale punch, a light
  pulse, a small burst of sparks.
- Trying to buy something you can't afford now gives the board a small
  physical shudder, instead of just turning the price text red.

## Economy impact (needs your call)

- **Field density (180 → 240 stalks)** is a 33% increase in bamboo per sweep
  with upgrade costs unchanged, so early progression is faster than before.
  This also raises the ceiling on the Density upgrade itself. Not rebalanced —
  say the word and pricing/rewards can be adjusted to compensate.
- Everything else in this pass is confirmed presentation-only.

## Also fixed this session

- A lag spike that was tripping the server's swing rate limit. On join, the
  game was computing every nearby plot's bamboo layout in a single frame,
  which froze the client just long enough for the sickle to "bank" several
  swings and then fire them in a burst. Both the freeze and the burst are
  fixed — the freeze is now spread over a few seconds, and a frozen frame can
  no longer produce more than one swing.

## Not yet tested in Studio

This pass has been checked with the game's linter, formatter, and build tool,
all of which pass, but none of it has been run and played in Studio yet.
Worth a hands-on pass before considering it final — particularly the new part
count on a full field, and how the sell show feels alongside the existing
money counter.
