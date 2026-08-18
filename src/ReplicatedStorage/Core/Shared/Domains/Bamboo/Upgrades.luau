--!strict
-- The three Phase 1 upgrades. Each one owns exactly one stat so progression
-- stays legible: how fast you swing, how many stalks you hit, how much you get.
--
-- Costs and stat curves are computed in Value; this file is the registry.

local Types = require(script.Parent:WaitForChild("Types"))

local Upgrades = {}

export type Definition = Types.UpgradeDefinition

local definitions: { [string]: Definition } = {
	SwingSpeed = {
		id = "SwingSpeed",
		name = "SWING SPEED",
		dataKey = "SwingSpeedLevel",
		baseCost = 150,
		costGrowth = 1.35,
		maxLevel = 25,
		effectText = "+8% Swing Speed",
	},
	MultiHit = {
		id = "MultiHit",
		name = "MULTI-HIT",
		dataKey = "MultiHitLevel",
		baseCost = 400,
		costGrowth = 1.55,
		maxLevel = 20,
		effectText = "+1 Target every 2 levels",
	},
	Yield = {
		id = "Yield",
		name = "BAMBOO YIELD",
		dataKey = "YieldLevel",
		baseCost = 250,
		costGrowth = 1.45,
		maxLevel = 20,
		effectText = "+1 Bamboo every 2 levels",
	},
	Storage = {
		id = "Storage",
		name = "STORAGE",
		dataKey = "StorageLevel",
		baseCost = 200,
		costGrowth = 1.40,
		maxLevel = 20,
		effectText = "+25 Bag Capacity",
	},
	GrowthSpeed = {
		id = "GrowthSpeed",
		name = "GROWTH SPEED",
		dataKey = "GrowthSpeedLevel",
		baseCost = 300,
		costGrowth = 1.50,
		maxLevel = 20,
		effectText = "+6% Regrow Speed",
	},
	Density = {
		id = "Density",
		name = "FIELD DENSITY",
		dataKey = "DensityLevel",
		baseCost = 500,
		costGrowth = 1.60,
		maxLevel = 15,
		effectText = "+8 Bamboo in the field",
	},
}

Upgrades.Definitions = definitions

-- Board order around the plot. Cutting-power upgrades first, then the ones that
-- change the field itself, so a new player reads them left to right.
Upgrades.Order = table.freeze({
	"SwingSpeed",
	"MultiHit",
	"Yield",
	"Storage",
	"GrowthSpeed",
	"Density",
})

--[[
	Looks up an upgrade definition.
	@param id string Upgrade id such as "MultiHit".
	@return Definition? The definition, or nil for an unknown id.
]]
function Upgrades.Get(id: string): Definition?
	return definitions[id]
end

--[[
	Every upgrade definition, in board order.
	@return { Definition } Definitions ordered as the boards are laid out.
]]
function Upgrades.List(): { Definition }
	local list: { Definition } = {}
	for _, id in Upgrades.Order do
		table.insert(list, definitions[id])
	end
	return list
end

return Upgrades
