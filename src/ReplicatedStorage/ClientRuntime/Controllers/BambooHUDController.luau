--!strict
-- Persistent HUD: money, bag, combo, and the "BAG FULL" arrow pointing at the
-- sell zone.
--
-- Money and bag are the authored HUDStatsLabel components in
-- StarterGui.Main.HUD.LeftDownSide (Cash and Backpack). They live in the place
-- file, not this repo, so they are bound by name at runtime and every write
-- goes through ShadowText — both layers, or the shadow keeps the old number.
--
-- Combo and the BAG FULL arrow have no authored counterpart, so they are still
-- built here, into their own ScreenGui that sits under the kit's.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Bamboo = Core:GetDomain("Bamboo")
local FormatUtil = Core:GetUtil("FormatUtil")
local Relay = Core:GetShared("Network")
local Replica = Core:Get("Replica")
local UI = require(ReplicatedStorage:WaitForChild("UI"))
local ShadowText = UI:GetModule("ShadowText")
local AntiCheat = require(script.Parent:WaitForChild("AntiCheatController"))

local BambooHUDController = {}

local LOCAL_PLAYER = Players.LocalPlayer
local ARROW_BIND = "BambooSellArrow"
local DROPPED_HINT_SECONDS = 1.6

-- Combo counter. The number is the whole design: a big count, a small label,
-- and a thin bar showing how much of the grace period is left.
local COMBO_BASE_SIZE = 46
local COMBO_LABEL_SIZE = 16
local MILESTONE_SIZE = 22

-- Authored HUD components, when the kit is present.
local _cashText: TextLabel? = nil
local _bagText: TextLabel? = nil

-- Built here, always.
local _screen: ScreenGui
local _comboRoot: Frame
local _comboCount: TextLabel
local _comboWord: TextLabel
local _comboBar: Frame
local _milestoneLabel: TextLabel
local _arrow: TextLabel

-- Authoritative combo, straight from the server. The client never derives it.
local _combo = 0
local _comboWindow = 0
local _comboEndsAt = 0
local _lastBag = 0
local _lastMoney = 0
-- While set, the arrow shows the drop hint instead of the direction readout.
local _droppedHintUntil = 0

-- ── authored HUD lookup ──────────────────────────────────────────────────────

-- Each HUDStatsLabel wraps its value in a `Double` ShadowText. Falls back to
-- any TextLabel child so a renamed component still binds.
local function _statLabel(container: Instance?): TextLabel?
	if not container then
		return nil
	end
	local double = container:FindFirstChild("Double")
	if double and double:IsA("TextLabel") then
		return double
	end
	return container:FindFirstChildWhichIsA("TextLabel")
end

local function _bindAuthoredHud()
	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	local main = playerGui:WaitForChild("Main", 10)
	if not main then
		return
	end

	local stats = main:FindFirstChild("HUD")
	stats = stats and stats:FindFirstChild("LeftDownSide")
	if not stats then
		return
	end

	_cashText = _statLabel(stats:FindFirstChild("Cash"))
	_bagText = _statLabel(stats:FindFirstChild("Backpack"))
end

-- ── own HUD construction ─────────────────────────────────────────────────────

local function _newLabel(name: string, parent: Instance, position: UDim2, size: UDim2, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = position
	label.Size = size
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = textSize
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.4
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Text = ""
	label.Parent = parent
	return label
end

local function _build()
	_screen = Instance.new("ScreenGui")
	_screen.Name = "BambooHUD"
	_screen.ResetOnSpawn = false
	_screen.IgnoreGuiInset = true
	_screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Below the authored kit, which has no DisplayOrder set.
	_screen.DisplayOrder = -1
	_screen.Parent = LOCAL_PLAYER:WaitForChild("PlayerGui")
	-- Built at runtime, so the anti-cheat scanner has to be told it is ours.
	AntiCheat.Approve(_screen)

	-- Combo cluster: count, word, window bar, milestone callout. Held in one
	-- frame so the whole thing can fade as a unit.
	_comboRoot = Instance.new("Frame")
	_comboRoot.Name = "Combo"
	_comboRoot.AnchorPoint = Vector2.new(0.5, 0)
	_comboRoot.Position = UDim2.new(0.5, 0, 0, 84)
	_comboRoot.Size = UDim2.fromOffset(280, 104)
	_comboRoot.BackgroundTransparency = 1
	_comboRoot.Visible = false
	_comboRoot.Parent = _screen

	_comboCount = _newLabel("Count", _comboRoot, UDim2.fromOffset(0, 0), UDim2.fromOffset(280, 56), COMBO_BASE_SIZE)
	_comboWord = _newLabel("Word", _comboRoot, UDim2.fromOffset(0, 54), UDim2.fromOffset(280, 20), COMBO_LABEL_SIZE)
	_comboWord.Text = "COMBO"
	_comboWord.TextColor3 = Color3.fromRGB(210, 214, 222)

	local barTrack = Instance.new("Frame")
	barTrack.Name = "WindowTrack"
	barTrack.AnchorPoint = Vector2.new(0.5, 0)
	barTrack.Position = UDim2.new(0.5, 0, 0, 78)
	barTrack.Size = UDim2.fromOffset(120, 4)
	barTrack.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	barTrack.BackgroundTransparency = 0.55
	barTrack.BorderSizePixel = 0
	barTrack.Parent = _comboRoot

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = barTrack

	_comboBar = Instance.new("Frame")
	_comboBar.Name = "Window"
	_comboBar.Size = UDim2.fromScale(1, 1)
	_comboBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	_comboBar.BorderSizePixel = 0
	_comboBar.Parent = barTrack

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = _comboBar

	_milestoneLabel =
		_newLabel("Milestone", _comboRoot, UDim2.fromOffset(0, 86), UDim2.fromOffset(280, 22), MILESTONE_SIZE)
	_milestoneLabel.TextTransparency = 1

	_arrow = _newLabel("SellArrow", _screen, UDim2.new(0.5, -160, 0.5, -40), UDim2.fromOffset(320, 60), 28)
	_arrow.TextColor3 = Color3.fromRGB(255, 120, 120)
	_arrow.Text = "BAG FULL!"
	_arrow.Visible = false
end

-- ── refresh ──────────────────────────────────────────────────────────────────

-- Scale punch on a label, so a number changing is felt and not just read.
local function _punch(label: TextLabel, baseSize: number, overshoot: number)
	label.TextSize = baseSize + overshoot
	TweenService:Create(label, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextSize = baseSize,
	}):Play()
end

-- The authored labels are TextScaled, so they can't be punched by TextSize.
-- A brief colour flash is the equivalent beat that survives scaling.
local function _flash(label: TextLabel, color: Color3)
	ShadowText.SetColor(label, color)
	task.delay(0.18, function()
		if label.Parent then
			ShadowText.SetColor(label, Color3.fromRGB(255, 255, 255))
		end
	end)
end

local function _refreshFromData(data: any)
	if not data then
		return
	end

	local money = data.Money or 0
	if _cashText then
		ShadowText.Set(_cashText, "$" .. FormatUtil.Number(money))
		if money > _lastMoney then
			_flash(_cashText, Color3.fromRGB(150, 255, 160))
		end
	end
	_lastMoney = money

	local bag = data.Bag or 0
	local capacity = Bamboo.Value.BagCapacity(data.StorageLevel or 0)
	local full = bag >= capacity

	if _bagText then
		ShadowText.Set(_bagText, string.format("%d/%d", bag, capacity))
		if full then
			ShadowText.SetColor(_bagText, Color3.fromRGB(255, 120, 120))
		elseif bag > _lastBag then
			_flash(_bagText, Color3.fromRGB(150, 255, 160))
		end
	end
	_lastBag = bag

	_arrow.Visible = full
end

-- Milestone callout: a short shout above the counter that never blocks play.
local function _showMilestone(milestone: number)
	_milestoneLabel.Text = string.format("%d COMBO!", milestone)
	_milestoneLabel.TextColor3 = Bamboo.Combo.Color(milestone)
	_milestoneLabel.TextTransparency = 0
	_punch(_milestoneLabel, MILESTONE_SIZE, 16)

	TweenService:Create(_milestoneLabel, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
	}):Play()
end

-- Server told us the combo moved. The client only renders it — it never counts.
local function _onComboState(payload: any)
	local combo = payload.combo :: number
	local milestone = payload.milestone :: number
	local grew = combo > _combo

	_combo = combo
	_comboWindow = payload.windowSeconds
	_comboEndsAt = if combo > 0 then os.clock() + payload.windowSeconds else 0

	if combo <= 0 then
		TweenService:Create(_comboCount, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
		TweenService:Create(_comboWord, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
		task.delay(0.25, function()
			if _combo <= 0 then
				_comboRoot.Visible = false
			end
		end)
		return
	end

	local color = Bamboo.Combo.Color(combo)
	_comboRoot.Visible = true
	_comboCount.Text = tostring(combo)
	_comboCount.TextColor3 = color
	_comboCount.TextTransparency = 0
	_comboWord.TextTransparency = 0
	_comboBar.BackgroundColor3 = color

	if grew then
		-- Punch harder as the streak heats up, so a 60-combo swing lands harder
		-- than the first one did.
		_punch(_comboCount, COMBO_BASE_SIZE, 10 + Bamboo.Combo.Heat(combo) * 16)
	end

	if milestone > 0 then
		_showMilestone(milestone)
	end
end

-- Drains the window bar. Driven locally from the last packet's window length
-- rather than the server sending a countdown every frame.
local function _updateComboWindow()
	if _combo <= 0 or _comboWindow <= 0 then
		return
	end
	local remaining = math.max(_comboEndsAt - os.clock(), 0)
	_comboBar.Size = UDim2.fromScale(remaining / _comboWindow, 1)
end

-- Bag was too full to take the cut, so the bamboo hit the ground instead. The
-- arrow already says BAG FULL; this says what it just cost.
local function _flashDropped(amount: number)
	_arrow.Text = string.format("BAG FULL  —  %d dropped", amount)
	_arrow.Visible = true
	_punch(_arrow, 28, 10)
	_droppedHintUntil = os.clock() + DROPPED_HINT_SECONDS
end

-- Points the "BAG FULL" text toward the player's own sell zone.
local function _updateArrow()
	if not _arrow.Visible or os.clock() < _droppedHintUntil then
		return
	end

	local character = LOCAL_PLAYER.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local camera = workspace.CurrentCamera
	if not root or not camera then
		return
	end

	local plots = workspace:FindFirstChild("Plots")
	if not plots then
		return
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("OwnerUserId") ~= LOCAL_PLAYER.UserId then
			continue
		end
		local sellZone = plot:FindFirstChild("SellZone") :: BasePart?
		if not sellZone then
			return
		end

		local toZone = sellZone.Position - root.Position
		local flat = Vector3.new(toZone.X, 0, toZone.Z)
		local look = camera.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 1e-3 or flatLook.Magnitude < 1e-3 then
			return
		end

		-- Signed angle between where the camera looks and where the zone is.
		local right = Vector3.new(-flatLook.Z, 0, flatLook.X).Unit
		local angle = math.atan2(flat.Unit:Dot(right), flat.Unit:Dot(flatLook.Unit))
		local arrows = { "↑", "↗", "→", "↘", "↓", "↙", "←", "↖" }
		local index = math.floor(((angle + math.pi * 2) % (math.pi * 2)) / (math.pi / 4) + 0.5) % 8 + 1

		_arrow.Text = string.format("BAG FULL!  %s  %dm", arrows[index], math.floor(flat.Magnitude))
		return
	end
end

local function _onFrame()
	_updateComboWindow()
	_updateArrow()
end

-- ── lifecycle ────────────────────────────────────────────────────────────────

function BambooHUDController:Start(_fw: any)
	_build()

	task.spawn(function()
		_bindAuthoredHud()
		local replica = Replica.Player
		if replica then
			_refreshFromData(replica.Data)
		end
	end)

	Replica:WaitForData("Player"):andThen(function(replica: any)
		_refreshFromData(replica.Data)
		for _, key in { "Money", "Bag", "StorageLevel" } do
			replica:ListenToChange({ key }, function()
				_refreshFromData(replica.Data)
			end)
		end
	end)

	Relay.Bamboo.ComboState.listen(_onComboState)

	Relay.Bamboo.SwingResult.listen(function(payload: any)
		if payload.dropped > 0 then
			_flashDropped(payload.dropped)
		end
	end)

	RunService:BindToRenderStep(ARROW_BIND, Enum.RenderPriority.Last.Value, _onFrame)
end

--[[
	The money readout, so payout orbs know where to land.
	@return TextLabel? The authored Cash label, or nil before the HUD has bound.
]]
function BambooHUDController.GetMoneyLabel(): TextLabel?
	return _cashText
end

return BambooHUDController
