--!strict
-- Every derived number in the farm loop, in one place.
--
-- All of these are pure, so the client can preview an upgrade and the server can
-- enforce the same result without a round trip. The server still owns the
-- authoritative call — a preview is never a grant.

local Economy = require(script.Parent:WaitForChild("Economy"))
local Field = require(script.Parent:WaitForChild("Field"))
local Mutations = require(script.Parent:WaitForChild("Mutations"))
local Rarity = require(script.Parent:WaitForChild("Rarity"))
local Tool = require(script.Parent:WaitForChild("Tool"))
local Upgrades = require(script.Parent:WaitForChild("Upgrades"))

local Value = {}

--[[
	Seconds one swing takes.
	@param level number The player's Swing Speed level.
	@return number Swing time in seconds.
]]
function Value.SwingTime(level: number): number
	return Tool.BaseSwingTime / (1 + level * 0.08)
end

--[[
	How many stalks a single swing may damage.
	@param level number The player's Multi-Hit level.
	@return number Target count, starting at the sickle's base multi-hit.
]]
function Value.MultiHitTargets(level: number): number
	return Tool.BaseMultiHit + math.floor(level / 2)
end

--[[
	Bamboo granted per destroyed stalk, before the rarity multiplier.
	@param level number The player's Yield level.
	@return number Bamboo per stalk.
]]
function Value.YieldPerStalk(level: number): number
	return 2 + math.floor(level / 2)
end

--[[
	Bamboo a single stalk actually gives when it breaks.

	Type and mutation are separate layers and both apply, which is what makes a
	Golden Thick worth chasing. This is the only place the two are combined —
	no service multiplies them again.

	@param rarityId string Type of the stalk that broke (Normal/Tall/Thick).
	@param yieldLevel number The player's Yield level.
	@param mutationId string? Mutation on the stalk; nil or "None" for plain.
	@return number Bamboo to add to the bag, rounded down to whole units.
]]
function Value.StalkReward(rarityId: string, yieldLevel: number, mutationId: string?): number
	local base = Value.YieldPerStalk(yieldLevel) * Rarity.Get(rarityId).rewardMultiplier
	return math.floor(base * Mutations.Get(mutationId).valueMultiplier)
end

--[[
	How much bamboo the bag holds.
	@param level number The player's Storage level.
	@return number Bag capacity.
]]
function Value.BagCapacity(level: number): number
	return Economy.BagCapacity + level * 25
end

--[[
	Seconds a cut stalk takes to return to Mature.
	@param level number The player's Growth Speed level.
	@return number Regrow time in seconds.
]]
function Value.RegrowSeconds(level: number): number
	return Field.RegrowSeconds / (1 + level * 0.06)
end

--[[
	Seconds before a regrowing stalk leaves the Shoot stage.
	Scaled with regrow time so the stages stay proportional at every level.
	@param level number The player's Growth Speed level.
	@return number Shoot duration in seconds.
]]
function Value.ShootSeconds(level: number): number
	return Value.RegrowSeconds(level) * (Field.ShootSeconds / Field.RegrowSeconds)
end

--[[
	Growth stage a stalk should show, accounting for the owner's Growth Speed.
	@param secondsSinceCut number Seconds elapsed since the stalk was cut.
	@param level number The player's Growth Speed level.
	@return number A Field.Stage value.
]]
function Value.StageAt(secondsSinceCut: number, level: number): number
	if secondsSinceCut >= Value.RegrowSeconds(level) then
		return Field.Stage.Mature
	elseif secondsSinceCut >= Value.ShootSeconds(level) then
		return Field.Stage.Young
	end
	return Field.Stage.Shoot
end

--[[
	Continuous visual scale for a regrowing stalk, from a sprout up to full
	height. Smoothstepped so it reads as a plant reaching rather than a number
	counting up: slow at first, quickest mid-growth, settling into full size.
	@param secondsSinceCut number Seconds elapsed since the stalk was cut.
	@param level number The player's Growth Speed level.
	@return number Scale from StageScale[Shoot] up to 1.
]]
function Value.GrowthScale(secondsSinceCut: number, level: number): number
	local t = math.clamp(secondsSinceCut / Value.RegrowSeconds(level), 0, 1)
	-- smoothstep: t^2 * (3 - 2t)
	local eased = t * t * (3 - 2 * t)
	local shoot = Field.StageScale[Field.Stage.Shoot]
	return shoot + (1 - shoot) * eased
end

--[[
	How many stalks the field holds.
	@param level number The player's Density level.
	@return number Stalk count.
]]
function Value.MaxStalks(level: number): number
	return Field.MaxStalks + level * 8
end

--[[
	The largest field any player can ever reach, so plots can pre-build enough
	planting slots up front instead of re-laying the grid on every upgrade.
	@return number Stalk count at maximum Density.
]]
function Value.MaxPossibleStalks(): number
	local definition = Upgrades.Get("Density")
	return Value.MaxStalks(if definition then definition.maxLevel else 0)
end

--[[
	Cost of the next level of an upgrade.
	@param upgradeId string Upgrade id such as "SwingSpeed".
	@param currentLevel number Level the player is on now.
	@return number Rounded money cost; math.huge for an unknown upgrade.
]]
function Value.UpgradeCost(upgradeId: string, currentLevel: number): number
	local definition = Upgrades.Get(upgradeId)
	if not definition then
		return math.huge
	end
	return math.floor(definition.baseCost * definition.costGrowth ^ currentLevel + 0.5)
end

--[[
	The stat an upgrade produces at a given level, for board displays.
	@param upgradeId string Upgrade id such as "Yield".
	@param level number Level to evaluate.
	@return number The stat value; 0 for an unknown upgrade.
]]
function Value.StatAtLevel(upgradeId: string, level: number): number
	if upgradeId == "SwingSpeed" then
		return Value.SwingTime(level)
	elseif upgradeId == "MultiHit" then
		return Value.MultiHitTargets(level)
	elseif upgradeId == "Yield" then
		return Value.YieldPerStalk(level)
	elseif upgradeId == "Storage" then
		return Value.BagCapacity(level)
	elseif upgradeId == "GrowthSpeed" then
		return Value.RegrowSeconds(level)
	elseif upgradeId == "Density" then
		return Value.MaxStalks(level)
	end
	return 0
end

--[[
	Whether an upgrade can still be bought.
	@param upgradeId string Upgrade id.
	@param level number Level the player is on now.
	@return boolean False once the upgrade is maxed or unknown.
]]
function Value.CanUpgrade(upgradeId: string, level: number): boolean
	local definition = Upgrades.Get(upgradeId)
	return definition ~= nil and level < definition.maxLevel
end

return Value
