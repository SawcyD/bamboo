--!strict

local Create = require(script.Parent.Enum).Create

export type Type = "Enemy" | "Boss" | "Merchant" | "Civilian" | "Wildlife" | "Pet"
export type MovementMode = "Ground" | "Flying" | "Swimming" | "Climbing"
export type AlertState = "Unaware" | "Suspicious" | "Alerted" | "Searching" | "Combat"
export type Disposition = "Friendly" | "Neutral" | "Hostile"

return table.freeze({
	Type = Create({ "Enemy", "Boss", "Merchant", "Civilian", "Wildlife", "Pet" }),
	MovementMode = Create({ "Ground", "Flying", "Swimming", "Climbing" }),
	AlertState = Create({ "Unaware", "Suspicious", "Alerted", "Searching", "Combat" }),
	Disposition = Create({ "Friendly", "Neutral", "Hostile" }),
})
