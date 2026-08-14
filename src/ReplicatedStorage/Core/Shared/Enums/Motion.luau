--!strict

local Create = require(script.Parent.Enum).Create

export type State = "Idle" | "Walk" | "Run" | "Jump" | "Fall" | "Land" | "Attack" | "Hit" | "Stunned" | "Death"
export type Layer = "Base" | "UpperBody" | "Action" | "Additive" | "Facial"
export type RigType = "R6" | "R15" | "Custom"
export type BlendMode = "Snap" | "Crossfade" | "Layered"

return table.freeze({
	State = Create({
		"Idle",
		"Walk",
		"Run",
		"Jump",
		"Fall",
		"Land",
		"Attack",
		"Hit",
		"Stunned",
		"Death",
	}),
	Layer = Create({ "Base", "UpperBody", "Action", "Additive", "Facial" }),
	RigType = Create({ "R6", "R15", "Custom" }),
	BlendMode = Create({ "Snap", "Crossfade", "Layered" }),
})
