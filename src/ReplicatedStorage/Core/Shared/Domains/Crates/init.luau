--!strict
-- Crates domain: what a crate costs, what is inside it, and at what odds.
--
--	local Crates = Core:GetDomain("Crates")
--
--	Crates.Definitions.List()
--	Crates.Odds.Entries("jade_crate")    -- for the rewards grid
--	Crates.Odds.Roll("jade_crate", rng)  -- server-authoritative when server-run
--
-- Spending money and granting the result belong to CrateService.

local Definitions = require(script:WaitForChild("Catalog"))

-- How many crates one request may open at once. The UI offers 1 / 2 / 4.
local BulkAmounts = table.freeze({ 1, 2, 4 })

-- Auto-open pacing. Slower than the server's rate limit on purpose: the loop
-- should read as a steady stream of results, not a flood.
local AutoOpenIntervalSeconds = 0.85

return {
	Definitions = Definitions,
	Odds = require(script:WaitForChild("Odds")),
	Luck = require(script:WaitForChild("Luck")),
	BulkAmounts = BulkAmounts,
	MaxBulk = 4,
	AutoOpenIntervalSeconds = AutoOpenIntervalSeconds,
}
