--!strict
-- Selling and upgrade purchases — the two places money moves in Phase 1.
--
-- Both are fully server-decided: the sell zone is polled server-side from the
-- character's position, and upgrade costs are recomputed from the player's
-- stored level rather than trusted from the request.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Bamboo = Core:GetDomain("Bamboo")
local Relay = Core:GetShared("Network")

local FarmEconomyService = {}
local Framework

local SELL_TICK_SECONDS = 0.35
-- Extra radius around the sell pad so players don't have to stand dead centre.
local SELL_PAD_PADDING = 3

-- ── selling ──────────────────────────────────────────────────────────────────

local function _isInSellZone(root: BasePart, sellZone: BasePart): boolean
	local offset = sellZone.CFrame:PointToObjectSpace(root.Position)
	local half = sellZone.Size * 0.5
	return math.abs(offset.X) <= half.X + SELL_PAD_PADDING
		and math.abs(offset.Z) <= half.Z + SELL_PAD_PADDING
		and math.abs(offset.Y) <= 8
end

--[[
	Empties a player's bag into money. Safe to call when the bag is empty.
	@param player Player The seller.
	@return number Bamboo sold (0 when there was nothing to sell).
]]
function FarmEconomyService.SellBag(player: Player): number
	local DataService = Framework:GetService("DataService")

	local bag = DataService.Get(player, "Bag") or 0
	if bag <= 0 then
		return 0
	end

	local payout = Bamboo.Economy.SellValue(bag)
	DataService.Set(player, "Bag", 0)
	local money = DataService.Increment(player, "Money", payout) or 0

	Relay.Bamboo.Sold.sendTo({ amount = bag, money = money }, player)
	return bag
end

local function _tickSelling()
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
		if _isInSellZone(root, plot.SellZone) then
			FarmEconomyService.SellBag(player)
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

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < SELL_TICK_SECONDS then
			return
		end
		accumulator = 0
		_tickSelling()
	end)
end

return FarmEconomyService
