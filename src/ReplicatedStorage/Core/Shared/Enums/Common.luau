--!strict

local Create = require(script.Parent.Enum).Create

export type LoadState = "Loading" | "Ready" | "Failed"
export type InteractionType = "Click" | "Touch" | "Proximity" | "Prompt"
export type TeamRelation = "Self" | "Ally" | "Neutral" | "Enemy"

return table.freeze({
	LoadState = Create({ "Loading", "Ready", "Failed" }),
	InteractionType = Create({ "Click", "Touch", "Proximity", "Prompt" }),
	TeamRelation = Create({ "Self", "Ally", "Neutral", "Enemy" }),
})
