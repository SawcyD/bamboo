--!strict
-- Bamboo rarity rule table plus the per-stalk visual variation spreads.
--
-- Rolling is pure here: callers pass their own Random so the server keeps the
-- authoritative stream and the client can preview without affecting it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local RNG = Core:Get("RNG")

local Types = require(script.Parent:WaitForChild("Types"))

local Rarity = {}

export type Definition = Types.RarityDefinition

local definitions: { [string]: Definition } = {
	Normal = {
		id = "Normal",
		name = "Normal",
		chance = 85,
		rewardMultiplier = 1,
		health = 3,
		heightScale = 1,
		thicknessScale = 1,
		color = Color3.fromRGB(112, 172, 84),
		impactWeight = 1,
	},
	Tall = {
		id = "Tall",
		name = "Tall",
		chance = 12,
		rewardMultiplier = 3,
		health = 3,
		heightScale = 1.55,
		thicknessScale = 1,
		color = Color3.fromRGB(148, 196, 92),
		impactWeight = 1.4,
	},
	Thick = {
		id = "Thick",
		name = "Thick",
		chance = 3,
		rewardMultiplier = 10,
		health = 3,
		-- Barely taller than Normal on purpose: Thick's read is *girth*. Letting it
		-- gain height too made it compete with Tall instead of contrasting with it.
		heightScale = 1.05,
		thicknessScale = 2.4,
		color = Color3.fromRGB(64, 104, 52),
		impactWeight = 2.4,
	},
}

Rarity.Definitions = definitions

-- Fixed order so every machine walks the same cumulative table.
Rarity.RollOrder = table.freeze({ "Normal", "Tall", "Thick" })

-- Per-stalk visual variation, so a field never reads as copied models.
Rarity.Variation = table.freeze({
	HeightSpread = 0.15, -- ±15%
	ThicknessSpread = 0.20, -- ±20%
	MaxTiltDegrees = 7,
	-- Raised with the forest height pass: a 16-stud stalk carrying only two leaves
	-- reads as a pole. Still low enough that a full field stays part-cheap.
	LeafCountMin = 3,
	LeafCountMax = 6,
	ColorJitter = 0.06, -- fraction of channel range
})

--[[
	Looks up a rarity, falling back to Normal for unknown ids.
	@param id string Rarity id such as "Thick".
	@return Definition The matching rarity, never nil.
]]
function Rarity.Get(id: string): Definition
	return definitions[id] or definitions.Normal
end

-- Rarity table in the shape RNG takes, built once. Rarest first, so the luck
-- weighting (which boosts the smallest weights hardest) lines up.
local _drops: { any } = {}
do
	for _, id in Rarity.RollOrder do
		table.insert(_drops, { name = id, weight = definitions[id].chance, rarity = id })
	end
	table.sort(_drops, function(a, b)
		return a.weight < b.weight
	end)
end

--[[
	Picks a rarity from the chance table.
	The caller owns the stream — the server must use its own so a client cannot
	influence what it gets.
	@param rng Random | RNG.Stream Stream to roll from.
	@param luck number? Bias toward rarer bamboo; 0 or nil for base odds.
	@return string The chosen rarity id.
]]
function Rarity.Roll(rng: any, luck: number?): string
	local effectiveLuck = luck or 0

	-- Fast path: no luck means the plain cumulative walk, which keeps the common
	-- case free of the RNG module's sorting work.
	if effectiveLuck <= 0 and typeof(rng) == "Random" then
		local roll = rng:NextNumber(0, 100)
		local cumulative = 0
		for _, id in Rarity.RollOrder do
			cumulative += definitions[id].chance
			if roll <= cumulative then
				return id
			end
		end
		return "Normal"
	end

	if type(rng) == "table" and type(rng.Roll) == "function" then
		return rng:Roll(_drops, effectiveLuck).name
	end

	local stream = RNG.NewStream((rng :: Random):NextInteger(1, 2 ^ 30))
	return stream:Roll(_drops, effectiveLuck).name
end

--[[
	Chance of rolling a rarity at a given luck, for previews and tests.
	@param id string Rarity id.
	@param luck number? Bias toward rarer bamboo; 0 or nil for base odds.
	@return number Percent chance.
]]
function Rarity.ChanceOf(id: string, luck: number?): number
	return RNG.GetChance(_drops, id, luck or 0)
end

--[[
	Rolls one stalk's look from its rarity and the variation spreads.
	@param rarityId string Rarity id the stalk was rolled as.
	@param rng Random Stream to roll from.
	@return Types.StalkVisual Values a builder needs to make this stalk unique.
]]
function Rarity.RollVisual(rarityId: string, rng: Random): Types.StalkVisual
	local definition = Rarity.Get(rarityId)
	local v = Rarity.Variation

	return {
		rarity = definition.id,
		-- Callers overwrite this with the stalk's rolled mutation; plain by default.
		mutation = "None",
		heightScale = definition.heightScale * (1 + rng:NextNumber(-v.HeightSpread, v.HeightSpread)),
		thicknessScale = definition.thicknessScale * (1 + rng:NextNumber(-v.ThicknessSpread, v.ThicknessSpread)),
		tiltDegrees = rng:NextNumber(0, v.MaxTiltDegrees),
		tiltAngle = rng:NextNumber(0, math.pi * 2),
		leafCount = rng:NextInteger(v.LeafCountMin, v.LeafCountMax),
		color = Color3.new(
			math.clamp(definition.color.R + rng:NextNumber(-v.ColorJitter, v.ColorJitter), 0, 1),
			math.clamp(definition.color.G + rng:NextNumber(-v.ColorJitter, v.ColorJitter), 0, 1),
			math.clamp(definition.color.B + rng:NextNumber(-v.ColorJitter, v.ColorJitter), 0, 1)
		),
	}
end

return Rarity
