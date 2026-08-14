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

	-- UI toasts / notifications (MessageToast etc.)
	UINotification = {
		SoundId = "rbxassetid://9116394545",
		Volume = 0.6,
		PlaybackSpeed = 1,
		SoundGroup = "SFX",
	},
}
