--!strict
-- Named hooks for bamboo break audio, with a hard ceiling on how many can sound
-- at once.
--
-- Every profile here is the existing BambooPop sample with a different playback
-- speed and SoundEffect chain, declared in the SFX library. SoundUtil builds a
-- fresh Sound per play and destroys it when it finishes, so the shared pop entry
-- is never mutated and two segments snapping in the same frame cannot alter each
-- other's pitch.
--
-- The reason this module exists rather than callers reaching for Audio:PlayAt
-- directly is the ceiling. A cascade is one sound *per joint*: a single Tall
-- stalk is eight, and a wide multi-hit that fells six stalks at once would be
-- close to fifty overlapping instances. Past a handful they stop being rhythm
-- and start being noise — and each one is a Part plus a Sound plus an effect
-- chain, which is a real cost on a phone.
--
-- Callers use the named hooks (SegmentSnap / CascadeFinale). Retuning the audio
-- pass later means changing the profile table below or the SFX entries it points
-- at, and touching nothing that calls this.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Audio = require(ReplicatedStorage:WaitForChild("Audio"))

local BambooAudio = {}

-- Simultaneous bamboo-break sounds allowed. Beyond this, calls are dropped
-- rather than queued: a snap that arrives late is worse than one that never
-- arrives, because the cascade has already moved on up the stalk.
local MAX_CONCURRENT = 10
-- Roughly how long one snap occupies a slot. The samples are short; this only
-- has to be long enough to stop the counter draining before the sound does.
local SLOT_SECONDS = 0.35

-- Named profiles, so the cascade never spells out a sound id or a pitch range.
local PROFILE = table.freeze({
	Light = "BambooSegmentSnap",
	Heavy = "BambooHeavySegmentSnap",
	Tall = "BambooTallSegmentSnap",
	Finale = "BambooCascadeFinale",
})

-- Which profile a rarity snaps with.
local RARITY_PROFILE: { [string]: string } = {
	Normal = PROFILE.Light,
	Tall = PROFILE.Tall,
	Thick = PROFILE.Heavy,
}

local _live = 0

local function _reserve(): boolean
	if _live >= MAX_CONCURRENT then
		return false
	end
	_live += 1
	task.delay(SLOT_SECONDS, function()
		_live = math.max(_live - 1, 0)
	end)
	return true
end

--[[
	One joint letting go, at its own position in the world.

	Pitch and volume are jittered per call on top of the profile's own range, so
	a cascade reads as a run of hollow pops travelling up the stalk rather than
	the same sample repeated.

	@param position Vector3 Where the segment detached.
	@param rarityId string Rarity id, which picks the profile.
	@param progress number 0-1 up the stalk; higher segments ring slightly higher.
]]
function BambooAudio.SegmentSnap(position: Vector3, rarityId: string, progress: number)
	if not _reserve() then
		return
	end

	local profile = RARITY_PROFILE[rarityId] or PROFILE.Light
	-- Rising slightly as the break climbs is what sells the cascade as vertical.
	local climb = 1 + progress * 0.18
	Audio:PlayAt(profile, position, "SFX", {
		PlaybackSpeed = climb * (0.94 + math.random() * 0.12),
		Volume = 0.85 + math.random() * 0.3,
	})
end

--[[
	The last segment letting go. Played once per cascade.
	@param position Vector3 Where the stalk stood.
	@param rarityId string Rarity id, so a Thick finale lands heavier.
]]
function BambooAudio.CascadeFinale(position: Vector3, rarityId: string)
	if not _reserve() then
		return
	end

	-- A heavier stalk finishes lower, without needing its own profile.
	local weight = if rarityId == "Thick" then 0.88 else 1
	Audio:PlayAt(PROFILE.Finale, position, "SFX", {
		PlaybackSpeed = weight * (0.95 + math.random() * 0.1),
	})
end

--[[
	How many break sounds are currently holding a slot, for the perf overlay.
	@return number Live bamboo-break sounds.
]]
function BambooAudio.GetLiveCount(): number
	return _live
end

return BambooAudio
