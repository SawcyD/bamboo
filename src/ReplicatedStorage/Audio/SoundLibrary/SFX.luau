--!strict
-- SFX sound definitions: monster, tools, footsteps, generators, campfire, player

return {
	FootstepGrass = {
		SoundId = "rbxassetid://0",
		Volume = { 0.4, 0.6 },
		PlaybackSpeed = { 0.9, 1.1 },
		SoundGroup = "SFX",
	},
	FootstepStone = {
		SoundId = "rbxassetid://0",
		Volume = { 0.5, 0.7 },
		PlaybackSpeed = { 0.9, 1.1 },
		SoundGroup = "SFX",
	},
	PlayerHit = {
		SoundId = "rbxassetid://0",
		Volume = 0.8,
		PlaybackSpeed = { 0.95, 1.05 },
		SoundGroup = "SFX",
	},
	ToolSwing = {
		SoundId = "rbxassetid://0",
		Volume = 0.7,
		PlaybackSpeed = { 0.9, 1.1 },
		SoundGroup = "SFX",
	},
	MonsterGrowl = {
		SoundId = "rbxassetid://0",
		Volume = 0.9,
		PlaybackSpeed = { 0.85, 1.15 },
		RollOffMaxDistance = 60,
		SoundGroup = "SFX",
	},
	GeneratorHum = {
		SoundId = "rbxassetid://0",
		Volume = 0.5,
		Looped = true,
		RollOffMaxDistance = 40,
		SoundGroup = "SFX",
	},
	CampfireCrackle = {
		SoundId = "rbxassetid://0",
		Volume = 0.6,
		Looped = true,
		RollOffMaxDistance = 30,
		SoundGroup = "SFX",
	},

	-- Bamboo cutting loop. PlaybackSpeed is overridden per-play to carry combo.
	BambooHit = {
		SoundId = "rbxassetid://9119603659",
		Volume = 0.5,
		PlaybackSpeed = { 0.92, 1.08 },
		RollOffMaxDistance = 60,
		SoundGroup = "SFX",
	},
	BambooBreak = {
		SoundId = "rbxassetid://9120962381",
		Volume = 0.8,
		PlaybackSpeed = { 0.95, 1.05 },
		RollOffMaxDistance = 80,
		SoundGroup = "SFX",
	},
	BambooBreakBig = {
		SoundId = "rbxassetid://9126240936",
		Volume = 1,
		PlaybackSpeed = { 0.85, 0.95 },
		RollOffMaxDistance = 110,
		SoundGroup = "SFX",
	},
	BambooCollect = {
		SoundId = "rbxassetid://91478228840490",
		Volume = 0.45,
		PlaybackSpeed = 1,
		SoundGroup = "SFX",
	},
	-- Per-orb absorb transient. Played on a rising ladder, so it must stay a
	-- clean short pop rather than anything with a tail.
	BambooPop = {
		SoundId = "rbxassetid://132948338000932",
		Volume = 1,
		PlaybackSpeed = 1,
		SoundGroup = "SFX",
	},
	-- ── cascade snaps ────────────────────────────────────────────────────────
	--
	-- All four reuse the BambooPop sample above rather than importing new audio.
	-- They differ only by playback speed, volume, and SoundEffect chain, which
	-- SoundUtil.buildSound applies to a *fresh* Sound on every play — so the
	-- shared pop entry is never mutated and segments snapping at the same moment
	-- cannot alter one another.
	--
	-- These are placeholders for the audio pass: the profiles are shaped so real
	-- samples can be dropped in behind the same names later.

	-- Light segment snap: the default rung of a cascade. Short, crisp, bright.
	BambooSegmentSnap = {
		SoundId = "rbxassetid://132948338000932",
		Volume = 0.45,
		PlaybackSpeed = { 1.15, 1.32 },
		RollOffMaxDistance = 70,
		SoundGroup = "SFX",
		Effects = {
			-- Lifts the crack out of the field ambience without raising volume.
			EqualizerSoundEffect = { LowGain = -6, MidGain = 0, HighGain = 4 },
			-- Just enough edge to read as splitting wood rather than a UI blip.
			DistortionSoundEffect = { Level = 0.08 },
		},
	},

	-- Heavy segment snap: Thick bamboo. Lower, louder, with a little body.
	BambooHeavySegmentSnap = {
		SoundId = "rbxassetid://132948338000932",
		Volume = 0.7,
		PlaybackSpeed = { 0.72, 0.85 },
		RollOffMaxDistance = 95,
		SoundGroup = "SFX",
		Effects = {
			EqualizerSoundEffect = { LowGain = 5, MidGain = 0, HighGain = -3 },
			DistortionSoundEffect = { Level = 0.14 },
			-- A very short tail is what separates "heavy" from merely "loud".
			ReverbSoundEffect = { DecayTime = 0.6, Density = 0.4, WetLevel = -12 },
		},
	},

	-- Tall bamboo: hollower, with a longer ring down the length of the stalk.
	BambooTallSegmentSnap = {
		SoundId = "rbxassetid://132948338000932",
		Volume = 0.55,
		PlaybackSpeed = { 0.95, 1.08 },
		RollOffMaxDistance = 85,
		SoundGroup = "SFX",
		Effects = {
			EqualizerSoundEffect = { LowGain = 0, MidGain = 2, HighGain = 1 },
			ReverbSoundEffect = { DecayTime = 1.1, Density = 0.6, WetLevel = -9 },
		},
	},

	-- Cascade finale: plays once, when the top segment lets go.
	BambooCascadeFinale = {
		SoundId = "rbxassetid://132948338000932",
		Volume = 0.8,
		PlaybackSpeed = { 0.6, 0.7 },
		RollOffMaxDistance = 120,
		SoundGroup = "SFX",
		Effects = {
			EqualizerSoundEffect = { LowGain = 8, MidGain = 1, HighGain = -4 },
			DistortionSoundEffect = { Level = 0.12 },
			-- Short echo tail so the stalk sounds like it finished falling.
			EchoSoundEffect = { Delay = 0.11, Feedback = 0.22, DryLevel = 0, WetLevel = -14 },
		},
	},

	BambooSell = {
		SoundId = "rbxassetid://120891770644830",
		Volume = 0.8,
		PlaybackSpeed = 1,
		SoundGroup = "SFX",
	},

	-- UI toasts / notifications (MessageToast etc.)
	UINotification = {
		SoundId = "rbxassetid://9116394545",
		Volume = 0.6,
		PlaybackSpeed = 1,
		SoundGroup = "SFX",
	},
}
