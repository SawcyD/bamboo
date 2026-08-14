--!strict
-- Sickles domain: what a sickle is, what tiers exist, and what a given one is
-- worth in a swing.
--
--	local Sickles = Core:GetDomain("Sickles")
--
--	Sickles.Definitions.Get("golden_scythe")
--	Sickles.Stats.Compute(equippedId, swingLevel, multiLevel, baseSwingTime)
--	Sickles.Tiers.Get(definition.tier).color
--
-- Ownership, equipping, and crate rolls belong to SickleService and CrateService.

local Definitions = require(script:WaitForChild("Catalog"))

return {
	Types = require(script:WaitForChild("Types")),
	Tiers = require(script:WaitForChild("Tiers")),
	Abilities = require(script:WaitForChild("Abilities")),
	Definitions = Definitions,
	Stats = require(script:WaitForChild("Stats")),
}
