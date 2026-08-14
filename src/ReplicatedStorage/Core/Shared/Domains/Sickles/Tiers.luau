--!strict
-- Sickle rarity tiers: colour, glow, and how hard the crate reveal should hit.
--
-- Tiers carry no stats of their own. A sickle's power lives on its definition,
-- so a tier is purely how the game presents it.

local Types = require(script.Parent:WaitForChild("Types"))

local Tiers = {}

export type Definition = Types.TierDefinition

local definitions: { [string]: Definition } = {
	Common = {
		id = "Common",
		name = "Common",
		color = Color3.fromRGB(178, 186, 194),
		glow = 0,
		revealWeight = 1,
	},
	Uncommon = {
		id = "Uncommon",
		name = "Uncommon",
		color = Color3.fromRGB(112, 214, 124),
		glow = 0.15,
		revealWeight = 1.3,
	},
	Rare = {
		id = "Rare",
		name = "Rare",
		color = Color3.fromRGB(94, 162, 255),
		glow = 0.3,
		revealWeight = 1.8,
	},
	Epic = {
		id = "Epic",
		name = "Epic",
		color = Color3.fromRGB(178, 106, 255),
		glow = 0.5,
		revealWeight = 2.6,
	},
	Legendary = {
		id = "Legendary",
		name = "Legendary",
		color = Color3.fromRGB(255, 186, 64),
		glow = 0.75,
		revealWeight = 3.8,
	},
	Mythic = {
		id = "Mythic",
		name = "Mythic",
		color = Color3.fromRGB(255, 92, 118),
		glow = 1,
		revealWeight = 5.5,
	},
}

Tiers.Definitions = definitions

-- Worst to best. Used for sorting reward grids and picking the "peak" tier out
-- of a multi-open.
Tiers.Order = table.freeze({ "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" })

local rankById: { [string]: number } = {}
for rank, id in Tiers.Order do
	rankById[id] = rank
end

--[[
	Looks up a tier, falling back to Common for unknown ids.
	@param id string Tier id such as "Legendary".
	@return Definition The matching tier, never nil.
]]
function Tiers.Get(id: string): Definition
	return definitions[id] or definitions.Common
end

--[[
	Where a tier sits on the ladder, for comparing two results.
	@param id string Tier id.
	@return number 1 for Common up to 6 for Mythic; 1 for unknown ids.
]]
function Tiers.Rank(id: string): number
	return rankById[id] or 1
end

--[[
	The better of two tiers, for summarising a multi-open.
	@param a string First tier id.
	@param b string Second tier id.
	@return string Whichever ranks higher.
]]
function Tiers.Best(a: string, b: string): string
	return if Tiers.Rank(a) >= Tiers.Rank(b) then a else b
end

return Tiers
