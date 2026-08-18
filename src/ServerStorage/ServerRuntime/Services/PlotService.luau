--!strict
-- Owns the physical plot: allocation, ground geometry, field slot positions,
-- the sell zone, and the three upgrade boards.
--
-- Everything here is built at runtime so Phase 1 needs no pre-authored place
-- file. Once real environment art exists, swap `_buildPlotModel` for a clone of
-- the authored plot; the rest of the game only reads the named children.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Bamboo = Core:GetDomain("Bamboo")

local PlotService = {}
local Framework

local PLOT_SIZE = 160
local PLOT_SPACING = 220
local FIELD_SIZE = 96
local SELL_ZONE_SIZE = Vector3.new(18, 1, 18)
local BOARD_SIZE = Vector3.new(8, 9, 1)
-- Boards are laid out along an arc of this width at this radius.
local BOARD_ARC_DEGREES = 100
local BOARD_ARC_RADIUS = 26
local PLOT_COUNT = 12

export type Plot = {
	Id: string,
	Index: number,
	Model: Model,
	Origin: CFrame,
	Field: BasePart,
	SellZone: BasePart,
	Slots: { CFrame },
	Owner: Player?,
}

local _plots: { Plot } = {}
local _plotsByPlayer: { [Player]: Plot } = {}
local _plotsFolder: Folder

-- ── geometry helpers ─────────────────────────────────────────────────────────

local function _newPart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Ground CFrames for every planting slot. The clustered layout itself lives in
-- the domain (Field.BuildSlots) so it stays deterministic and testable; this
-- only lifts the local offsets into world space.
local function _buildSlots(fieldCFrame: CFrame, count: number, rng: Random): { CFrame }
	local slots: { CFrame } = {}
	for _, offset in Bamboo.Field.BuildSlots(count, FIELD_SIZE * 0.5, rng) do
		table.insert(slots, fieldCFrame * CFrame.new(offset))
	end
	return slots
end

-- Boards sit on an arc across the back of the plot, angled inward, so six of
-- them stay readable from the walk-up instead of running off the edge.
local function _buildBoard(plotModel: Model, origin: CFrame, upgradeId: string, slot: number, total: number)
	local def = Bamboo.Upgrades.Get(upgradeId)

	local spread = math.rad(BOARD_ARC_DEGREES)
	local t = if total > 1 then (slot - 1) / (total - 1) - 0.5 else 0
	local angle = t * spread

	local offset = CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -BOARD_ARC_RADIUS)
	local position = origin * CFrame.new(0, BOARD_SIZE.Y * 0.5, -PLOT_SIZE * 0.5 + BOARD_ARC_RADIUS + 8) * offset

	local board = _newPart(
		"UpgradeBoard_" .. upgradeId,
		BOARD_SIZE,
		position * CFrame.Angles(0, math.pi + angle, 0),
		Color3.fromRGB(94, 68, 44),
		plotModel
	)
	board.Material = Enum.Material.WoodPlanks
	board.CanCollide = true
	board:SetAttribute("UpgradeId", def.id)
	board:AddTag("BambooUpgradeBoard")
end

local function _buildPlotModel(index: number): Plot
	local origin = CFrame.new((index - 1) * PLOT_SPACING, 0, 0)
	local plotId = string.format("Plot%02d", index)

	local model = Instance.new("Model")
	model.Name = plotId
	model:SetAttribute("PlotId", plotId)
	model:SetAttribute("PlotIndex", index)

	local ground = _newPart(
		"Ground",
		Vector3.new(PLOT_SIZE, 2, PLOT_SIZE),
		origin * CFrame.new(0, -1, 0),
		Color3.fromRGB(88, 122, 70),
		model
	)
	ground.Material = Enum.Material.Grass

	local field = _newPart(
		"Field",
		Vector3.new(FIELD_SIZE, 0.2, FIELD_SIZE),
		origin * CFrame.new(0, 0.1, 12),
		Color3.fromRGB(74, 104, 60),
		model
	)
	field.Material = Enum.Material.LeafyGrass
	field.CanCollide = false

	local sellZone = _newPart(
		"SellZone",
		SELL_ZONE_SIZE,
		origin * CFrame.new(0, 0.5, -PLOT_SIZE * 0.5 + 30),
		Color3.fromRGB(232, 196, 84),
		model
	)
	sellZone.Material = Enum.Material.Neon
	sellZone.CanCollide = false

	local sellLabel = Instance.new("BillboardGui")
	sellLabel.Name = "SellLabel"
	sellLabel.Size = UDim2.fromScale(8, 2)
	sellLabel.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	sellLabel.AlwaysOnTop = true
	sellLabel.Parent = sellZone
	local sellText = Instance.new("TextLabel")
	sellText.Size = UDim2.fromScale(1, 1)
	sellText.BackgroundTransparency = 1
	sellText.Text = "SELL"
	sellText.TextScaled = true
	sellText.Font = Enum.Font.GothamBold
	sellText.TextColor3 = Color3.fromRGB(255, 240, 180)
	sellText.Parent = sellLabel

	local boardCount = #Bamboo.Upgrades.Order
	for slot, upgradeId in Bamboo.Upgrades.Order do
		_buildBoard(model, origin, upgradeId, slot, boardCount)
	end

	local spawnPad = _newPart(
		"SpawnPad",
		Vector3.new(10, 1, 10),
		origin * CFrame.new(0, 0.5, -PLOT_SIZE * 0.5 + 46),
		Color3.fromRGB(120, 120, 130),
		model
	)
	spawnPad.Material = Enum.Material.Slate

	local rng = Random.new(index * 7919)

	model.Parent = _plotsFolder

	return {
		Id = plotId,
		Index = index,
		Model = model,
		Origin = origin,
		Field = field,
		SellZone = sellZone,
		-- Every plot is laid out for a fully upgraded field up front, so buying
		-- Density plants into existing slots instead of replanting the field.
		Slots = _buildSlots(field.CFrame * CFrame.new(0, -0.1, 0), Bamboo.Value.MaxPossibleStalks(), rng),
		Owner = nil,
	}
end

-- ── ownership ────────────────────────────────────────────────────────────────

local function _firstFreePlot(): Plot?
	for _, plot in _plots do
		if plot.Owner == nil then
			return plot
		end
	end
	return nil
end

local function _assign(player: Player)
	local plot = _firstFreePlot()
	if not plot then
		warn("[PlotService] no free plot for " .. player.Name)
		return
	end

	plot.Owner = player
	_plotsByPlayer[player] = plot
	plot.Model:SetAttribute("OwnerUserId", player.UserId)

	local Relay = Core:GetShared("Network")
	Relay.Player.PlotOwnerChanged.sendToAll({ plotId = plot.Id, ownerName = player.Name })

	local BambooService = Framework:GetService("BambooService")
	if BambooService then
		BambooService.PopulatePlot(plot)
	end
end

local function _release(player: Player)
	local plot = _plotsByPlayer[player]
	if not plot then
		return
	end

	local BambooService = Framework:GetService("BambooService")
	if BambooService then
		BambooService.ClearPlot(plot)
	end

	plot.Owner = nil
	plot.Model:SetAttribute("OwnerUserId", 0)
	_plotsByPlayer[player] = nil
end

-- Drops the character onto their own spawn pad so they start facing the field.
local function _placeCharacter(player: Player, character: Model)
	local plot = _plotsByPlayer[player]
	if not plot then
		return
	end
	local pad = plot.Model:FindFirstChild("SpawnPad") :: BasePart?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not pad or not root then
		return
	end
	root.CFrame = CFrame.lookAt(pad.Position + Vector3.new(0, 4, 0), plot.Field.Position)
end

-- ── lifecycle ────────────────────────────────────────────────────────────────

function PlotService:Start(fw: any)
	Framework = fw

	_plotsFolder = Instance.new("Folder")
	_plotsFolder.Name = "Plots"
	_plotsFolder.Parent = workspace

	for index = 1, PLOT_COUNT do
		table.insert(_plots, _buildPlotModel(index))
	end

	local function onPlayer(player: Player)
		_assign(player)
		if player.Character then
			_placeCharacter(player, player.Character)
		end
		player.CharacterAdded:Connect(function(character)
			_placeCharacter(player, character)
		end)
	end

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(_release)
end

--[[
	The plot a player currently owns.
	@param player Player Player to look up.
	@return Plot? Their plot, or nil before assignment / after they leave.
]]
function PlotService.GetPlot(player: Player): Plot?
	return _plotsByPlayer[player]
end

--[[
	Every plot in the server, owned or not.
	@return { Plot } All plots in index order.
]]
function PlotService.GetAllPlots(): { Plot }
	return _plots
end

return PlotService
