--!strict

local Profiles = require(script.Parent.Parent.Parent.Profiles)

-- Replace this placeholder with the game's shopkeeper idle animation.
local IDLE_ANIMATION_ID = "rbxassetid://0"

return Profiles.Create({
	Idle = Profiles.Animation(IDLE_ANIMATION_ID, true, Enum.AnimationPriority.Idle),
}, {
	Idle = "Idle",
})
