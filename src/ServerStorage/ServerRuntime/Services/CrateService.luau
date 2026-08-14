--!strict
-- Crate opening: charge, roll, grant.
--
-- The client sends only "open this crate, N times". Everything that decides an
-- outcome — whether they can afford it, what they win — happens here on a
-- server-owned random stream the client cannot reach or predict.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Crates = Core:GetDomain("Crates")
local RNG = Core:Get("RNG")
local Sickles = Core:GetDomain("Sickles")
local Relay = Core:GetShared("Network")

local CrateService = {}
local Framework

-- One shared stream for the whole server. Seeded from the clock so restarts
-- don't replay the same sequence of pulls.
local _rng = RNG.NewStream(math.floor(os.clock() * 1e6) % 2 ^ 30)

local function _reject(player: Player, crateId: string, reason: string)
	Relay.Crates.CrateRejected.sendTo({ crateId = crateId, reason = reason }, player)
end

local function _onOpenCrate(payload: any, player: Player)
	local DataService = Framework:GetService("DataService")
	local SickleService = Framework:GetService("SickleService")
	local LuckService = Framework:GetService("LuckService")

	local crateId = payload.crateId :: string
	local amount = payload.amount :: number

	local crate = Crates.Definitions.Get(crateId)
	if not crate then
		return _reject(player, crateId, "unknown")
	end
	if amount > Crates.MaxBulk then
		return _reject(player, crateId, "amount")
	end

	local totalCost = crate.cost * amount
	local money = DataService.Get(player, "Money") or 0
	if money < totalCost then
		return _reject(player, crateId, "money")
	end

	-- Charge once, up front, so a mid-loop error can never grant free sickles.
	DataService.Increment(player, "Money", -totalCost)

	-- Luck is read once for the whole request, from the server's own state.
	local luck = LuckService.GetLuck(player)

	local results: { any } = {}
	for _ = 1, amount do
		local sickleId = Crates.Odds.Roll(crateId, _rng, luck)
		if not sickleId then
			continue
		end
		local definition = Sickles.Definitions.Get(sickleId)
		if not definition then
			continue
		end

		local isNew = SickleService.Grant(player, sickleId)
		table.insert(results, {
			sickleId = sickleId,
			tier = definition.tier,
			isNew = isNew,
		})
	end

	if #results == 0 then
		-- Should be unreachable: crates are validated as non-empty at
		-- registration. Refund rather than silently take the money.
		DataService.Increment(player, "Money", totalCost)
		return _reject(player, crateId, "empty")
	end

	DataService.Increment(player, "CratesOpened", #results)

	Relay.Crates.CrateResult.sendTo({
		crateId = crateId,
		results = results,
		spent = totalCost,
		luck = luck,
	}, player)
end

function CrateService:Start(fw: any)
	Framework = fw
	Relay.Crates.OpenCrate.listen(_onOpenCrate)
end

--[[
	Cost of opening a crate a number of times.
	@param crateId string Crate id.
	@param amount number How many to open.
	@return number Total money cost; math.huge for an unknown crate.
]]
function CrateService.GetCost(crateId: string, amount: number): number
	local crate = Crates.Definitions.Get(crateId)
	if not crate then
		return math.huge
	end
	return crate.cost * amount
end

return CrateService
