--!strict

local Rarity = require(script.Parent.Rarity)
local Condition = require(script.Parent.Condition)
local Definitions = require(script.Parent.Definitions)

local Value = {}

function Value.Compute(definitionId: string, rarity: string, condition: string, variantMultiplier: number?): number
	local definition = Definitions.Get(definitionId)
	assert(definition, "Unknown collectible definition: " .. definitionId)
	local rarityData = Rarity.Get(rarity)
	local conditionData = Condition[condition]
	assert(rarityData and conditionData, "Invalid collectible rarity or condition")
	return math.floor(
		definition.baseValue * rarityData.multiplier * conditionData.multiplier * (variantMultiplier or 1)
	)
end

return Value
