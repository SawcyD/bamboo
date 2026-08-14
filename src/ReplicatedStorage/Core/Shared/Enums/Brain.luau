--!strict

local Create = require(script.Parent.Enum).Create

export type State = "Idle" | "Patrol" | "Investigate" | "Chase" | "Attack" | "Flee" | "Stunned" | "Dead"
export type BehaviorStatus = "Running" | "Success" | "Failure"
export type TransitionReason = "Start" | "Update" | "Event" | "Timeout" | "Interrupt" | "Death"
export type TargetingMode = "Nearest" | "LowestHealth" | "HighestThreat" | "Random"

return table.freeze({
	State = Create({
		"Idle",
		"Patrol",
		"Investigate",
		"Chase",
		"Attack",
		"Flee",
		"Stunned",
		"Dead",
	}),
	BehaviorStatus = Create({ "Running", "Success", "Failure" }),
	TransitionReason = Create({ "Start", "Update", "Event", "Timeout", "Interrupt", "Death" }),
	TargetingMode = Create({ "Nearest", "LowestHealth", "HighestThreat", "Random" }),
})
