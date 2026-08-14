--!strict
-- Combines the equipped sickle with the player's upgrade levels into the stats
-- a swing actually resolves with.
--
-- §17's separation holds: the sickle sets the *base* damage, range, and
-- multi-hit; upgrades add on top. Both the client preview and the server's
-- authoritative swing call this, so they can never disagree.

local Definitions = require(script.Parent:WaitForChild("Catalog"))
local Types = require(script.Parent:WaitForChild("Types"))

local Stats = {}

export type EffectiveStats = Types.EffectiveStats

--[[
	The definition a player is actually swinging, falling back to the starter
	when their saved id is missing or no longer in the catalog.
	@param sickleId string? The player's equipped sickle id.
	@return Types.SickleDefinition A definition, never nil.
]]
function Stats.Resolve(sickleId: string?): Types.SickleDefinition
	local definition = if sickleId then Definitions.Get(sickleId) else nil
	return definition or (Definitions.Get(Definitions.StarterId) :: Types.SickleDefinition)
end

--[[
	Full swing stats for a player.
	@param sickleId string? Equipped sickle id.
	@param swingSpeedLevel number Swing Speed upgrade level.
	@param multiHitLevel number Multi-Hit upgrade level.
	@param baseSwingTime number The tool's base swing time, from the Bamboo domain.
	@return EffectiveStats Damage, range, multi-hit, swing time, and ability.
]]
function Stats.Compute(
	sickleId: string?,
	swingSpeedLevel: number,
	multiHitLevel: number,
	baseSwingTime: number
): EffectiveStats
	local sickle = Stats.Resolve(sickleId)

	return {
		damage = sickle.damage,
		range = sickle.range,
		-- Sickle sets the base; the upgrade adds one target every two levels.
		multiHit = sickle.baseMultiHit + math.floor(multiHitLevel / 2),
		swingTime = baseSwingTime / (1 + swingSpeedLevel * 0.08),
		ability = sickle.ability,
		abilityPotency = sickle.abilityPotency or 0,
	}
end

--[[
	Whether a sickle carries a given ability, for gating server-side effects.
	@param sickleId string? Equipped sickle id.
	@param abilityId string Ability to test for.
	@return boolean True when the equipped sickle has that ability.
]]
function Stats.HasAbility(sickleId: string?, abilityId: string): boolean
	return Stats.Resolve(sickleId).ability == abilityId
end

--[[
	How many stalks a sickle sweeps, ignoring upgrades. For comparison cards.
	@param sickleId string Sickle id.
	@return number Base multi-hit from the definition.
]]
function Stats.BaseMultiHit(sickleId: string): number
	return Stats.Resolve(sickleId).baseMultiHit
end

return Stats
