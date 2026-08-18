--!strict
-- Sickle abilities: the reason a Legendary is exciting rather than just bigger.
--
-- Every ability is resolved on the server during swing resolution. Potency is
-- stored on the sickle definition, so the same ability can appear at different
-- strengths across tiers.

local Types = require(script.Parent:WaitForChild("Types"))

local Abilities = {}

export type Definition = Types.AbilityDefinition

local definitions: { [string]: Definition } = {
	Chain = {
		id = "Chain",
		name = "Chain Cut",
		description = "Breaking a stalk can chain into a neighbour.",
	},
	Reaper = {
		id = "Reaper",
		name = "Reaper",
		description = "Hits can fell a stalk in one strike.",
	},
	Bountiful = {
		id = "Bountiful",
		name = "Bountiful",
		description = "Broken stalks can pay out double.",
	},
	Magnet = {
		id = "Magnet",
		name = "Magnet",
		description = "Pulls ground drops in from much further away.",
	},
}

Abilities.Definitions = definitions

-- How far Chain reaches to find its next stalk, in studs.
Abilities.ChainRadius = 9
-- Magnet multiplies the base pickup radius by this.
Abilities.MagnetRadiusMultiplier = 2.5
-- Bountiful multiplies a broken stalk's reward by this when it procs.
Abilities.BountifulMultiplier = 2

--[[
	Looks up an ability definition.
	@param id string? Ability id, or nil for a sickle without one.
	@return Definition? The definition, or nil when absent or unknown.
]]
function Abilities.Get(id: string?): Definition?
	if id == nil then
		return nil
	end
	return definitions[id]
end

--[[
	Player-facing text for a sickle's ability, with its potency filled in.
	@param id string? Ability id.
	@param potency number Chance or multiplier, as stored on the sickle.
	@return string? One line for the sickle card, or nil when there is no ability.
]]
function Abilities.Describe(id: string?, potency: number): string?
	local definition = Abilities.Get(id)
	if not definition then
		return nil
	end

	if definition.id == "Magnet" then
		return string.format("%s — %.1fx drop pickup range", definition.name, Abilities.MagnetRadiusMultiplier)
	end
	return string.format("%s — %.0f%% chance", definition.name, potency * 100)
end

return Abilities
