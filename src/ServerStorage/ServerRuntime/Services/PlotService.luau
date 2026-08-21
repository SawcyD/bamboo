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
local CASH_COLLECTOR_SIZE = Vector3.new(18, 1, 18)
local STOCKPILE_SIZE = Vector3.new(14, 4, 14)
local PROCESSOR_SIZE = Vector3.new(12, 8, 10)
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
	-- Where PendingEarnings become spendable Money. Named CashCollector rather
	-- than SellZone: nothing is sold here, earnings already banked by the
	-- processor are simply claimed.
	CashCollector: BasePart,
	-- BambooStock -> CarriedBamboo interaction point.
	Stockpile: BasePart,
	-- Deposit/collision zone for the Raw Bamboo -> Straw processor. Looked up by
	-- field the same way CashCollector is, rather than a CollectionService tag,
	-- because there is exactly one per plot.
	Processor: BasePart,
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

-- A ProximityPrompt with the shared look every interaction point on the plot
-- uses. The client controller owning `name` listens for .Triggered and sends
-- its own intent-only remote; the server never trusts the prompt itself as
-- authority, only as the player's "I'm asking" signal — StockpileService and
-- ProcessingService still validate ownership and distance independently.
local function _newPrompt(parent: Instance, name: string, actionText: string, objectText: string): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent
	return prompt
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

-- Raw Bamboo -> Straw processor. Built beside the sell zone (same Z, offset in
-- X) rather than a CollectionService-tagged component: there is exactly one per
-- plot, so a direct field on the Plot record is simpler than a tag lookup, the
-- same choice PlotService already made for Field and SellZone.
local function _buildProcessor(plotModel: Model, origin: CFrame): BasePart
	-- X=30 clears the sell zone's own padded footprint (its half-width plus
	-- FarmEconomyService's padding reaches to X≈12) with room to spare, so
	-- standing at one pad can never also register inside the other.
	local body = _newPart(
		"Processor",
		PROCESSOR_SIZE,
		origin * CFrame.new(30, PROCESSOR_SIZE.Y * 0.5, -PLOT_SIZE * 0.5 + 30),
		Color3.fromRGB(92, 100, 112),
		plotModel
	)
	body.Material = Enum.Material.Metal
	body.CanCollide = true

	-- Idle/active spin driven client-side (ProcessorController); the server only
	-- places it. A visibly turning part is the cheapest possible "machine is
	-- alive" read, and costs the server nothing since rotation is presentation.
	local roller = Instance.new("Part")
	roller.Name = "Roller"
	roller.Shape = Enum.PartType.Cylinder
	roller.Size = Vector3.new(PROCESSOR_SIZE.X * 0.7, 1.6, 1.6)
	roller.Color = Color3.fromRGB(60, 66, 74)
	roller.Material = Enum.Material.Metal
	roller.Anchored = true
	roller.CanCollide = false
	roller.CanQuery = false
	roller.CanTouch = false
	roller.CFrame = body.CFrame * CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(90))
	roller.Parent = body

	-- Off by default; ProcessorController brightens it while the input buffer is
	-- non-empty, so "the machine has fuel" is readable at a glance across the plot.
	local light = Instance.new("PointLight")
	light.Name = "ProcessorLight"
	light.Color = Color3.fromRGB(140, 220, 255)
	light.Brightness = 0
	light.Range = 14
	light.Shadows = false
	light.Parent = body

	-- Attachments the client flies visuals to/from. Positioned in the body's own
	-- local space, so they move correctly even if PROCESSOR_SIZE is retuned.
	local inputPoint = Instance.new("Attachment")
	inputPoint.Name = "ProcessorInputPoint"
	inputPoint.Position = Vector3.new(0, PROCESSOR_SIZE.Y * 0.5 + 0.5, PROCESSOR_SIZE.Z * 0.15)
	inputPoint.Parent = body

	local outputPoint = Instance.new("Attachment")
	outputPoint.Name = "ProcessorOutputPoint"
	outputPoint.Position = Vector3.new(0, -PROCESSOR_SIZE.Y * 0.15, PROCESSOR_SIZE.Z * 0.5)
	outputPoint.Parent = body

	_newPrompt(body, "DepositPrompt", "Deposit", "Processor")

	local label = Instance.new("BillboardGui")
	label.Name = "ProcessorLabel"
	label.Size = UDim2.fromScale(8, 3)
	label.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	label.AlwaysOnTop = true
	label.Parent = body

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = label

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.LayoutOrder = 1
	title.Size = UDim2.new(1, 0, 0, 30)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextStrokeTransparency = 0.4
	title.Text = "PROCESSOR"
	title.Parent = label

	-- Live readout. ProcessorController writes this straight from the owner's
	-- replicated ProcessorInput/CarriedBamboo — no extra networking, since those
	-- fields already replicate through DataService like BambooStock and Money.
	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.LayoutOrder = 2
	status.Size = UDim2.new(1, 0, 0, 22)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.GothamBold
	status.TextScaled = true
	status.TextColor3 = Color3.fromRGB(196, 232, 255)
	status.TextStrokeTransparency = 0.5
	status.Text = ""
	status.Parent = label

	return body
end

-- Physical stockpile interaction point: BambooStock -> CarriedBamboo. Built
-- beside the field (same X row as the processor/cash collector, mirrored to
-- the other side) so the walk from field to stockpile to processor reads as a
-- straight line across the plot.
local function _buildStockpile(plotModel: Model, origin: CFrame): BasePart
	local body = _newPart(
		"Stockpile",
		STOCKPILE_SIZE,
		origin * CFrame.new(-30, STOCKPILE_SIZE.Y * 0.5, -PLOT_SIZE * 0.5 + 30),
		Color3.fromRGB(150, 120, 70),
		plotModel
	)
	body.Material = Enum.Material.WoodPlanks
	body.CanCollide = true

	_newPrompt(body, "TakePrompt", "Take Bamboo", "Stockpile")

	local label = Instance.new("BillboardGui")
	label.Name = "StockpileLabel"
	label.Size = UDim2.fromScale(8, 3)
	label.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	label.AlwaysOnTop = true
	label.Parent = body

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = label

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.LayoutOrder = 1
	title.Size = UDim2.new(1, 0, 0, 30)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextStrokeTransparency = 0.4
	title.Text = "STOCKPILE"
	title.Parent = label

	-- Live readout. StockpileController writes this straight from the owner's
	-- replicated BambooStock — no extra networking needed for display.
	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.LayoutOrder = 2
	status.Size = UDim2.new(1, 0, 0, 22)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.GothamBold
	status.TextScaled = true
	status.TextColor3 = Color3.fromRGB(230, 214, 190)
	status.TextStrokeTransparency = 0.5
	status.Text = ""
	status.Parent = label

	return body
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

	local cashCollector = _newPart(
		"CashCollector",
		CASH_COLLECTOR_SIZE,
		origin * CFrame.new(0, 0.5, -PLOT_SIZE * 0.5 + 30),
		Color3.fromRGB(232, 196, 84),
		model
	)
	cashCollector.Material = Enum.Material.Neon
	cashCollector.CanCollide = false

	local collectorLabel = Instance.new("BillboardGui")
	collectorLabel.Name = "CashCollectorLabel"
	collectorLabel.Size = UDim2.fromScale(8, 2)
	collectorLabel.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	collectorLabel.AlwaysOnTop = true
	collectorLabel.Parent = cashCollector
	local collectorText = Instance.new("TextLabel")
	collectorText.Size = UDim2.fromScale(1, 1)
	collectorText.BackgroundTransparency = 1
	collectorText.Text = "COLLECT"
	collectorText.TextScaled = true
	collectorText.Font = Enum.Font.GothamBold
	collectorText.TextColor3 = Color3.fromRGB(255, 240, 180)
	collectorText.Parent = collectorLabel

	local boardCount = #Bamboo.Upgrades.Order
	for slot, upgradeId in Bamboo.Upgrades.Order do
		_buildBoard(model, origin, upgradeId, slot, boardCount)
	end

	local stockpile = _buildStockpile(model, origin)
	local processor = _buildProcessor(model, origin)

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
		CashCollector = cashCollector,
		Stockpile = stockpile,
		Processor = processor,
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
