--!strict
-- Collecting earnings and buying upgrades — the two places money moves.
--
-- Both are fully server-decided: the Cash Collector is polled server-side from
-- the character's position, and upgrade costs are recomputed from the player's
-- stored level rather than trusted from the request.
--
-- Money is never created anywhere else. Straw sells itself automatically as
-- soon as a batch completes (ProcessingService), landing in PendingEarnings;
-- this service is the only place PendingEarnings ever becomes spendable Money.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Bamboo = Core:GetDomain("Bamboo")
local Relay = Core:GetShared("Network")

local FarmEconomyService = {}
local Framework

local COLLECT_TICK_SECONDS = 0.35
-- Extra radius around the pad so players don't have to stand dead centre.
local COLLECTOR_PADDING = 3

-- ── collecting earnings ─────────────────────────────────────────────────────

local function _isAtCollector(root: BasePart, collector: BasePart): boolean
	local offset = collector.CFrame:PointToObjectSpace(root.Position)
	local half = collector.Size * 0.5
	return math.abs(offset.X) <= half.X + COLLECTOR_PADDING
		and math.abs(offset.Z) <= half.Z + COLLECTOR_PADDING
		and math.abs(offset.Y) <= 8
end

--[[
	Moves a player's pending earnings into their spendable Money. Safe to call
	when there is nothing pending (a no-op).
	@param player Player The collector.
	@return number Money actually collected (0 if there was nothing pending).
]]
function FarmEconomyService.CollectEarnings(player: Player): number
	local DataService = Framework:GetService("DataService")

	local pending = DataService.Get(player, "PendingEarnings") or 0
	if pending <= 0 then
		return 0
	end

	-- Read once, then a single atomic pair of writes, so the player is never
	-- mid-collection with earnings cleared but Money not yet credited (or
	-- collected twice by two ticks landing back-to-back).
	DataService.Set(player, "PendingEarnings", 0)
	local money = DataService.Increment(player, "Money", pending) or 0

	Relay.Bamboo.Sold.sendTo({ amount = pending, money = money }, player)
	return pending
end

local function _tickCollecting()
	local PlotService = Framework:GetService("PlotService")

	for _, player in Players:GetPlayers() do
		local plot = PlotService.GetPlot(player)
		if not plot then
			continue
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			continue
		end
		if _isAtCollector(root, plot.CashCollector) then
			FarmEconomyService.CollectEarnings(player)
		end
	end
end

-- ── upgrades ─────────────────────────────────────────────────────────────────

local function _onBuyUpgrade(payload: any, player: Player)
	local DataService = Framework:GetService("DataService")

	local upgradeId = payload.upgradeId :: string
	local def = Bamboo.Upgrades.Get(upgradeId)
	if not def then
		return
	end

	local level = DataService.Get(player, def.dataKey) or 0
	local function reject()
		Relay.Bamboo.UpgradeResult.sendTo({ upgradeId = upgradeId, ok = false, level = level }, player)
	end

	if level >= def.maxLevel then
		return reject()
	end

	local cost = Bamboo.Value.UpgradeCost(upgradeId, level)
	local money = DataService.Get(player, "Money") or 0
	if money < cost then
		return reject()
	end

	DataService.Increment(player, "Money", -cost)
	local newLevel = DataService.Increment(player, def.dataKey, 1) or level + 1

	-- Field Density changes how many stalks exist, so the plot has to react.
	if upgradeId == "Density" then
		local PlotService = Framework:GetService("PlotService")
		local BambooService = Framework:GetService("BambooService")
		local plot = PlotService.GetPlot(player)
		if plot then
			BambooService.SyncFieldSize(plot)
		end
	end

	Relay.Bamboo.UpgradeResult.sendTo({ upgradeId = upgradeId, ok = true, level = newLevel }, player)
end

-- ── lifecycle ────────────────────────────────────────────────────────────────

function FarmEconomyService:Start(fw: any)
	Framework = fw

	Relay.Bamboo.BuyUpgrade.listen(_onBuyUpgrade)
	Relay.Bamboo.CollectEarnings.listen(function(_payload: any, player: Player)
		FarmEconomyService.CollectEarnings(player)
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < COLLECT_TICK_SECONDS then
			return
		end
		accumulator = 0
		_tickCollecting()
	end)
end

return FarmEconomyService
