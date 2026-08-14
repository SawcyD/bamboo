--!strict

local Create = require(script.Parent.Enum).Create

export type OutcomeType = "Collectible" | "Junk" | "Resource" | "Empty" | "Special"
export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"
export type Condition = "Worn" | "Used" | "Good" | "Pristine"
export type TradeState = "Available" | "Locked" | "Listed" | "Escrowed"

return table.freeze({
	OutcomeType = Create({ "Collectible", "Junk", "Resource", "Empty", "Special" }),
	Rarity = Create({ "Common", "Uncommon", "Rare", "Epic", "Legendary" }),
	Condition = Create({ "Worn", "Used", "Good", "Pristine" }),
	TradeState = Create({ "Available", "Locked", "Listed", "Escrowed" }),
})
