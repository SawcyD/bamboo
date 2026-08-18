--!strict
--[[
	Panel: the modal shell the runtime-built screens share.

	The authored kit has panel chrome for OpenBoxes and Settings, but the
	inventory and collection screens have no authored counterpart. Rather than
	each controller inventing its own frame, they build one from here so they
	look like the rest of the game and pick up the same mobile behaviour.

		local Panel = UI:GetModule("Panel")

		local panel = Panel.new("COLLECTION", { Tabs = { "Bamboo", "Sickles" } })
		panel:SetVisible(true)
		panel.Content.Parent -- fill this with rows

	Sized in scale with a pixel ceiling, so it fills a phone screen without
	stretching absurdly on desktop. Every touch target clears 44px.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ripple = require(script.Parent:WaitForChild("Ripple"))
local ShadowText = require(script.Parent:WaitForChild("ShadowText"))

local Panel = {}
Panel.__index = Panel

local BACKDROP_TRANSPARENCY = 0.4
local PANEL_COLOR = Color3.fromRGB(24, 27, 34)
local HEADER_COLOR = Color3.fromRGB(32, 36, 45)
local ACCENT = Color3.fromRGB(150, 255, 160)
-- Apple's floor for a comfortable touch target, which mobile needs.
local MIN_TOUCH_PX = 44

export type Options = {
	Tabs: { string }?,
	-- Widest the panel may get on desktop, in pixels.
	MaxWidth: number?,
	MaxHeight: number?,
}

export type PanelType = {
	Gui: ScreenGui,
	Frame: Frame,
	Content: ScrollingFrame,
	SetVisible: (self: PanelType, visible: boolean) -> (),
	IsVisible: (self: PanelType) -> boolean,
	SetTitle: (self: PanelType, title: string) -> (),
	SetSubtitle: (self: PanelType, text: string) -> (),
	OnTabChanged: (self: PanelType, callback: (tab: string) -> ()) -> (),
	SelectTab: (self: PanelType, tab: string) -> (),
	ActiveTab: (self: PanelType) -> string?,
	ClearContent: (self: PanelType) -> (),
	Destroy: (self: PanelType) -> (),
}

local function _corner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

--[[
	Builds a modal panel, hidden until SetVisible.
	@param title string Header text.
	@param options Options? Tabs and desktop size ceilings.
	@return PanelType The panel; fill `Content` with rows.
]]
function Panel.new(title: string, options: Options?): PanelType
	local opts = options or {}
	local self = setmetatable({}, Panel) :: any

	local gui = Instance.new("ScreenGui")
	gui.Name = "Panel_" .. title
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Panels are built at runtime, so the anti-cheat scanner would otherwise
	-- report every one of them to the server as an injected menu.
	local antiCheat = ReplicatedStorage:FindFirstChild("ClientRuntime")
	antiCheat = antiCheat and antiCheat:FindFirstChild("Controllers")
	antiCheat = antiCheat and antiCheat:FindFirstChild("AntiCheatController")
	if antiCheat then
		require(antiCheat :: ModuleScript).Approve(gui)
	end

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = BACKDROP_TRANSPARENCY
	backdrop.BorderSizePixel = 0
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.Parent = gui

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	-- Scale-first so a phone gets a near-fullscreen sheet.
	frame.Size = UDim2.fromScale(0.92, 0.86)
	frame.BackgroundColor3 = PANEL_COLOR
	frame.BorderSizePixel = 0
	frame.Parent = backdrop
	_corner(frame, 14)

	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(opts.MaxWidth or 760, opts.MaxHeight or 620)
	sizeLimit.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(58, 64, 78)
	stroke.Thickness = 2
	stroke.Parent = frame

	-- ── header ───────────────────────────────────────────────────────────────
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 62)
	header.BackgroundColor3 = HEADER_COLOR
	header.BorderSizePixel = 0
	header.Parent = frame
	_corner(header, 14)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Position = UDim2.fromOffset(18, 8)
	titleLabel.Size = UDim2.new(1, -90, 0, 30)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextScaled = true
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.Text = title
	titleLabel.Parent = header

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Position = UDim2.fromOffset(18, 36)
	subtitle.Size = UDim2.new(1, -90, 0, 18)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.TextScaled = true
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextColor3 = ACCENT
	subtitle.Text = ""
	subtitle.Parent = header

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -12, 0.5, 0)
	close.Size = UDim2.fromOffset(MIN_TOUCH_PX, MIN_TOUCH_PX)
	close.BackgroundColor3 = Color3.fromRGB(52, 58, 70)
	close.AutoButtonColor = false
	close.Font = Enum.Font.GothamBlack
	close.TextSize = 22
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Text = "X"
	close.Parent = header
	_corner(close, 10)
	Ripple.Bind(close)

	-- ── tabs ─────────────────────────────────────────────────────────────────
	local tabs = opts.Tabs
	local tabBar: Frame? = nil
	local tabButtons: { [string]: TextButton } = {}
	local contentTop = 62

	if tabs and #tabs > 0 then
		contentTop = 62 + MIN_TOUCH_PX + 8

		local bar = Instance.new("Frame")
		bar.Name = "Tabs"
		bar.Position = UDim2.fromOffset(12, 66)
		bar.Size = UDim2.new(1, -24, 0, MIN_TOUCH_PX)
		bar.BackgroundTransparency = 1
		bar.Parent = frame
		tabBar = bar

		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.Padding = UDim.new(0, 8)
		layout.Parent = bar

		for index, tabName in tabs do
			local button = Instance.new("TextButton")
			button.Name = tabName
			button.LayoutOrder = index
			-- Even split, so two tabs each get half the width on a phone.
			button.Size = UDim2.new(1 / #tabs, -8, 1, 0)
			button.BackgroundColor3 = HEADER_COLOR
			button.AutoButtonColor = false
			button.Font = Enum.Font.GothamBold
			button.TextSize = 16
			button.TextColor3 = Color3.fromRGB(170, 176, 188)
			button.Text = tabName
			button.Parent = bar
			_corner(button, 10)
			Ripple.Bind(button)
			tabButtons[tabName] = button
		end
	end

	-- ── content ──────────────────────────────────────────────────────────────
	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.Position = UDim2.fromOffset(12, contentTop)
	content.Size = UDim2.new(1, -24, 1, -contentTop - 12)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 4
	content.ScrollBarImageColor3 = Color3.fromRGB(90, 96, 110)
	content.CanvasSize = UDim2.new()
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.Parent = frame

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Padding = UDim.new(0, 8)
	contentLayout.Parent = content

	self.Gui = gui
	self.Frame = frame
	self.Content = content
	self._title = titleLabel
	self._subtitle = subtitle
	self._tabButtons = tabButtons
	self._tabBar = tabBar
	self._activeTab = tabs and tabs[1] or nil
	self._tabCallback = nil

	local function refreshTabs()
		for name, button in tabButtons do
			local active = name == self._activeTab
			button.BackgroundColor3 = if active then ACCENT else HEADER_COLOR
			button.TextColor3 = if active then Color3.fromRGB(20, 24, 30) else Color3.fromRGB(170, 176, 188)
		end
	end
	self._refreshTabs = refreshTabs

	for name, button in tabButtons do
		button.Activated:Connect(function()
			self:SelectTab(name)
		end)
	end
	refreshTabs()

	local function hide()
		self:SetVisible(false)
	end
	close.Activated:Connect(hide)
	-- Tapping outside is the expected way to dismiss a sheet on mobile.
	backdrop.Activated:Connect(hide)

	-- The panel swallows the tap so it never falls through to the backdrop.
	frame.InputBegan:Connect(function() end)
	frame.Active = true

	-- Respect the topbar inset so the header is never under it.
	local inset = GuiService:GetGuiInset()
	frame.Position = UDim2.new(0.5, 0, 0.5, inset.Y * 0.5)

	return self :: PanelType
end

function Panel:SetVisible(visible: boolean)
	self.Gui.Enabled = visible
end

function Panel:IsVisible(): boolean
	return self.Gui.Enabled
end

function Panel:SetTitle(title: string)
	ShadowText.Set(self._title, title)
end

--- Secondary header line, e.g. "7 / 9 discovered".
function Panel:SetSubtitle(text: string)
	ShadowText.Set(self._subtitle, text)
end

function Panel:OnTabChanged(callback: (tab: string) -> ())
	self._tabCallback = callback
end

function Panel:SelectTab(tab: string)
	if self._activeTab == tab or not self._tabButtons[tab] then
		return
	end
	self._activeTab = tab
	self._refreshTabs()
	if self._tabCallback then
		self._tabCallback(tab)
	end
end

function Panel:ActiveTab(): string?
	return self._activeTab
end

--- Removes every row, leaving the layout in place.
function Panel:ClearContent()
	for _, child in self.Content:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function Panel:Destroy()
	self.Gui:Destroy()
end

return Panel
