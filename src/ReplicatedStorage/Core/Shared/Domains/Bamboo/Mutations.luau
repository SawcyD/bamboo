--!strict
-- Mutations: a second rarity layer, rolled independently of bamboo type.
--
-- Type (Normal/Tall/Thick) is the *shape* of the stalk. A mutation is a
-- property layered on top, so the two combine:
--
--	Thick + Golden  →  Golden Thick Bamboo
--
-- Both multipliers apply, which is what makes a Golden Thick worth chasing.
-- The combined value lives in Value.StalkReward; nothing else multiplies.
--
-- Rolling is pure — the caller passes its own stream, so the server keeps the
-- authoritative roll and the client can preview odds without touching it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local RNG = Core:Get("RNG")

local Types = require(script.Parent:WaitForChild("Types"))

local Mutations = {}

export type Definition = Types.MutationDefinition

-- `weight` is a relative roll weight, not a percentage — the RNG module works
-- in weights, and using them directly means the table can be retuned without
-- having to re-balance every other row to keep a sum of 100.
local definitions: { [string]: Definition } = {
	None = {
		id = "None",
		name = "",
		valueMultiplier = 1,
		weight = 8755,
		color = Color3.fromRGB(112, 172, 84),
		nodeColor = Color3.fromRGB(86, 132, 64),
		leafColor = Color3.fromRGB(112, 172, 84),
		material = Enum.Material.Grass,
		glow = 0,
		announce = false,
		revealWeight = 1,
	},
	Dewy = {
		id = "Dewy",
		name = "Dewy",
		valueMultiplier = 1.5,
		weight = 800,
		color = Color3.fromRGB(150, 226, 140),
		nodeColor = Color3.fromRGB(110, 190, 170),
		leafColor = Color3.fromRGB(168, 240, 190),
		material = Enum.Material.Glass,
		glow = 0.1,
		announce = false,
		revealWeight = 1.2,
	},
	Red = {
		id = "Red",
		name = "Red",
		valueMultiplier = 3,
		weight = 300,
		color = Color3.fromRGB(190, 62, 44),
		nodeColor = Color3.fromRGB(126, 34, 26),
		leafColor = Color3.fromRGB(150, 70, 46),
		material = Enum.Material.Grass,
		glow = 0.15,
		announce = false,
		revealWeight = 1.6,
	},
	Black = {
		id = "Black",
		name = "Black",
		valueMultiplier = 7,
		weight = 100,
		color = Color3.fromRGB(44, 44, 50),
		-- Bright nodes are what keeps a near-black stalk readable on a phone
		-- against a dark green field.
		nodeColor = Color3.fromRGB(190, 196, 210),
		leafColor = Color3.fromRGB(70, 74, 84),
		material = Enum.Material.Slate,
		glow = 0.2,
		announce = false,
		revealWeight = 2.2,
	},
	Crystal = {
		id = "Crystal",
		name = "Crystal",
		valueMultiplier = 20,
		weight = 35,
		color = Color3.fromRGB(150, 240, 245),
		nodeColor = Color3.fromRGB(220, 255, 255),
		leafColor = Color3.fromRGB(180, 245, 250),
		material = Enum.Material.Glass,
		glow = 0.6,
		announce = false,
		revealWeight = 3.2,
	},
	Golden = {
		id = "Golden",
		name = "Golden",
		valueMultiplier = 75,
		weight = 9,
		color = Color3.fromRGB(255, 200, 60),
		nodeColor = Color3.fromRGB(255, 236, 150),
		leafColor = Color3.fromRGB(255, 214, 92),
		material = Enum.Material.Neon,
		glow = 1,
		announce = true,
		revealWeight = 4.5,
	},
	Ancient = {
		id = "Ancient",
		name = "Ancient",
		valueMultiplier = 250,
		weight = 1,
		color = Color3.fromRGB(126, 236, 214),
		nodeColor = Color3.fromRGB(214, 255, 246),
		leafColor = Color3.fromRGB(168, 200, 255),
		material = Enum.Material.Neon,
		glow = 1,
		announce = true,
		revealWeight = 6,
	},
}

Mutations.Definitions = definitions

-- Commonest to rarest. Also the order collection entries are listed in.
Mutations.Order = table.freeze({ "None", "Dewy", "Red", "Black", "Crystal", "Golden", "Ancient" })

-- Everything except None, for collection tracking and reward grids.
Mutations.Collectable = table.freeze({ "Dewy", "Red", "Black", "Crystal", "Golden", "Ancient" })

-- Mutations at or above this multiplier get the heavier break treatment
-- (hit-stop, bigger debris, unique sting).
Mutations.EventThreshold = 20

-- Luck can never push a mutation past this share of the roll, so no amount of
-- stacking makes Golden or Ancient routine.
Mutations.MaxLuck = 3

-- RNG-shaped drops table, built once. Rarest first so the luck weighting —
-- which boosts the smallest weights hardest — lines up.
local _drops: { any } = {}
do
	for _, id in Mutations.Order do
		table.insert(_drops, { name = id, weight = definitions[id].weight, rarity = id })
	end
	table.sort(_drops, function(a, b)
		return a.weight < b.weight
	end)
end

--[[
	Looks up a mutation, falling back to None for unknown ids.
	@param id string? Mutation id such as "Golden"; nil is treated as None.
	@return Definition The matching mutation, never nil.
]]
function Mutations.Get(id: string?): Definition
	if id == nil then
		return definitions.None
	end
	return definitions[id] or definitions.None
end

--[[
	Whether a mutation is anything other than plain bamboo.
	@param id string? Mutation id.
	@return boolean False for None, nil, or an unknown id.
]]
function Mutations.IsMutated(id: string?): boolean
	return id ~= nil and id ~= "None" and definitions[id] ~= nil
end

--[[
	Rolls a mutation, independently of the stalk's type.
	The caller owns the stream — the server must pass its own so a client can
	never influence or predict what it gets.
	@param rng Random | RNG.Stream Stream to roll from.
	@param luck number? Bias toward rarer mutations; 0 or nil for base odds.
	@return string The chosen mutation id, "None" included.
]]
function Mutations.Roll(rng: any, luck: number?): string
	local effectiveLuck = math.clamp(luck or 0, 0, Mutations.MaxLuck)

	if type(rng) == "table" and type(rng.Roll) == "function" then
		return rng:Roll(_drops, effectiveLuck).name
	end

	local stream = RNG.NewStream((rng :: Random):NextInteger(1, 2 ^ 30))
	return stream:Roll(_drops, effectiveLuck).name
end

--[[
	Percentage chance of a mutation at a given luck, for previews and tests.
	@param id string Mutation id.
	@param luck number? Bias toward rarer mutations; 0 or nil for base odds.
	@return number Percent chance.
]]
function Mutations.ChanceOf(id: string, luck: number?): number
	return RNG.GetChance(_drops, id, math.clamp(luck or 0, 0, Mutations.MaxLuck))
end

--[[
	Display name for a type/mutation pair, e.g. "Golden Thick Bamboo".
	@param typeName string The bamboo type's display name.
	@param mutationId string? Mutation id; None yields just the type.
	@return string Full name, ready for a headline or collection entry.
]]
function Mutations.DisplayName(typeName: string, mutationId: string?): string
	local mutation = Mutations.Get(mutationId)
	if mutation.name == "" then
		return typeName .. " Bamboo"
	end
	return string.format("%s %s Bamboo", mutation.name, typeName)
end

--[[
	Whether breaking this mutation should get the full event treatment.
	@param id string? Mutation id.
	@return boolean True for Crystal and above.
]]
function Mutations.IsEvent(id: string?): boolean
	return Mutations.Get(id).valueMultiplier >= Mutations.EventThreshold
end

return Mutations
