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
