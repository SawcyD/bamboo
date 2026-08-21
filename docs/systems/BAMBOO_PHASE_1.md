# Bamboo Farm — Phase 1

The whole loop: cut → collect → fill bag → process into Straw → sell → upgrade
→ cut faster.

## Files

| Layer  | File | Job |
| ------ | ---- | --- |
| Shared | `Core/Shared/Domains/Bamboo/` | The domain: `Field`, `Rarity`, `Drops`, `Tool`, `Upgrades`, `Economy`, `Processing`, `Value`, `Types`. Reached with `Core:GetDomain("Bamboo")`. |
| Shared | `Core/Shared/Domains/Sickles/` | Tiers, abilities, the sickle catalog, and `Stats.Compute`. |
| Shared | `Core/Shared/Domains/Crates/` | Crate catalog and pure odds helpers. |
| Shared | `Core/Shared/BambooModel.luau` | Procedural stalk builder + growth-stage scaling (presentation, so it sits outside the domain and reads from it). |
| Shared | `Core/Shared/Network/Events/Bamboo.luau` | `Swing`, `SwingResult`, `BuyUpgrade`, `UpgradeResult`, `Sold`. |
| Server | `Services/PlotService.luau` | Plot allocation, ground/field/sell-zone/board geometry, spawn placement. |
| Server | `Services/BambooService.luau` | Stalk state, growth, swing resolution, yield into the bag. |
| Server | `Services/FarmEconomyService.luau` | Sell-zone polling (raw bamboo + Straw in one payout) and upgrade purchases. |
| Server | `Services/ProcessingService.luau` | Processor deposit-by-proximity and the per-plot batch clock. |
| Server | `Services/DropService.luau` | Ground drops: spawn, merge, despawn, and proximity pickup. |
| Server | `Services/SickleService.luau` | Sickle ownership, equipping, and the one place swing stats resolve. |
| Server | `Services/CrateService.luau` | Charges, rolls, and grants crate openings. |
| Server | `Services/LuckService.luau` | Recomputes each player's luck from boosts and friends. |
| Client | `Controllers/SickleController.luau` | Builds the sickle and spins it around the player as a never-stopping rotor; one swing per revolution. |
| Client | `Controllers/BambooFXController.luau` | All cutting feel: particles, debris, collection flight, shake, reward numbers. |
| Client | `Controllers/BambooHUDController.luau` | Binds the authored Cash/Backpack HUD; owns combo and the one guidance arrow (bag-full → processor, Straw-ready → sell zone). |
| Client | `Controllers/ProcessorController.luau` | Processor idle/active feel, deposit flight, product pops, full/blocked pulses. |
| Client | `Controllers/BambooDropController.luau` | Bobbing/spinning drop piles, expiry blink, pickup burst. |
| Client | `Controllers/CrateController.luau` | Binds the authored OpenBoxes panel and runs the reveal reel. |
| Client | `Controllers/UpgradeBoardController.luau` | Per-board billboard, the `[E]` prompt, and a tappable cost button. |
| Shared | `Core/Modules/Orbify.luau` | Reusable collectible orbs: world burst → player, and UI burst → HUD element. |
| Shared | `Core/Modules/FlashPool.luau` | Pooled `Highlight` impact flashes, one shared frame loop. |
| Shared | `UI/Modules/Ripple.luau` | Reusable click ripple for any `GuiButton`. Reached with `UI:GetModule("Ripple")`. |
| Shared | `UI/Modules/ShadowText.luau` | Keeps both layers of the kit's two-label text in sync. |

## Authority

The client sends only `{ origin, look }`. The server owns the stalk registry and
re-runs the arc query itself, so the client cannot pick its own targets, choose
what broke, or swing faster than its Swing Speed level allows. Money, bag, and
upgrade levels move only through `DataService`.

## Tuning

Everything worth changing during playtests lives in one module of the domain:

| Module | Holds |
| --- | --- |
| `Field.luau` | Base stalk count, regrow time, stage thresholds, and the clustered planter. |
| `Drops.luau` | Despawn time, pickup radius, merge radius, per-plot cap, expiry warning. |
| `Combo.luau` | Timeout, milestones, reward tiers, UI colours, and the value-bonus carry. |
| `Rarity.luau` | Chance, reward multiplier, health, impact weight, and the visual variation spreads. Also `Roll` and `RollVisual`. |
| `Tool.luau` | Damage, base swing time, range, base multi-hit, and the rotor's orbit radius / height / spin-up. `SwingArcDegrees` is 360, which disables the directional cone on both client and server; drop it below 360 for a facing-limited swing. |
| `Upgrades.luau` | The six upgrade definitions: base cost, cost growth, max level, effect text. |
| `Economy.luau` | Bag capacity, money per bamboo, combo window. |
| `Processing.luau` | Batch input/output amounts, batch time, buffer caps, Straw sell value. |
| `Value.luau` | Every derived number: `SwingTime`, `MultiHitTargets`, `YieldPerStalk`, `StalkReward`, `BagCapacity`, `RegrowSeconds`, `StageAt`, `MaxStalks`, `UpgradeCost`, `StatAtLevel`, `CanUpgrade`. |

Nothing outside `Value` should reimplement a formula — the client's upgrade
preview and the server's authoritative grant call the same function.

The domain is covered by `Core/Tests/Bamboo.spec.luau`; run the suite with
`require(game.ReplicatedStorage.Core.Tests).Run()`.

## Reusable feel modules

Two pieces of juice are deliberately generic, so later systems get them for free:

- **`Orbify`** (`Core:Get("Orbify")`) — `Burst` pops world orbs that tumble, then
  stream into a target on staggered curved arcs, calling `OnAbsorb` per arrival.
  `UIBurst` does the screen-space equivalent into a `GuiObject`. Bamboo pieces
  use the first; sell payouts use the second, flying coins into the money
  counter.
- **`Ripple`** (`UI:GetModule("Ripple")`) — `Bind(button)` makes every press
  expand a fading circle from the contact point; `Play(button)` fires one
  manually, which is how the `[E]` key ripples the same button a tap would.

Camera shake comes from `sleitnick/shake` and the rotor wind-up from
`sleitnick/spring`, both via `Core:GetPackage`.

## Upgrades

Six boards, laid out on an arc across the back of the plot. Each owns exactly
one stat:

| Upgrade | Changes | From → per level |
| --- | --- | --- |
| Swing Speed | How fast the rotor turns | 0.80s, −8% compounding |
| Multi-Hit | Stalks per swing | 3, +1 every 2 levels |
| Bamboo Yield | Bamboo per stalk | 2, +1 every 2 levels |
| Storage | Bag capacity | 50, +25 |
| Growth Speed | Regrow time | 40s, −6% compounding |
| Field Density | Stalks in the field | 20, +2 |

Growth Speed and Density are the player's answer to running the field dry — the
balance problem is now something money solves rather than something tuning has
to prevent.

Density needs plots to be laid out for a *fully upgraded* field up front:
`PlotService` builds `Value.MaxPossibleStalks()` planting slots (50), and
`BambooService.SyncFieldSize` plants into the unused ones when the upgrade is
bought. Growth Speed is read per plot per growth tick from the owner's level, so
each player's field grows at their own rate.

## Processing

The loop extends one step: cut → collect raw bamboo → **process into Straw** →
sell Straw (raw bamboo stays sellable directly too, at a lower rate — it is
never a dead end, only a worse trade than processing).

One machine, one recipe: **Raw Bamboo → Straw**, all configured in
`Processing.luau` next to `Economy.luau`.

| | Value | Note |
| --- | --- | --- |
| Input / output per batch | 10 → 5 | All-or-nothing; a batch never consumes or produces a fraction of itself |
| Batch time | 6s | ≈1.67 bamboo/s consumed, deliberately slower than level-0 harvesting (≈2.5 bamboo/s) so cutting always outpaces the machine |
| Input buffer / output buffer | 100 / 50 | Output caps lower on purpose — hitting "full" is meant to happen |
| Straw sell value | 3 | 1.5 money per raw-bamboo-equivalent vs raw bamboo's 1 — the entire incentive to process |

Both buffers (`ProcessorInput`, `StrawStock`) are ordinary top-level
`PlayerData` keys, replicated to the owner exactly like `Bag` and `Money` — no
processing-specific network channel exists. `ProcessorController` only ever
*reacts* to the replica; it never decides an amount.

`ProcessingService` runs two ticks, both mirroring an existing pattern rather
than inventing one:

- **Deposit** (0.35s, same cadence as the sell-zone poll) — standing at the
  processor moves `min(Bag, InputRoom)` into `ProcessorInput`. Idempotent: a
  player parked on the pad just moves nothing once either side is exhausted.
- **Batch** (per-plot clock, ticked at 1Hz) — every plot with an online owner,
  enough input, and output room converts one batch. A plot with no owner (its
  player left) has its clock dropped rather than advanced, which is the entire
  offline-processing rule — there is no separate flag for it.

`FarmEconomyService.SellBag` sells both Bag and `StrawStock` in one payout, so
selling is still the single place money moves; nothing new was added there
besides two more numbers going into the same total.

## Field planting

Bamboo is planted in **clumps with walkable channels**, not on a jittered grid.
`Field.BuildSlots` scatters clump centres by rejection sampling, then fills each
clump in turn.

Filling **in order** rather than round-robin matters: plots pre-build slots for a
fully upgraded field (79) and plant only a prefix (34). Round-robin spread that
prefix thinly across all 11 clumps and undid the clustering entirely — measured
at 1.1 stalks in rotor range. Filling in order makes any prefix a set of
complete clumps.

Measured in-world at base density: **100% of stalks have a neighbour within the
sickle's 7-stud reach, averaging 3.1** — which is exactly the starter sickle's
multi-hit, so a swing anywhere in a clump lands a full sweep. Planting all 12
plots at maximum density costs ~11ms at server start.

Density adds whole new clumps (5 at base → 11 at max), so upgrading gives the
player more patches to run between rather than one thickening blob.

## Ground drops

Cutting with a full bag used to destroy the bamboo silently. Now the overflow
lands where the stalk stood:

- Server-owned in `DropService` — it decides the value, the pickup, and the
  expiry. Drop parts live in `plot.Model.Drops` and carry `Amount`, `Rarity`,
  and `SpawnedAt` attributes for the client to read.
- Drops within `MergeRadius` of a same-rarity pile merge into it, so a group
  break leaves a few worthwhile piles instead of a dozen crumbs. Merging
  refreshes the timer.
- Walking within `PickupRadius` with bag room vacuums them up automatically,
  batched into one `DropsCollected` packet per tick. Partial pickups shrink the
  pile rather than wasting it.
- They despawn after `DespawnSeconds`, blinking for the last `WarnSeconds`.
  `MaxPerPlot` caps the part count; past it the oldest pile goes.

## Sickles

A sickle owns exactly the three stats §17 assigns to the tool — **damage,
range, base multi-hit** — and upgrades stack on top. The Multi-Hit upgrade still
adds one target every two levels; it just adds them to the sickle's base rather
than to a constant. Swing Speed is untouched by sickles, so the two progression
systems never overlap.

Stat budget, deliberately narrow: damage 1–3 (stalks have 3 health, so 3 is a
one-shot), range 7–15, base multi-hit 3–8.

Abilities are what make the top tiers worth chasing. All four resolve
server-side during swing resolution:

| Ability | Effect |
| --- | --- |
| Chain Cut | A break can carry into the nearest untouched neighbour. |
| Reaper | A hit can fell a stalk outright, whatever its health. |
| Bountiful | A broken stalk can pay out double. |
| Magnet | Multiplies ground-drop pickup radius. |

`SickleService.GetStats(player)` is the only place the equipped sickle and the
upgrade levels are combined. `BambooService` reads damage, range, multi-hit, and
swing time from it — the client never sends any of them.

## Crates

Four crates, each overlapping the one below it so the cheap crate stays worth
opening and moving up reads as a jump rather than a reroll.

`CrateService` charges up front, rolls on a server-owned `Random`, and grants.
The client sends only `{ crateId, amount }`. A pull at Legendary or above is
broadcast to the server via `Crates.RareUnbox`, and a better tier auto-equips so
a big pull is felt rather than buried in an inventory.

The panel is the authored `StarterGui.Main.FRAMES.OpenBoxes` UI, which lives in
the place file rather than this repo. `CrateController` binds to it by name and
no-ops if a frame is missing, so the game still runs against a stripped place.
The reveal reel is built at runtime since the kit has no reel frame: a strip of
cards decelerating onto the winner, with a small random offset so it never stops
perfectly centred.

## Luck

Luck bends crate odds toward the rare end. It is stored as the `luck` value
`Core:Get("RNG")` already models — 0 is base odds, higher boosts the rarest
entries hardest — and shown to the player as a multiplier (`x2.15`).
`Crates.Luck` owns that conversion so no caller has to remember which is which.

`LuckService` recomputes it server-side and writes it to replicated data, so the
LuckBoost chip, the odds grid, and the roll all read the same number. Two
sources today:

- **Timed boosts** via `LuckService.GrantBoost(player, luck, seconds)`. A
  stronger boost replaces a weaker one; an equal or weaker one only extends the
  timer, so claiming a lesser boost can never downgrade a player. Nothing grants
  one yet — that hook is where a gamepass or potion would land.
- **Friends in the server**, at `LuckPerFriend` each up to `MaxFriendLuck`.
  Friend lookups yield, so they are cached per player and refreshed when anyone
  joins or leaves.

Luck is read fresh inside `GetLuck` rather than from the replicated copy, so a
boost that expired a moment ago can't be rolled with.

The rewards grid re-renders whenever `Luck` changes, so the percentages on
screen are always the ones a roll would use.

## Auto-open

The `AutoOpen` button toggles a client loop that re-requests every
`AutoOpenIntervalSeconds` (0.85s — deliberately slower than the channel's 8/s
rate limit, so an honest client never trips it).

Auto-open **skips the reel**: a four-second reveal per crate would turn a long
session into a wait. Results land in the authored `HUD.RewardToasts` frame
instead, one line per sickle, coloured by tier and flagged `NEW!` on a first
copy. A manual open cancels auto so the two can't disagree about whether the
reel should play, and the loop stops itself on: toggle off, panel closed, not
enough money, or any server rejection.

A manual bulk open still reels — on its best pull — and toasts the rest.

## Combo

The server owns the combo outright — it already knows which stalks broke, so the
client is never asked, only told, and only when the number moves
(`Bamboo.ComboState`). The client counts the grace window down locally from the
packet's `windowSeconds` rather than being sent a countdown every frame.

Only **felled stalks** build it. Damaging without breaking, collecting drops,
selling, and buying upgrades all leave it untouched.

| Combo | Bonus |
| --- | --- |
| 10+ | +2 walk speed |
| 25+ | +6% swing speed |
| 50+ | +3 walk speed, +8% swing, +10% bamboo value |
| 100+ | +4 walk speed, +10% swing, +15% value, +0.5 replant rarity luck |

Everything economically meaningful is applied server-side in `BambooService`.
Bonuses are deliberately small, and a test asserts a maxed combo can't out-scale
three levels of Swing Speed — permanent upgrades stay the primary progression.

Two details worth knowing:

- **The value bonus carries its fraction** (`Combo.ApplyValueBonus`). A Normal
  stalk is worth 2, so flooring +10% per stalk paid *nothing* — the tier was
  invisible for exactly the bamboo a new player cuts most. Carrying the
  remainder pays a whole extra bamboo every fifth stalk instead.
- **Rarity luck is captured at cut time**, not read at replant time, so the field
  a hot streak leaves behind regrows richer.

## Hit feedback

A stalk that survives a hit now reads as contact rather than a whiff:

- **Flash** — a pooled `Highlight` (10 slots, oldest stolen when full) blended
  72% toward white, so it reads as impact first and rarity second. 0.1s.
- **Recoil** — the stalk springs away from the impact. Models pivot at their
  foot, so they bend from the ground. One shared frame loop drives every active
  recoil and unbinds itself when the last one settles.
- **Sound and shake** — a separate hit sound, pitched down slightly for wider
  sweeps, plus a whisper of camera shake well below the smallest break.

The break hierarchy is untouched and still layers on `impactWeight`.

## The rotor

The sickle never stops turning. `Tool.IdleSpinFraction` (0.3) is how fast it
coasts with nothing in reach; near mature bamboo a critically damped spring
winds it to full speed over `Tool.SpinSmoothTime`. Swings fire off the rotation
itself rather than off a target check, so a stalk that drifts into reach
mid-revolution is caught by the sweep already in progress — the rotor can never
"miss" a patch because it was busy spinning up.

A hot combo lifts the visual spin ceiling and each break adds a decaying kick.
Both are **presentation only**: the swing clock clamps spin at 1.0, so an
energetic-looking rotor can never manufacture swings the server would reject.

## Placeholder art

There are no Blender assets yet. Bamboo, the sickle, the plot, and the boards
are all built from parts at runtime. When the real models land:

- Stalks: replace the body of `_buildStalkParts` in `BambooModel`. Everything
  else only calls `Build` / `ApplyStage`.
- Sickle: replace `_buildSickle` in `SickleController`. Keep the child named
  `Blade` — the trail is attached to it and `_poseRotor` positions it.
- Plot: replace `_buildPlotModel` in `PlotService`, keeping the child names
  `Ground`, `Field`, `SellZone`, `SpawnPad`, and the `BambooUpgradeBoard`-tagged
  boards with their `UpgradeId` attribute.

Sound ids in `Audio/SoundLibrary/SFX.luau` are filled in:

| Key | Plays when |
| --- | --- |
| `BambooHit` | Every swing that connects, lethal or not. |
| `BambooBreak` | A stalk breaks (1–2 at once, common rarity). |
| `BambooBreakBig` | 3+ break together, or a Thick one does. |
| `BambooPop` | Each orb is absorbed, on a rising whole-tone ladder. |
| `BambooCollect` | Each coin orb lands on the money counter after a sale. |
| `BambooSell` | The sale itself. |

`BambooPop` and `BambooCollect` are pitch-stepped, so both need to stay clean
short transients rather than anything with a tail.
