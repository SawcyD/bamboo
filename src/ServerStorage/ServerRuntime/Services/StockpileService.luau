--!strict
-- The farm stockpile: BambooStock -> CarriedBamboo, by request only.
--
-- The player triggers the stockpile's ProximityPrompt; the client only ever
-- asks ("give me bamboo to carry"), never says how much. The server looks up
-- the player's own plot, checks proximity, and moves the entire stockpile onto
-- the player — carrying has no capacity limit — but never from another
-- player's farm.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Relay = Core:GetShared("Network")

local StockpileService = {}
local Framework

-- Extra radius around the stockpile pad, matching the rest of the plot's
-- proximity checks so players don't have to stand dead centre.
local STOCKPILE_PADDING = 3

local function _isAtStockpile(root: BasePart, stockpile: BasePart): boolean
	local offset = stockpile.CFrame:PointToObjectSpace(root.Position)
	local half = stockpile.Size * 0.5
	return math.abs(offset.X) <= half.X + STOCKPILE_PADDING
		and math.abs(offset.Z) <= half.Z + STOCKPILE_PADDING
		and math.abs(offset.Y) <= 8
end

--[[
	Moves the player's entire stockpile onto their carried amount. Safe to call
	repeatedly (idempotent no-op once the stockpile is empty).
	@param player Player The player taking bamboo.
	@return number Bamboo actually moved (0 if there was nothing to take).
]]
function StockpileService.Take(player: Player): number
	local DataService = Framework:GetService("DataService")

	local stock = DataService.Get(player, "BambooStock") or 0
	if stock <= 0 then
		return 0
	end

	-- Two increments, same callback, no yield between them: the bamboo is never
	-- observably in both places or in neither.
	DataService.Increment(player, "BambooStock", -stock)
	DataService.Increment(player, "CarriedBamboo", stock)
	return stock
end

local function _onTakeRequest(_payload: any, player: Player)
	local PlotService = Framework:GetService("PlotService")

	local plot = PlotService.GetPlot(player)
	if not plot then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	if not _isAtStockpile(root, plot.Stockpile) then
		return
	end

	StockpileService.Take(player)
end

-- ── lifecycle ────────────────────────────────────────────────────────────────

function StockpileService:Start(fw: any)
	Framework = fw

	Relay.Bamboo.TakeFromStockpile.listen(_onTakeRequest)
end

return StockpileService
