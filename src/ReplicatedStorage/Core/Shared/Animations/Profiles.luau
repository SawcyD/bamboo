--!strict
-- Helpers for defining reusable character and NPC animation profiles.

local Profiles = {}

export type AnimationDefinition = {
	Id: string,
	Looped: boolean?,
	Priority: Enum.AnimationPriority?,
}

export type Locomotion = {
	Idle: string?,
	Walk: string?,
	Run: string?,
	WalkSpeed: number?,
	RunSpeed: number?,
}

export type Profile = {
	Animations: { [string]: AnimationDefinition | string },
	Locomotion: Locomotion?,
}

function Profiles.Animation(id: string, looped: boolean?, priority: Enum.AnimationPriority?): AnimationDefinition
	assert(id ~= "", "Animations.Profiles.Animation: animation id is required")
	return {
		Id = id,
		Looped = looped,
		Priority = priority,
	}
end

function Profiles.Create(animations: { [string]: AnimationDefinition | string }, locomotion: Locomotion?): Profile
	return {
		Animations = animations,
		Locomotion = locomotion,
	}
end

return Profiles
