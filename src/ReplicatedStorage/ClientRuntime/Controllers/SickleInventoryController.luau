--!strict
-- Sickle inventory: every sickle the player owns, and a way back to any of them.
--
-- This closes a real usability hole. Crates auto-equip anything better, so a
-- player who liked their Hunter's Scythe for Magnet had no route back to it
-- once a higher tier dropped. Ownership was never lost — there was just no UI.
--
-- The panel only ever *requests* an equip. SickleService re-checks ownership
-- server-side, so a client asking for something it never won is ignored.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Sickles = Core:GetDomain("Sickles")
local Relay = Core:GetShared("Network")
local Replica = Core:Get("Replica")
local UI = require(ReplicatedStorage:WaitForChild("UI"))
local Panel = UI:GetModule("Panel")
local Ripple = UI:GetModule("Ripple")
local ShadowText = UI:GetModule("ShadowText")

local SickleInventoryController = {}

local LOCAL_PLAYER = Players.LocalPlayer
local CARD_HEIGHT = 108
local EQUIP_BUTTON_WIDTH = 104

local _panel: any = nil
local _dirty = true

-- ── data ─────────────────────────────────────────────────────────────────────

local function _data(): any
	return Replica.Player and Replica.Player.Data
end

-- Owned sickles, best tier first so the strongest is always at the top.
local function _ownedSorted(): { { definition: any, count: number } }
	local data = _data()
	local owned = data and data.OwnedSickles
	if not owned then
		return {}
	end

	local list = {}
	for sickleId, count in owned do
		local definition = Sickles.Definitions.Get(sickleId)
		if definition and count > 0 then
			table.insert(list, { definition = definition, count = count })
		end
	end

	table.sort(list, function(a, b)
		local rankA = Sickles.Tiers.Rank(a.definition.tier)
		local rankB = Sickles.Tiers.Rank(b.definition.tier)
		if rankA ~= rankB then
			return rankA > rankB
		end
		return a.definition.name < b.definition.name
	end)

	return list
end

-- ── cards ────────────────────────────────────────────────────────────────────

local function _statLine(parent: Instance, order: number, text: string, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, 16)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = color
	label.Text = text
	label.Parent = parent
	return label
end

local function _buildCard(entry: any, equippedId: string?, order: number): Frame
	local definition = entry.definition
	local tier = Sickles.Tiers.Get(definition.tier)
	local isEquipped = definition.id == equippedId

	local card = Instance.new("Frame")
	card.Name = definition.id
	card.LayoutOrder = order
	card.Size = UDim2.new(1, 0, 0, CARD_HEIGHT)
	card.BackgroundColor3 = Color3.fromRGB(32, 36, 45)
	card.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = tier.color
	stroke.Thickness = if isEquipped then 3 else 1.5
	stroke.Transparency = if isEquipped then 0 else 0.45
	stroke.Parent = card

	-- Tier stripe down the left edge: the fastest read of rarity in a list.
	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, 6, 1, -16)
	stripe.Position = UDim2.fromOffset(8, 8)
	stripe.BackgroundColor3 = tier.color
	stripe.BorderSizePixel = 0
	stripe.Parent = card
	local stripeCorner = Instance.new("UICorner")
	stripeCorner.CornerRadius = UDim.new(1, 0)
	stripeCorner.Parent = stripe

	local info = Instance.new("Frame")
	info.Position = UDim2.fromOffset(24, 8)
	info.Size = UDim2.new(1, -24 - EQUIP_BUTTON_WIDTH - 20, 1, -16)
	info.BackgroundTransparency = 1
	info.Parent = card

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = info

	local name = Instance.new("TextLabel")
	name.LayoutOrder = 1
	name.Size = UDim2.new(1, 0, 0, 22)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextSize = 18
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextColor3 = Color3.new(1, 1, 1)
	name.Text = definition.name .. (if entry.count > 1 then `  x{entry.count}` else "")
	name.Parent = info

	_statLine(info, 2, string.upper(tier.name), tier.color)
	_statLine(
		info,
		3,
		string.format("DMG %d   RANGE %d   MULTI %d", definition.damage, definition.range, definition.baseMultiHit),
		Color3.fromRGB(200, 206, 216)
	)

	-- Ability is what actually makes a sickle worth going back to, so it is
	-- tinted in the tier colour rather than left as another grey stat line.
	local ability = Sickles.Abilities.Describe(definition.ability, definition.abilityPotency or 0)
	_statLine(info, 4, ability or "No ability", if ability then tier.color else Color3.fromRGB(130, 136, 148))

	local button = Instance.new("TextButton")
	button.Name = "Equip"
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -10, 0.5, 0)
	button.Size = UDim2.fromOffset(EQUIP_BUTTON_WIDTH, 46)
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.TextSize = 15
	button.Parent = card
	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 8)
	buttonCorner.Parent = button

	if isEquipped then
		button.Text = "EQUIPPED"
		button.BackgroundColor3 = Color3.fromRGB(46, 52, 64)
		button.TextColor3 = Color3.fromRGB(150, 255, 160)
		button.Active = false
	else
		button.Text = "EQUIP"
		button.BackgroundColor3 = tier.color
		button.TextColor3 = Color3.fromRGB(20, 24, 30)
		Ripple.Bind(button)
		button.Activated:Connect(function()
			Relay.Crates.EquipSickle.send({ sickleId = definition.id })
		end)
	end

	return card
end

-- ── refresh ──────────────────────────────────────────────────────────────────

local function _refresh()
	if not _panel or not _panel:IsVisible() then
		-- Rebuilt on next open rather than while hidden, so cutting never pays
		-- for a panel nobody is looking at.
		_dirty = true
		return
	end
	_dirty = false

	local data = _data()
	local equippedId = data and data.EquippedSickle
	local owned = _ownedSorted()

	_panel:ClearContent()
	_panel:SetSubtitle(string.format("%d / %d collected", #owned, #Sickles.Definitions.List()))

	if #owned == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, 0, 0, 60)
		empty.BackgroundTransparency = 1
		empty.Font = Enum.Font.GothamMedium
		empty.TextSize = 16
		empty.TextColor3 = Color3.fromRGB(150, 156, 168)
		empty.Text = "Open a crate to find your first sickle."
		empty.Parent = _panel.Content
		return
	end

	for index, entry in owned do
		_buildCard(entry, equippedId, index).Parent = _panel.Content
	end
end

-- ── lifecycle ────────────────────────────────────────────────────────────────

local function _bindHudButton()
	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	local main = playerGui:WaitForChild("Main", 10)
	if not main then
		return
	end

	local hud = main:FindFirstChild("HUD")
	local buttons = hud and hud:FindFirstChild("LeftSide")
	buttons = buttons and buttons:FindFirstChild("2ndButtons")
	local button = buttons and buttons:FindFirstChild("Boosts1")
	if not button or not button:IsA("GuiButton") then
		return
	end

	-- The kit's spare HUD slot becomes Sickles; Collection keeps its own button.
	local title = button:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		ShadowText.Set(title, "Sickles")
	end

	Ripple.Bind(button)
	button.Activated:Connect(function()
		SickleInventoryController.Toggle()
	end)
end

function SickleInventoryController:Start(_fw: any)
	_panel = Panel.new("SICKLES", { MaxWidth = 700, MaxHeight = 600 })

	task.spawn(_bindHudButton)

	Replica:WaitForData("Player"):andThen(function(replica: any)
		replica:ListenToChange({ "EquippedSickle" }, _refresh)
		replica:ListenToChange({ "OwnedSickles" }, _refresh)
		_refresh()
	end)

	-- A crate result can add a sickle without the replica path firing for the
	-- inventory, so results mark it stale too.
	Relay.Crates.CrateResult.listen(function()
		_dirty = true
	end)
end

--[[
	Shows or hides the inventory.
	@param visible boolean True to open.
]]
function SickleInventoryController.SetVisible(visible: boolean)
	if not _panel then
		return
	end
	_panel:SetVisible(visible)
	if visible and _dirty then
		_refresh()
	end
end

--- Flips the panel open or closed, for the HUD button.
function SickleInventoryController.Toggle()
	if _panel then
		SickleInventoryController.SetVisible(not _panel:IsVisible())
	end
end

return SickleInventoryController
