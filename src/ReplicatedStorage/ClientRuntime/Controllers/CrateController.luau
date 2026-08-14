--!strict
-- Crate opening: binds the hand-built OpenBoxes UI, and runs the case-clicker
-- reel that reveals what the server rolled.
--
-- The UI lives in StarterGui.Main (authored in Studio, not in this repo), so
-- everything here is defensive: if a frame is missing the controller quietly
-- does nothing rather than erroring on join. Names it expects:
--
--	FRAMES.OpenBoxes
--	  TitleBar.Title                     ShadowText — crate name
--	  CloseButton
--	  BoxSelection.ScrollingFrame        one row per crate
--	  OpenSettings.BoxSelectedText       ShadowText — selected crate + cost
--	  OpenSettings.AmountSelection       Open1 / Open2 / Open4
--	  OpenSettings.Buttons.OpenOnce
--	  PossibleRewards.ScrollingFrame     odds grid
--
-- The reel itself is built at runtime, since the kit has no reel frame.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Audio = require(ReplicatedStorage:WaitForChild("Audio"))
local Crates = Core:GetDomain("Crates")
local RNG = Core:Get("RNG")
local Sickles = Core:GetDomain("Sickles")
local FormatUtil = Core:GetUtil("FormatUtil")
local Relay = Core:GetShared("Network")
local Replica = Core:Get("Replica")
local UI = require(ReplicatedStorage:WaitForChild("UI"))
local Ripple = UI:GetModule("Ripple")
local ShadowText = UI:GetModule("ShadowText")

local CrateController = {}

local LOCAL_PLAYER = Players.LocalPlayer

-- Reel tuning. The reel is a strip of cards that slides left and decelerates
-- onto the winner; the long spin is what makes the stop feel earned.
local REEL_CARD_WIDTH = 150
local REEL_CARD_GAP = 10
local REEL_LENGTH = 48
-- Where in the strip the winning card sits. Far enough in that the spin reads
-- as long, short enough that the strip stays cheap to build.
local REEL_WINNER_INDEX = 42
local REEL_SPIN_SECONDS = 4.2
local REEL_SETTLE_SECONDS = 0.55

-- Auto-open skips the reel: a four-second reveal per crate turns a long session
-- into a wait. Results land as toasts instead.
local TOAST_SECONDS = 2.6

type Refs = {
	Frame: Frame,
	Dimmer: GuiObject?,
	HudButton: GuiButton?,
	Title: TextLabel?,
	SelectedText: TextLabel?,
	CrateList: ScrollingFrame?,
	RewardGrid: ScrollingFrame?,
	OpenButton: GuiButton?,
	AutoButton: GuiButton?,
	CloseButton: GuiButton?,
	LuckName: TextLabel?,
	LuckAmount: TextLabel?,
	RewardToasts: GuiObject?,
	AmountButtons: { [number]: GuiButton },
}

local _refs: Refs? = nil
local _selectedCrateId: string? = nil
local _selectedAmount = 1
local _isRolling = false
local _autoOpen = false
-- Forward-declared: the auto loop turns itself off from inside its own body.
local _setAutoOpen: (enabled: boolean) -> ()
local _reelGui: ScreenGui? = nil

-- ── UI lookup ────────────────────────────────────────────────────────────────

local function _find(parent: Instance?, path: { string }): Instance?
	local current = parent
	for _, name in path do
		if not current then
			return nil
		end
		current = current:FindFirstChild(name)
	end
	return current
end

local function _collectRefs(): Refs?
	local playerGui = LOCAL_PLAYER:FindFirstChildOfClass("PlayerGui")
	local frame = _find(playerGui, { "Main", "FRAMES", "OpenBoxes" }) :: Frame?
	if not frame then
		return nil
	end

	local amountButtons: { [number]: GuiButton } = {}
	for _, amount in Crates.BulkAmounts do
		local button = _find(frame, { "OpenSettings", "AmountSelection", "Open" .. amount })
		if button and button:IsA("GuiButton") then
			amountButtons[amount] = button
		end
	end

	local main = frame.Parent and frame.Parent.Parent

	return {
		Frame = frame,
		Dimmer = _find(main, { "FRAMES", "Dimmer" }) :: GuiObject?,
		HudButton = _find(main, { "HUD", "LeftSide", "Buttons", "OpenBoxes" }) :: GuiButton?,
		Title = _find(frame, { "TitleBar", "Title" }) :: TextLabel?,
		SelectedText = _find(frame, { "OpenSettings", "BoxSelectedText" }) :: TextLabel?,
		CrateList = _find(frame, { "BoxSelection", "ScrollingFrame" }) :: ScrollingFrame?,
		RewardGrid = _find(frame, { "PossibleRewards", "ScrollingFrame" }) :: ScrollingFrame?,
		OpenButton = _find(frame, { "OpenSettings", "Buttons", "OpenOnce" }) :: GuiButton?,
		AutoButton = _find(frame, { "OpenSettings", "Buttons", "AutoOpen" }) :: GuiButton?,
		LuckName = _find(frame, { "OpenSettings", "LuckBoost", "TextFrame", "LuckName" }) :: TextLabel?,
		LuckAmount = _find(frame, { "OpenSettings", "LuckBoost", "TextFrame", "Amount" }) :: TextLabel?,
		RewardToasts = _find(main, { "HUD", "RewardToasts" }) :: GuiObject?,
		CloseButton = frame:FindFirstChild("CloseButton") :: GuiButton?,
		AmountButtons = amountButtons,
	}
end

-- ── cards ────────────────────────────────────────────────────────────────────

-- One sickle card: tier-coloured plate with the name and an optional footer.
local function _buildSickleCard(sickleId: string, footer: string?): Frame
	local definition = Sickles.Definitions.Get(sickleId)
	local tier = Sickles.Tiers.Get(if definition then definition.tier else "Common")

	local card = Instance.new("Frame")
	card.Name = sickleId
	card.BackgroundColor3 = tier.color
	card.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = tier.color
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = card

	local inner = Instance.new("Frame")
	inner.Size = UDim2.new(1, -8, 1, -8)
	inner.Position = UDim2.fromOffset(4, 4)
	inner.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
	inner.BackgroundTransparency = 0.15
	inner.BorderSizePixel = 0
	inner.Parent = card

	local innerCorner = Instance.new("UICorner")
	innerCorner.CornerRadius = UDim.new(0, 6)
	innerCorner.Parent = inner

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, -8, 0.42, 0)
	name.Position = UDim2.fromScale(0, 0.12)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextScaled = true
	name.TextColor3 = tier.color
	name.Text = if definition then definition.name else sickleId
	name.Parent = inner

	local tierLabel = Instance.new("TextLabel")
	tierLabel.Size = UDim2.new(1, -8, 0.2, 0)
	tierLabel.Position = UDim2.fromScale(0, 0.56)
	tierLabel.BackgroundTransparency = 1
	tierLabel.Font = Enum.Font.GothamMedium
	tierLabel.TextScaled = true
	tierLabel.TextColor3 = Color3.fromRGB(210, 214, 222)
	tierLabel.Text = tier.name
	tierLabel.Parent = inner

	if footer then
		local footerLabel = Instance.new("TextLabel")
		footerLabel.Size = UDim2.new(1, -8, 0.2, 0)
		footerLabel.Position = UDim2.fromScale(0, 0.76)
		footerLabel.BackgroundTransparency = 1
		footerLabel.Font = Enum.Font.GothamMedium
		footerLabel.TextScaled = true
		footerLabel.TextColor3 = Color3.fromRGB(160, 166, 178)
		footerLabel.Text = footer
		footerLabel.Parent = inner
	end

	return card
end

-- ── panel population ─────────────────────────────────────────────────────────

-- Luck the server last told us about. The odds grid uses it so the percentages
-- shown are the ones a roll would actually use.
local function _currentLuck(): number
	local data = Replica.Player and Replica.Player.Data
	return (data and data.Luck) or 0
end

local function _refreshLuck()
	local refs = _refs
	if not refs then
		return
	end

	local luck = _currentLuck()

	if refs.LuckName then
		ShadowText.Set(refs.LuckName, "Luck Boost")
	end
	if refs.LuckAmount then
		ShadowText.Set(refs.LuckAmount, Crates.Luck.Format(luck))
		-- Green while boosted, muted at base luck, so "x1.00" doesn't read as a
		-- bonus the player already has.
		ShadowText.SetColor(
			refs.LuckAmount,
			if luck > 0 then Color3.fromRGB(68, 221, 79) else Color3.fromRGB(170, 176, 186)
		)
	end
end

local function _refreshRewardGrid()
	local refs = _refs
	local crateId = _selectedCrateId
	if not refs or not refs.RewardGrid or not crateId then
		return
	end

	for _, child in refs.RewardGrid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	for index, entry in Crates.Odds.Entries(crateId, _currentLuck()) do
		local card = _buildSickleCard(entry.sickleId, string.format("%.2f%%", entry.chance))
		card.LayoutOrder = index
		card.Parent = refs.RewardGrid
	end
end

local function _refreshSelection()
	local refs = _refs
	local crateId = _selectedCrateId
	if not refs or not crateId then
		return
	end

	local crate = Crates.Definitions.Get(crateId)
	if not crate then
		return
	end

	-- Both layers of every ShadowText, or the shadow keeps the old crate's name.
	if refs.Title then
		ShadowText.Set(refs.Title, crate.name)
	end
	if refs.SelectedText then
		local total = crate.cost * _selectedAmount
		ShadowText.Set(refs.SelectedText, string.format("%s  •  $%s", crate.name, FormatUtil.Number(total)))

		local money = Replica.Player and Replica.Player.Data and Replica.Player.Data.Money or 0
		ShadowText.SetColor(
			refs.SelectedText,
			if money >= total then Color3.fromRGB(150, 255, 160) else Color3.fromRGB(255, 140, 140)
		)
	end

	for amount, button in refs.AmountButtons do
		local title = button:FindFirstChild("Title")
		if title and title:IsA("TextLabel") then
			ShadowText.Set(title, "x" .. amount)
		end
		-- Selected amount is highlighted by opacity; the kit has no toggle state.
		button.BackgroundTransparency = if amount == _selectedAmount then 0 else 0.45
	end

	if refs.AutoButton then
		local title = refs.AutoButton:FindFirstChild("Title")
		if title and title:IsA("TextLabel") then
			ShadowText.Set(title, if _autoOpen then "STOP" else "AUTO")
			ShadowText.SetColor(
				title,
				if _autoOpen then Color3.fromRGB(255, 140, 140) else Color3.fromRGB(255, 255, 255)
			)
		end
		refs.AutoButton.BackgroundTransparency = if _autoOpen then 0 else 0.35
	end
end

local function _selectCrate(crateId: string)
	_selectedCrateId = crateId
	_refreshSelection()
	_refreshRewardGrid()
end

local function _populateCrateList()
	local refs = _refs
	if not refs or not refs.CrateList then
		return
	end

	for _, child in refs.CrateList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	for index, crate in Crates.Definitions.List() do
		local button = Instance.new("TextButton")
		button.Name = crate.id
		button.LayoutOrder = index
		button.Size = UDim2.new(1, 0, 0, 64)
		button.BackgroundColor3 = crate.color
		button.BackgroundTransparency = 0.15
		button.AutoButtonColor = false
		button.Font = Enum.Font.GothamBold
		button.TextScaled = true
		button.TextColor3 = Color3.fromRGB(255, 255, 255)
		button.Text = string.format("%s  —  $%s", crate.name, FormatUtil.Number(crate.cost))
		button.Parent = refs.CrateList

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = button

		Ripple.Bind(button)
		button.Activated:Connect(function()
			_selectCrate(crate.id)
		end)
	end
end

-- ── the reel ─────────────────────────────────────────────────────────────────

local function _ensureReelGui(): ScreenGui
	local existing = _reelGui
	if existing and existing.Parent then
		return existing
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "CrateReel"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.Enabled = false
	gui.Parent = LOCAL_PLAYER:WaitForChild("PlayerGui")

	_reelGui = gui
	return gui
end

-- Builds a strip of random cards with the real winner at REEL_WINNER_INDEX, and
-- slides it so that card lands under the centre marker.
local function _playReel(crateId: string, winnerSickleId: string): ()
	local gui = _ensureReelGui()
	for _, child in gui:GetChildren() do
		child:Destroy()
	end
	gui.Enabled = true

	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.BorderSizePixel = 0
	backdrop.Parent = gui

	local window = Instance.new("Frame")
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.new(0.8, 0, 0, 180)
	window.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	window.BorderSizePixel = 0
	window.ClipsDescendants = true
	window.Parent = backdrop

	local windowCorner = Instance.new("UICorner")
	windowCorner.CornerRadius = UDim.new(0, 12)
	windowCorner.Parent = window

	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.BackgroundTransparency = 1
	strip.AnchorPoint = Vector2.new(0, 0.5)
	strip.Position = UDim2.fromScale(0, 0.5)
	strip.Size = UDim2.fromOffset(REEL_LENGTH * (REEL_CARD_WIDTH + REEL_CARD_GAP), 150)
	strip.Parent = window

	-- Filler cards are rolled from the same odds table, so the strip looks like
	-- plausible results rather than a random shuffle of everything.
	-- One stream for the whole strip; the filler cards are only a preview, so
	-- they don't need to come from the server's roll.
	local previewRng = RNG.NewStream()
	for index = 1, REEL_LENGTH do
		local sickleId = if index == REEL_WINNER_INDEX
			then winnerSickleId
			else (Crates.Odds.Roll(crateId, previewRng, _currentLuck()) or winnerSickleId)

		local card = _buildSickleCard(sickleId)
		card.Size = UDim2.fromOffset(REEL_CARD_WIDTH, 150)
		card.Position = UDim2.fromOffset((index - 1) * (REEL_CARD_WIDTH + REEL_CARD_GAP), 0)
		card.Parent = strip
	end

	local marker = Instance.new("Frame")
	marker.Name = "Marker"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.fromScale(0.5, 0.5)
	marker.Size = UDim2.new(0, 4, 1, 0)
	marker.BackgroundColor3 = Color3.fromRGB(255, 226, 130)
	marker.BorderSizePixel = 0
	marker.ZIndex = 10
	marker.Parent = window

	-- Land the winning card's centre under the marker, with a small random
	-- offset so it never stops perfectly centred — near-misses feel earned.
	local pitch = REEL_CARD_WIDTH + REEL_CARD_GAP
	local jitter = previewRng:Number(-REEL_CARD_WIDTH * 0.28, REEL_CARD_WIDTH * 0.28)
	local target = -((REEL_WINNER_INDEX - 1) * pitch + REEL_CARD_WIDTH * 0.5) + jitter

	local spin = TweenService:Create(
		strip,
		TweenInfo.new(REEL_SPIN_SECONDS, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0, math.floor(target), 0.5, 0) }
	)
	spin:Play()
	spin.Completed:Wait()

	local definition = Sickles.Definitions.Get(winnerSickleId)
	local tier = Sickles.Tiers.Get(if definition then definition.tier else "Common")

	-- Reveal beat: the marker flares in the tier colour and the window pulses.
	marker.BackgroundColor3 = tier.color
	TweenService:Create(window, TweenInfo.new(REEL_SETTLE_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0.86, 0, 0, 200),
	}):Play()

	Audio:Play("BambooSell", "SFX", { PlaybackSpeed = 0.85 + tier.revealWeight * 0.06 })

	task.wait(1.4)
	gui.Enabled = false
end

-- ── toasts ───────────────────────────────────────────────────────────────────

-- Compact result line, used instead of the reel while auto-opening.
local function _pushToast(sickleId: string, isNew: boolean)
	local refs = _refs
	if not refs or not refs.RewardToasts then
		return
	end

	local definition = Sickles.Definitions.Get(sickleId)
	local tier = Sickles.Tiers.Get(if definition then definition.tier else "Common")

	local toast = Instance.new("Frame")
	toast.Name = "Toast"
	toast.Size = UDim2.new(1, 0, 0, 44)
	toast.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
	toast.BackgroundTransparency = 0.15
	toast.BorderSizePixel = 0
	toast.Parent = refs.RewardToasts

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = toast

	local stroke = Instance.new("UIStroke")
	stroke.Color = tier.color
	stroke.Thickness = 2
	stroke.Parent = toast

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -12, 1, 0)
	label.Position = UDim2.fromOffset(6, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = tier.color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text =
		string.format("%s%s", if definition then definition.name else sickleId, if isNew then "  •  NEW!" else "")
	label.Parent = toast

	TweenService:Create(toast, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.15,
	}):Play()

	task.delay(TOAST_SECONDS, function()
		if not toast.Parent then
			return
		end
		local fade = TweenService:Create(toast, TweenInfo.new(0.25), {
			BackgroundTransparency = 1,
		})
		TweenService:Create(label, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.25), { Transparency = 1 }):Play()
		fade:Play()
		fade.Completed:Once(function()
			toast:Destroy()
		end)
	end)
end

-- ── open flow ────────────────────────────────────────────────────────────────

local function _canAfford(): boolean
	local crateId = _selectedCrateId
	local crate = crateId and Crates.Definitions.Get(crateId)
	if not crate then
		return false
	end
	local money = Replica.Player and Replica.Player.Data and Replica.Player.Data.Money or 0
	return money >= crate.cost * _selectedAmount
end

local function _requestOpen()
	local crateId = _selectedCrateId
	if _isRolling or not crateId then
		return
	end
	_isRolling = true
	Relay.Crates.OpenCrate.send({ crateId = crateId, amount = _selectedAmount })
end

-- Auto-open stops itself the moment it can't continue, so it never spams the
-- server with requests the server is only going to reject.
function _setAutoOpen(enabled: boolean)
	_autoOpen = enabled
	_refreshSelection()

	if not enabled then
		return
	end

	task.spawn(function()
		while _autoOpen do
			local refs = _refs
			if not refs or not refs.Frame.Visible or not _canAfford() then
				_setAutoOpen(false)
				return
			end
			if not _isRolling then
				_requestOpen()
			end
			task.wait(Crates.AutoOpenIntervalSeconds)
		end
	end)
end

local function _onCrateResult(payload: any)
	local results = payload.results :: { any }

	-- Auto-open skips the reel entirely and reports as toasts; a four-second
	-- reveal per crate would make a long session a wait rather than a reward.
	if _autoOpen then
		for _, result in results do
			_pushToast(result.sickleId, result.isNew)
		end
		_isRolling = false
		_refreshSelection()
		return
	end

	-- A bulk open reels on its best pull; showing four reels back to back would
	-- turn the payoff into a chore. The rest still land as toasts.
	local best = results[1]
	for _, result in results do
		if Sickles.Tiers.Rank(result.tier) > Sickles.Tiers.Rank(best.tier) then
			best = result
		end
	end

	task.spawn(function()
		_playReel(payload.crateId, best.sickleId)
		for _, result in results do
			if result ~= best then
				_pushToast(result.sickleId, result.isNew)
			end
		end
		_isRolling = false
		_refreshSelection()
	end)
end

local function _onCrateRejected(_payload: any)
	_isRolling = false
	-- Whatever the server refused, auto-open can't fix by trying harder.
	if _autoOpen then
		_setAutoOpen(false)
	end
	_refreshSelection()
end

-- ── lifecycle ────────────────────────────────────────────────────────────────

-- Panel and dimmer are shown together; the dimmer is what makes the panel read
-- as modal rather than as another HUD element.
local function _setPanelVisible(visible: boolean)
	local refs = _refs
	if not refs then
		return
	end
	refs.Frame.Visible = visible
	if refs.Dimmer then
		refs.Dimmer.Visible = visible
	end
	-- Closing the panel is a clear "stop", so the loop doesn't run unseen.
	if not visible and _autoOpen then
		_setAutoOpen(false)
	end
end

local function _bind()
	local refs = _collectRefs()
	if not refs then
		return
	end
	_refs = refs

	_setPanelVisible(false)

	if refs.HudButton then
		Ripple.Bind(refs.HudButton)
		refs.HudButton.Activated:Connect(function()
			_setPanelVisible(not refs.Frame.Visible)
		end)
	end

	if refs.CloseButton then
		Ripple.Bind(refs.CloseButton)
		refs.CloseButton.Activated:Connect(function()
			_setPanelVisible(false)
		end)
	end

	_refreshLuck()

	if refs.OpenButton then
		Ripple.Bind(refs.OpenButton, { Color = Color3.fromRGB(200, 255, 200) })
		refs.OpenButton.Activated:Connect(function()
			-- A manual open always cancels auto, so the two can never fight over
			-- whether the reel should play.
			if _autoOpen then
				_setAutoOpen(false)
			end
			_requestOpen()
		end)
	end

	if refs.AutoButton then
		Ripple.Bind(refs.AutoButton, { Color = Color3.fromRGB(255, 226, 190) })
		refs.AutoButton.Activated:Connect(function()
			_setAutoOpen(not _autoOpen)
		end)
	end

	for amount, button in refs.AmountButtons do
		Ripple.Bind(button)
		button.Activated:Connect(function()
			_selectedAmount = amount
			_refreshSelection()
		end)
	end

	_populateCrateList()

	local first = Crates.Definitions.List()[1]
	if first then
		_selectCrate(first.id)
	end
end

function CrateController:Start(_fw: any)
	task.spawn(_bind)

	Relay.Crates.CrateResult.listen(_onCrateResult)
	Relay.Crates.CrateRejected.listen(_onCrateRejected)

	Replica:WaitForData("Player"):andThen(function(replica: any)
		replica:ListenToChange({ "Money" }, _refreshSelection)
		replica:ListenToChange({ "Luck" }, function()
			_refreshLuck()
			-- Odds shift with luck, so the grid is rebuilt alongside the chip.
			_refreshRewardGrid()
		end)
	end)
end

--[[
	Shows or hides the crate panel. Call this from whichever HUD button or world
	interaction should open it.
	@param visible boolean True to show the panel.
]]
function CrateController.SetVisible(visible: boolean)
	_setPanelVisible(visible)
end

--[[
	The crate currently selected in the panel, for other UI to read.
	@return string? Crate id, or nil before the panel has bound.
]]
function CrateController.GetSelectedCrate(): string?
	return _selectedCrateId
end

return CrateController
