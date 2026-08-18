--!strict
-- Bamboo domain: the shared rules of the farm loop.
--
--	local Bamboo = Core:GetDomain("Bamboo")
--
--	Bamboo.Field.MaxStalks
--	Bamboo.Rarity.Roll(rng)
--	Bamboo.Value.SwingTime(level)
--
-- Everything here is deterministic and side-effect free. Ownership, money,
-- persistence, and authoritative rolls belong to BambooService and
-- FarmEconomyService.

return {
	Types = require(script:WaitForChild("Types")),
	Field = require(script:WaitForChild("Field")),
	Rarity = require(script:WaitForChild("Rarity")),
	Mutations = require(script:WaitForChild("Mutations")),
	Drops = require(script:WaitForChild("Drops")),
	Tool = require(script:WaitForChild("Tool")),
	Upgrades = require(script:WaitForChild("Upgrades")),
	Economy = require(script:WaitForChild("Economy")),
	Combo = require(script:WaitForChild("Combo")),
	Value = require(script:WaitForChild("Value")),
}
