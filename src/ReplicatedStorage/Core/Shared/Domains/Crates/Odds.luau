--!strict
-- Crate odds, luck-aware.
--
-- The weighting itself is delegated to `Core:Get("RNG")`, which already models
-- luck as "boost the rarest entries hardest". Doing it here too would be a
-- second implementation to keep in sync.
--
-- `Roll` is callable on both runtimes, but the *authoritative* roll must happen
-- in CrateService with the server's own stream and the server's own luck value.
-- A client roll is only ever a preview.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local RNG = Core:Get("RNG")

local Definitions = require(script.Parent:WaitForChild("Catalog"))
local Sickles = require(script.Parent.Parent:WaitForChild("Sickles"))

local Odds = {}

export type Entry = {
	sickleId: string,
	weight: number,
	chance: number, -- percent, after luck
}

-- Crate contents as an RNG drops array. Cached per crate: contents are frozen
-- at registration, so the array only has to be built once.
local _dropsCache: { [string]: { any } } = {}

local function _drops(crateId: string): { any }?
	local cached = _dropsCache[crateId]
	if cached then
		return cached
	end

	local crate = Definitions.Get(crateId)
	if not crate then
		return nil
	end

	local drops: { any } = {}
	for sickleId, weight in crate.contents do
		local sickle = Sickles.Definitions.Get(sickleId)
		table.insert(drops, {
			name = sickleId,
			weight = weight,
			rarity = if sickle then sickle.tier else "Common",
		})
	end

	-- Stable order, so the same seed and luck always give the same result.
	table.sort(drops, function(a, b)
		if a.weight ~= b.weight then
			return a.weight < b.weight
		end
		return a.name < b.name
	end)

	_dropsCache[crateId] = drops
	return drops
end

--[[
	Total base roll weight in a crate, ignoring luck.
	@param crateId string Crate id.
	@return number Sum of every entry's weight; 0 for an unknown crate.
]]
function Odds.TotalWeight(crateId: string): number
	local drops = _drops(crateId)
	if not drops then
		return 0
	end
	local total = 0
	for _, drop in drops do
		total += drop.weight
	end
	return total
end

--[[
	A crate's contents as percentage odds at a given luck, rarest first.
	This is what the "possible rewards" grid renders, so the grid updates as the
	player's luck changes.
	@param crateId string Crate id.
	@param luck number? Internal luck; 0 or nil for base odds.
	@return { Entry } Entries sorted rarest-first; empty for an unknown crate.
]]
function Odds.Entries(crateId: string, luck: number?): { Entry }
	local drops = _drops(crateId)
	if not drops then
		return {}
	end

	local effectiveLuck = luck or 0
	local entries: { Entry } = {}
	for _, drop in drops do
		table.insert(entries, {
			sickleId = drop.name,
			weight = drop.weight,
			chance = RNG.GetChance(drops, drop.name, effectiveLuck),
		})
	end

	-- Rarest first, so the grid leads with what the player is hoping for.
	table.sort(entries, function(a, b)
		if a.chance == b.chance then
			return a.sickleId < b.sickleId
		end
		return a.chance < b.chance
	end)

	return entries
end

--[[
	The chance of pulling one specific sickle from a crate.
	@param crateId string Crate id.
	@param sickleId string Sickle id.
	@param luck number? Internal luck; 0 or nil for base odds.
	@return number Percent chance; 0 when the sickle isn't in the crate.
]]
function Odds.ChanceOf(crateId: string, sickleId: string, luck: number?): number
	local drops = _drops(crateId)
	if not drops then
		return 0
	end
	return RNG.GetChance(drops, sickleId, luck or 0)
end

--[[
	Rolls one sickle out of a crate.
	The caller owns the stream — the server must pass its own so a client can
	never influence the outcome.
	@param crateId string Crate id.
	@param rng Random | RNG.Stream Stream to roll from.
	@param luck number? Internal luck; 0 or nil for base odds.
	@return string? The won sickle id, or nil for an unknown crate.
]]
function Odds.Roll(crateId: string, rng: any, luck: number?): string?
	local drops = _drops(crateId)
	if not drops or #drops == 0 then
		return nil
	end

	-- Accept either an RNG stream (which carries its own luck-aware Roll) or a
	-- plain Random, so callers aren't forced to build a stream for a preview.
	if type(rng) == "table" and type(rng.Roll) == "function" then
		return rng:Roll(drops, luck or 0).name
	end

	local stream = RNG.NewStream((rng :: Random):NextInteger(1, 2 ^ 30))
	return stream:Roll(drops, luck or 0).name
end

--[[
	The best tier a crate can produce, for sorting the crate list.
	@param crateId string Crate id.
	@return string Tier id of the rarest sickle inside; "Common" if unknown.
]]
function Odds.PeakTier(crateId: string): string
	local best = "Common"
	local drops = _drops(crateId)
	if not drops then
		return best
	end
	for _, drop in drops do
		local sickle = Sickles.Definitions.Get(drop.name)
		if sickle then
			best = Sickles.Tiers.Best(best, sickle.tier)
		end
	end
	return best
end

return Odds
