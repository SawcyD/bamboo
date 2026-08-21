--!strict
-- Every tunable for the Phase 1.5 world-feel pass, in one table.
--
-- These are presentation values only. Nothing here affects health, rewards,
-- odds, timers, or costs — the server never reads this file, and changing any
-- number in it can only change how something looks.
--
-- Structured by system so a tuning session is a scroll rather than a hunt, and
-- so a whole effect can be switched off (`Enabled = false`) when profiling a
-- frame-time regression on a low-end device.

local FeelConfig = {}

-- ── global ───────────────────────────────────────────────────────────────────

-- Master switch per system, so a suspect effect can be isolated during a
-- MicroProfiler pass without deleting code.
FeelConfig.Enabled = table.freeze({
	Sway = true,
	GrowthPop = true,
	Topple = true,
	RarityBurst = true,
	RotorFeel = true,
	DropFeel = true,
	ComboFeel = true,
	SellShow = true,
	BoardFeel = true,
})

-- ── stalk idle sway ──────────────────────────────────────────────────────────
--
-- Sway is the single most expensive effect here, because it writes a model
-- pivot per stalk per update and a plot holds up to 180 stalks. Two things keep
-- it affordable: a distance cull, and a per-frame budget that round-robins the
-- field so each stalk updates at roughly `BudgetPerFrame / visibleStalks` Hz.
-- Sway is a slow sine, so a stalk refreshed ~13x/sec is indistinguishable from
-- one refreshed every frame — but it costs a quarter as much.
FeelConfig.Sway = table.freeze({
	-- Stalks past this from the camera are not swayed at all.
	Radius = 70,
	RadiusSq = 70 * 70,
	-- Model pivots rewritten per frame across every field. The number that matters
	-- is pivots x parts-per-stalk, not pivots: the forest pass raised a Normal
	-- stalk to ~14 parts, so 30 pivots/frame is ~425 part CFrame writes — about
	-- what 40 cost before the stalks got taller. Raise this only alongside a
	-- MicroProfiler reading on a full field.
	BudgetPerFrame = 30,

	-- Peak bend of a mature Normal stalk. Deliberately tiny — the field should
	-- breathe, not wave. Anything past ~3 degrees starts reading as wind damage.
	MaxRadians = math.rad(1.6),
	-- Sway cycles per second, before per-stalk variation.
	BaseFrequency = 0.55,
	-- Per-stalk multipliers on frequency/amplitude, picked from the stalk id so
	-- the field never pulses in unison. 1.0 +/- this fraction.
	FrequencyJitter = 0.35,
	AmplitudeJitter = 0.4,

	-- A second, slower sine layered on top at this fraction of the amplitude.
	-- Two incommensurate frequencies stop the loop from reading as a loop.
	SecondaryRatio = 0.42,
	SecondaryFrequency = 0.23,

	-- Taller stalks bend more, so a Tall reads as more flexible than a Thick.
	-- Multiplier applied per unit of the rarity's heightScale above 1.
	HeightInfluence = 0.5,
	-- Thick stalks are stiff: amplitude divided by thicknessScale ^ this.
	ThicknessStiffness = 0.8,

	-- Immature stalks barely move: a shoot is a stub in the ground, and keeping
	-- it still is half of what makes mature bamboo read as "this one is cuttable".
	ShootAmplitude = 0.15,
	YoungAmplitude = 0.45,
})

-- ── stalk hit recoil ─────────────────────────────────────────────────────────
--
-- A struck stalk kicks away from the impact and springs back. These were
-- previously constants inside BambooFXController; they moved here when the pose
-- work was centralised, and the values are carried over unchanged so the
-- existing hit feel is preserved.
FeelConfig.StalkHit = table.freeze({
	-- Radians a stalk bends at full kick. Small on purpose: the read is "WHACK",
	-- not an animation.
	MaxRadians = math.rad(11),
	SmoothTime = 0.11,
	-- Below this the recoil is imperceptible and the entry is dropped.
	RestEpsilon = 0.0015,
	-- Flash length on a confirmed hit, deliberately barely-there.
	FlashSeconds = 0.1,
})

-- ── growth stage pop ─────────────────────────────────────────────────────────
--
-- Fired when a stalk crosses a growth stage. A scale overshoot that settles,
-- so a stalk arriving at Mature announces itself in the corner of the eye.
FeelConfig.GrowthPop = table.freeze({
	-- Spring smooth-time for the settle. Lower = snappier.
	SmoothTime = 0.16,
	-- Scale overshoot per stage transition, keyed by the stage being entered.
	-- Mature is the one that matters: it means "cut me".
	ShootScale = 0.06,
	YoungScale = 0.08,
	MatureScale = 0.14,
	-- Upward settle: the stalk lifts by this fraction of its height and drops
	-- back, which sells the pop as growth rather than a size glitch.
	LiftFraction = 0.035,
	-- Below this the pop is imperceptible and the entry is dropped.
	RestEpsilon = 0.002,
})

-- ── break topple ─────────────────────────────────────────────────────────────
--
-- The existing sever (top half detaches as flying chunks) already carries the
-- break. Topple adds the missing half of the read: the stub twists and falls at
-- its base instead of fading in place, so a felled stalk goes *down*.
FeelConfig.Topple = table.freeze({
	-- Total fall time. Scaled per rarity below.
	Seconds = 0.30,
	-- How far the stub bends over. Past ~80 degrees it clips into the ground.
	FallRadians = math.rad(72),
	-- Twist about the stalk's own axis as it goes, which is what stops the fall
	-- from reading as a flat hinge.
	TwistRadians = math.rad(28),
	-- Fraction of the fall spent easing out of the ground impact (the bounce).
	BounceFraction = 0.18,
	BounceRadians = math.rad(6),

	-- Per-rarity feel. `time` multiplies Seconds, `bend` multiplies FallRadians.
	-- Thick falls slower and harder; Tall arcs further and takes longer.
	Rarity = table.freeze({
		Normal = table.freeze({ time = 1.0, bend = 1.0, bounce = 1.0 }),
		Tall = table.freeze({ time = 1.25, bend = 1.12, bounce = 0.9 }),
		Thick = table.freeze({ time = 1.35, bend = 0.85, bounce = 1.8 }),
	}),
})

-- ── break cascade ────────────────────────────────────────────────────────────
--
-- A felled stalk breaks upward through its joints: the bottom segment snaps and
-- kicks away, then the next, then the next, until the top detaches. The read is
-- a stalk coming apart at the joints, not a model exploding.
--
-- The cascade is purely a reaction to the server having already confirmed the
-- break. It cannot cut anything, cannot grant anything, and runs exactly once
-- per stalk.
FeelConfig.Cascade = table.freeze({
	-- Gap between one joint snapping and the next.
	SegmentDelay = 0.075,
	-- Per-stalk jitter on that gap, so a field of breaks isn't metronomic. A
	-- fraction of SegmentDelay.
	SegmentDelayJitter = 0.25,
	-- How long one detached segment takes to arc away and fade.
	SegmentFlightSeconds = 0.55,
	-- The snap itself: the segment tips at its base before it leaves.
	SegmentSnapSeconds = 0.14,

	-- Outward kick. Segments higher up the stalk are thrown further, which is
	-- what makes the cascade read as travelling upward.
	KickSpeedBase = 6,
	KickSpeedPerSegment = 1.6,
	KickUpSpeed = 7,
	SpinRadians = 7,

	-- Hard ceiling on segments animated across *all* stalks breaking in the same
	-- moment. A wide multi-hit plus a Chain proc can confirm a dozen stalks at
	-- once; without this that is a dozen full cascades of loose parts.
	MaxLiveSegments = 60,
	-- Stalks whose cascade would exceed the ceiling collapse instantly instead —
	-- still a break, just without the per-joint theatre.
	MaxConcurrentCascades = 6,
	-- Extra delay stacked per simultaneous stalk, so several stalks breaking
	-- together read as a run rather than one mush.
	StalkStagger = 0.06,

	-- Per-rarity character.
	Rarity = table.freeze({
		Normal = table.freeze({ delay = 1.0, kick = 1.0, spin = 1.0 }),
		-- More joints already, so a slightly tighter gap keeps the total duration
		-- inside the readable window rather than dragging.
		Tall = table.freeze({ delay = 0.85, kick = 1.25, spin = 1.3 }),
		-- Heavy: slower, shorter throw, less spin. It falls rather than flies.
		Thick = table.freeze({ delay = 1.3, kick = 0.7, spin = 0.6 }),
	}),

	-- Reward fragments. The server already decided the payout; these only carry
	-- it visually, so the count is capped independently of both the segment count
	-- and the amount collected.
	MaxRewardFragments = 4,
})

-- ── impact / break particle bursts ───────────────────────────────────────────
--
-- Short bursts only, never a sustained emitter parented to a live stalk. Every
-- burst comes from a pooled anchored part that is returned on a timer.
FeelConfig.Burst = table.freeze({
	-- Idle emitter parts kept warm. A wide multi-hit swing plus a chain can want
	-- ~8 at once; past the cap the pool destroys the overflow rather than growing.
	PoolInitial = 8,
	PoolMax = 24,
	-- Seconds an emitter part stays checked out before returning to the pool.
	-- Must outlive the longest particle Lifetime below.
	PartLifetime = 2.2,

	-- Wood chips on a non-lethal hit. Small, fast, gone.
	Chip = table.freeze({
		Count = 6,
		Size = 0.22,
		Speed = NumberRange.new(7, 14),
		Lifetime = NumberRange.new(0.25, 0.5),
		Gravity = -38,
	}),
	-- Ground dust when a stalk lands. Slow and low.
	Dust = table.freeze({
		Count = 8,
		Size = 1.1,
		Speed = NumberRange.new(1.5, 4),
		Lifetime = NumberRange.new(0.4, 0.8),
		Gravity = -2,
		Color = Color3.fromRGB(186, 172, 138),
	}),

	-- Hard ceiling on particles emitted from one swing packet, across every
	-- stalk it touched. A 20-target multi-hit must not be 20x the particles.
	MaxParticlesPerSwing = 90,
})

-- ── mutation reveal ──────────────────────────────────────────────────────────
--
-- Rare bamboo gets a *burst*, never a permanent emitter. The stalk already
-- carries its rarity in colour/material/glow from BambooModel; this is only the
-- moment-of-break payoff.
FeelConfig.Reveal = table.freeze({
	-- Mutations below this revealWeight get no special break burst at all, so
	-- Dewy and Red stay quiet and Crystal upward reads as an event.
	MinRevealWeight = 3.0,

	-- Particles in the reveal burst, before the per-mutation multiplier.
	BaseCount = 14,
	-- Shard/spark size and speed.
	Size = 0.4,
	Speed = NumberRange.new(10, 20),
	Lifetime = NumberRange.new(0.35, 0.75),

	-- Expanding ring at the stalk's foot. The clearest "something rare happened"
	-- read at a distance, and one part rather than an emitter.
	Ring = table.freeze({
		Seconds = 0.45,
		StartDiameter = 2,
		EndDiameter = 16,
		Thickness = 0.35,
	}),
	-- Only mutations at or above this revealWeight get the ring, so it stays
	-- meaningful. Crystal is 3.2, Golden 4.5, Ancient 6.
	RingMinRevealWeight = 4.0,
})

-- ── rotor / sickle ───────────────────────────────────────────────────────────
--
-- The rotor already winds up, tips outward, and takes a break-energy kick. This
-- adds the beats it was missing: idle bob, a recoil on confirmed contact, and a
-- lean toward what it is about to cut.
FeelConfig.Rotor = table.freeze({
	-- Vertical bob while idling, so a parked rotor still breathes.
	BobStuds = 0.12,
	BobFrequency = 1.1,
	-- Bob is suppressed as the rotor winds up; at full speed it is gone.
	BobFadeWithWind = true,

	-- Recoil kick on a server-confirmed hit. Radians the rotor plane jolts.
	HitRecoilRadians = math.rad(4.5),
	-- A break kicks harder than a hit that only damaged.
	BreakRecoilRadians = math.rad(9),
	RecoilSmoothTime = 0.09,
	-- Ceiling so a wide multi-break cannot stack into a spin-out.
	MaxRecoilRadians = math.rad(16),

	-- Radius the rotor pushes out by on a break, then springs back. Reads as the
	-- blade being thrown wide by the resistance.
	BreakPushStuds = 0.55,

	-- Trail escalation with combo. Lifetime is the existing 0.10-0.30 range; this
	-- is added on top at full combo heat.
	ComboTrailLifetimeBonus = 0.14,
	ComboTrailWidthBonus = 0.5,
})

-- ── ground drops ─────────────────────────────────────────────────────────────
FeelConfig.Drop = table.freeze({
	-- Spawn pop: a drop pile punches up out of the ground when it appears.
	PopSeconds = 0.26,
	PopHeightStuds = 1.5,
	-- Per-drop variation on pop height so a scattered field doesn't pop in sync.
	PopHeightJitter = 0.45,
	-- Scale overshoot on spawn.
	PopScale = 1.35,

	-- Existing bob/spin, kept here so all drop tuning is in one place.
	BobHeight = 0.4,
	BobSpeed = 2.2,
	SpinSpeed = 1.4,

	-- Collection flight. The existing pull is 0.32s straight-ish; a touch longer
	-- with a wider arc reads as magnetic rather than teleported.
	FlightSeconds = 0.38,
	ArcHeight = 5,
	-- Bigger piles get a slightly fatter orb and a trail, not more orbs.
	MaxOrbs = 5,
	TrailMinAmount = 12,
	-- Flash when an orb lands on the player.
	CollectFlashSeconds = 0.18,
})

-- ── combo world feedback ─────────────────────────────────────────────────────
--
-- Deliberately restrained: the player has to keep seeing the field. No
-- persistent aura, only milestone punctuation and a decay warning.
FeelConfig.Combo = table.freeze({
	-- Ground ring at the player's feet on a milestone.
	Ring = table.freeze({
		Seconds = 0.5,
		StartDiameter = 3,
		EndDiameter = 13,
		Thickness = 0.3,
	}),
	-- Leaf swirl around the player on a milestone. Burst, not sustained.
	SwirlCount = 12,
	SwirlSeconds = 0.7,
	SwirlRadius = 3.5,

	-- Decay warning: the last fraction of the combo window pulses the ring
	-- colour. Only shown above this combo, so early streaks aren't nagged.
	WarnBelowFraction = 0.3,
	WarnMinCombo = 10,
})

-- ── sell zone ────────────────────────────────────────────────────────────────
--
-- Staged: deposit travels in, the machine processes, cash bursts out, hovers,
-- then homes to the player. Every count here is capped — amount changes the
-- intensity of a fixed animation, never the number of objects per unit sold.
FeelConfig.Sell = table.freeze({
	-- Name of the receiving point inside the sell zone. Created on demand if the
	-- authored model doesn't have one.
	DepositPointName = "SellDepositPoint",
	DepositPointHeight = 3.5,

	-- Idle: the zone breathes while it can be used.
	IdlePulseSeconds = 2.2,
	IdlePulseTransparency = 0.18,
	IdleRingSeconds = 2.6,

	-- Deposit phase: bamboo bundles arc from the player into the receiving point.
	DepositSeconds = 0.5,
	DepositArcHeight = 7,
	-- Visual bundles, never one per bamboo. Amount only moves this within range.
	MinBundles = 1,
	MaxBundles = 6,
	BundleStagger = 0.06,

	-- Processing flash at the receiving point once the deposit lands.
	ProcessSeconds = 0.16,

	-- Cash burst.
	CashSeconds = 0.35,
	CashBurstRadius = 6,
	CashRiseStuds = 4,
	MinCash = 1,
	MaxCash = 14,
	-- Payouts at or above this get the stronger tier: wider burst, extra wave.
	BigPayoutThreshold = 1000,
	BigPayoutRadiusScale = 1.6,
	BigPayoutWaves = 2,

	-- Hover before the cash comes home.
	HoverSeconds = 1.0,
	HoverBobStuds = 0.35,
	HoverSpinSpeed = 2.5,

	-- Homing return to the player.
	ReturnSeconds = 0.55,
	ReturnStagger = 0.04,
	ReturnArcHeight = 5,

	-- Absolute ceiling on visual objects alive from selling at any one time,
	-- across every overlapping sale. Repeated selling in the zone fires every
	-- ~0.35s, so this is what stops a camper from carpeting the plot in coins.
	MaxLiveObjects = 40,

	CashColor = Color3.fromRGB(255, 214, 92),
	CashSize = Vector3.new(0.9, 0.9, 0.16),
})

-- ── processor ────────────────────────────────────────────────────────────────
--
-- Presentation only, matching Bamboo.Processing (the shared config those visuals
-- are reacting to). Nothing here changes rates, buffer sizes, or sell value —
-- see Core/Shared/Domains/Bamboo/Processing.luau for those.
FeelConfig.Processor = table.freeze({
	-- Roller spin, radians/sec. Idle keeps the machine reading as "on" without
	-- looking like it is working; active is the same read the sickle rotor uses
	-- for "cutting speed" vs "coasting".
	IdleRollSpeed = 0.5,
	ActiveRollSpeed = 3.4,
	-- Smooth-time the roller's speed eases between idle and active over, so a
	-- deposit landing doesn't snap the roller to full speed mid-turn.
	RollSmoothTime = 0.6,

	-- Light on the body. Off at rest; active brightness plus a slow pulse on top,
	-- so "has fuel" reads from across the plot without being distracting.
	ActiveLightBrightness = 2.2,
	ActiveLightPulseAmplitude = 0.5,
	ActiveLightPulseSeconds = 1.6,

	-- Small wood/dust puffs at the input point while the machine has fuel.
	ParticleIntervalSeconds = 0.7,
	ParticleCount = 5,

	-- Deposit: bamboo bundles arc from the player into the input point. Reuses
	-- Orbify, so this is the same shape as collecting a drop — just the reverse
	-- direction and destination.
	DepositArcHeight = 6,
	DepositFlightSeconds = 0.5,
	-- Bundles are capped independently of how much bamboo actually moved, so a
	-- 100-bamboo deposit costs the same as a 10-bamboo one.
	MinDepositBundles = 1,
	MaxDepositBundles = 6,
	DepositBundleThreshold = 15,

	-- One pop per completed batch, not per unit of Straw — OutputPerBatch is
	-- already a fixed, small number, so this never needs its own cap on amount.
	ProductBounceSeconds = 0.42,
	ProductBounceHeight = 2.5,
	-- Visible product objects kept stacked at the output point before older ones
	-- are cleared. A real "hundreds of objects" ceiling, not just a soft cap.
	MaxVisibleProducts = 6,

	-- Output buffer full: a slow, low-key tint pulse on the body rather than a
	-- particle spam, so "go sell" reads without nagging.
	FullPulseSeconds = 1.8,
	FullTintColor = Color3.fromRGB(255, 176, 96),

	-- Player stands at the processor with bamboo to deposit but the input buffer
	-- has no room: a quick, sparse reject pulse, matching the upgrade board's
	-- "can't afford this" shudder rather than a constant warning.
	BlockedPulseSeconds = 0.3,
	BlockedTintColor = Color3.fromRGB(255, 120, 120),
})

-- ── upgrade boards ───────────────────────────────────────────────────────────
FeelConfig.Board = table.freeze({
	-- Idle: an affordable board glows faintly. Only the affordable ones, and only
	-- the nearest gets the stronger treatment, so six boards never all shout.
	IdlePulseSeconds = 1.8,
	AffordableGlow = 0.12,
	NearestGlow = 0.3,

	-- Hover/selection: the nearest board leans forward slightly.
	SelectLeanRadians = math.rad(3),
	SelectRaiseStuds = 0.25,
	SelectSmoothTime = 0.12,

	-- Purchase reaction.
	PurchasePunchScale = 1.12,
	PurchaseSeconds = 0.32,
	PurchaseShakeRadians = math.rad(2.5),
	-- Light pulse on buy.
	PurchaseLightBrightness = 4,
	PurchaseLightRange = 16,
	-- Rejected purchase: a short red shudder, so "I can't afford this" is
	-- physical rather than only a red number on the billboard.
	RejectShakeRadians = math.rad(1.5),
	RejectSeconds = 0.22,
})

return table.freeze(FeelConfig)
