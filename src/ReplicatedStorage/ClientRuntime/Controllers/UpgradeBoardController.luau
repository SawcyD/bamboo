--!strict
-- Upgrade boards. Each board shows its own level/effect/cost on a billboard and
-- only becomes buyable when the player is standing next to it — Phase 1 has no
-- upgrade menu.
--
-- The cost is a real button so touch and mouse players can tap it directly; [E]
-- does the same thing for keyboard and gamepad. Both paths ripple.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Bamboo = Core:GetDomain("Bamboo")
local FormatUtil = Core:GetUtil("FormatUtil")
local Relay = Core:GetShared("Network")
local Replica = Core:Get("Replica")
local UI = require(ReplicatedStorage:WaitForChild("UI"))
local Ripple = UI:GetModule("Ripple")

local UpgradeBoardController = {}

local LOCAL_PLAYER = Players.LocalPlayer
local BOARD_TAG = "BambooUpgradeBoard"
local BUY_ACTION = "BambooBuyUpgrade"
local PROXIMITY_STUDS = 14
local REFRESH_BIND = "BambooBoardRefresh"

type BoardView = {
	Part: BasePart,
	UpgradeId: string,
	TitleLabel: TextLabel,
	StatLabel: TextLabel,
	CostButton: TextButton,
	PromptLabel: TextLabel,
}

local _boards: { BoardView } = {}
local _nearest: BoardView? = nil
-- Forward-declared: the board UI binds to it before it is defined below.
local _requestUpgrade: (view: BoardView) -> ()

-- ── board UI ─────────────────────────────────────────────────────────────────

local function _newText(parent: Instance, order: number, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, size)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.4
	label.Text = ""
	label.Parent = parent
	return label
end

local function _newButton(parent: Instance, order: number, size: number, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.LayoutOrder = order
	button.Size = UDim2.new(1, 0, 0, size)
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.TextColor3 = color
	button.TextStrokeTransparency = 0.4
	button.Text = ""
	button.Parent = parent
	return button
end

local function _attachBoard(part: BasePart): BoardView?
	local upgradeId = part:GetAttribute("UpgradeId") :: string?
	local def = upgradeId and Bamboo.Upgrades.Get(upgradeId)
	if not def then
		return nil
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BoardUI"
	billboard.Size = UDim2.fromScale(9, 6)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	billboard.MaxDistance = 60
	billboard.Parent = part

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = billboard

	local view: BoardView = {
		Part = part,
		UpgradeId = def.id,
		TitleLabel = _newText(billboard, 1, 34, Color3.fromRGB(255, 255, 255)),
		StatLabel = _newText(billboard, 2, 26, Color3.fromRGB(196, 232, 190)),
		CostButton = _newButton(billboard, 3, 30, Color3.fromRGB(255, 226, 130)),
		PromptLabel = _newText(billboard, 4, 22, Color3.fromRGB(200, 200, 210)),
	}
	view.TitleLabel.Text = def.name

	Ripple.Bind(view.CostButton, { Color = Color3.fromRGB(255, 240, 190) })
	view.CostButton.Activated:Connect(function()
		_requestUpgrade(view)
	end)

	return view
end

-- What each upgrade's stat is measured in, for the board's level line.
local STAT_FORMAT: { [string]: string } = {
	SwingSpeed = "%.2fs swing",
	MultiHit = "%d targets",
	Yield = "%d per stalk",
	Storage = "%d bag",
	GrowthSpeed = "%.0fs regrow",
	Density = "%d in field",
}

-- Formats the stat line for one upgrade at its current level.
local function _statText(upgradeId: string, level: number): string
	local value = Bamboo.Value.StatAtLevel(upgradeId, level)
	local format = STAT_FORMAT[upgradeId] or "%d"
	return string.format("Level %d  •  " .. format, level, value)
end

local function _refreshBoards()
	local replica = Replica.Player
	local data = replica and replica.Data
	if not data then
		return
	end

	local money = data.Money or 0

	for _, view in _boards do
		local def = Bamboo.Upgrades.Get(view.UpgradeId)
		local level = data[def.dataKey] or 0

		view.StatLabel.Text = _statText(view.UpgradeId, level)

		if level >= def.maxLevel then
			view.CostButton.Text = "MAXED"
			view.CostButton.TextColor3 = Color3.fromRGB(180, 200, 255)
			view.PromptLabel.Text = ""
			continue
		end

		local cost = Bamboo.Value.UpgradeCost(view.UpgradeId, level)
		view.CostButton.Text = "$" .. FormatUtil.Number(cost)
		view.CostButton.TextColor3 = if money >= cost
			then Color3.fromRGB(150, 255, 160)
			else Color3.fromRGB(255, 140, 140)
		view.CostButton.Active = view == _nearest
		view.PromptLabel.Text = if view == _nearest
			then "[E] / Tap to Upgrade  •  " .. def.effectText
			else def.effectText
	end
end

-- ── proximity ────────────────────────────────────────────────────────────────

local function _updateNearest()
	local character = LOCAL_PLAYER.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local previous = _nearest
	_nearest = nil

	if root then
		local bestDistance = PROXIMITY_STUDS
		for _, view in _boards do
			local distance = (view.Part.Position - root.Position).Magnitude
			if distance < bestDistance then
				bestDistance = distance
				_nearest = view
			end
		end
	end

	if _nearest ~= previous then
		_refreshBoards()
	end
end

-- Single path for both input routes, so the prompt and the button can never
-- disagree about which board is buyable.
function _requestUpgrade(view: BoardView)
	if view ~= _nearest then
		return
	end
	Relay.Bamboo.BuyUpgrade.send({ upgradeId = view.UpgradeId })
end

local function _onBuyAction(_actionName: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local view = _nearest
	if not view then
		return Enum.ContextActionResult.Pass
	end
	Ripple.Play(view.CostButton, nil, { Color = Color3.fromRGB(255, 240, 190) })
	_requestUpgrade(view)
	return Enum.ContextActionResult.Sink
end

-- ── lifecycle ────────────────────────────────────────────────────────────────

function UpgradeBoardController:Start(_fw: any)
	local function bind(instance: Instance)
		if not instance:IsA("BasePart") then
			return
		end
		local view = _attachBoard(instance)
		if view then
			table.insert(_boards, view)
			_refreshBoards()
		end
	end

	for _, instance in CollectionService:GetTagged(BOARD_TAG) do
		bind(instance)
	end
	CollectionService:GetInstanceAddedSignal(BOARD_TAG):Connect(bind)
	CollectionService:GetInstanceRemovedSignal(BOARD_TAG):Connect(function(instance: Instance)
		for index, view in _boards do
			if view.Part == instance then
				table.remove(_boards, index)
				break
			end
		end
	end)

	Replica:WaitForData("Player"):andThen(function(replica: any)
		_refreshBoards()
		for _, upgradeId in Bamboo.Upgrades.Order do
			replica:ListenToChange({ Bamboo.Upgrades.Get(upgradeId).dataKey }, _refreshBoards)
		end
		replica:ListenToChange({ "Money" }, _refreshBoards)
	end)

	Relay.Bamboo.UpgradeResult.listen(_refreshBoards)

	ContextActionService:BindAction(BUY_ACTION, _onBuyAction, true, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle(BUY_ACTION, "Upgrade")

	local accumulator = 0
	RunService:BindToRenderStep(REFRESH_BIND, Enum.RenderPriority.Last.Value, function(dt: number)
		accumulator += dt
		if accumulator < 0.2 then
			return
		end
		accumulator = 0
		_updateNearest()
	end)
end

return UpgradeBoardController
