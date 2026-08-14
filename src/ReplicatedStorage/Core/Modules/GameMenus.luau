--!strict
--[[
	GameMenus
	─────────────────────────────────────────────────────────────────────────────
	Registration-based system that ties dock GuiButtons to ScreenGui/Frame pairs
	with mutual exclusivity, lock, and optional first-person auto-close.

	Usage (from a frame module or controller's Start):

	    local Core = require(ReplicatedStorage.Core)
	    local GameMenus = Core:Get("GameMenus")

	    GameMenus.register({
	        id          = "Inventory",
	        screenGui   = InventoryGui,        -- ScreenGui to enable/disable
	        contentFrame = InventoryGui.Frame, -- optional: Spring open/close target
	        openButton  = InventoryIcon,       -- optional dock button
	        exclusive   = true,                -- default true
	    })

	    -- From code:
	    GameMenus.toggle("Inventory")          -- flip
	    GameMenus.toggle("Inventory", true)    -- open
	    GameMenus.toggle("Inventory", false)   -- close

	    local conn = GameMenus.onToggle("Inventory", function(open: boolean)
	        print("Inventory is now", if open then "open" else "closed")
	    end)
	    conn:Disconnect()  -- clean up when done

	    -- Or: name dock buttons to match menu ids (e.g. TextButton named "Inventory")
	    -- and call once from LeftSide (after all menus registered):
	    GameMenus.bindOpenButtonsIn(LeftSideFrame)
	─────────────────────────────────────────────────────────────────────────────
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local SpringUI = Core:Get("SpringUI")
local Relay = Core:GetShared("Network")

assert(RunService:IsClient(), "GameMenus is client-only")

-- ──────────────────────────────────────────────────────────────────────────────
-- Types
-- ──────────────────────────────────────────────────────────────────────────────

export type MenuRegistration = {
	--- Stable key; used in all public API calls.
	id: string,
	--- The ScreenGui that is enabled/disabled as the menu opens/closes.
	screenGui: ScreenGui,
	--- If provided, `SpringUI.openUI` / `closeUI` is used on this frame instead of
	--- only toggling `screenGui.Enabled`. The frame must be a direct child of screenGui.
	contentFrame: GuiObject?,
	--- Dock / sidebar button that toggles this menu. SpringUI hover/scale still
	--- applies if ButtonController already called setupInteractiveButton on it;
	--- GameMenus only wires the click callback here.
	openButton: GuiButton?,
	--- If different from openButton; clicking this always closes (never toggles).
	closeButton: GuiButton?,
	--- When true (default), opening this menu closes all other registered menus first.
	exclusive: boolean?,
	--- When true, this menu is force-closed when the camera enters first-person view.
	closeInFirstPerson: boolean?,
	--- Only relevant when contentFrame is set. When false, skips SpringUI animation
	--- and only toggles Enabled. Defaults to true.
	useSpringOpen: boolean?,
}

type MenuEntry = {
	reg: MenuRegistration,
	open: boolean,
	originalDisplayOrder: number,
	toggled: typeof((Relay.Signal :: any).new()),
	_openConn: RBXScriptConnection?,
	_closeConn: RBXScriptConnection?,
	_lastToggleClock: number,
}

-- ──────────────────────────────────────────────────────────────────────────────
-- State
-- ──────────────────────────────────────────────────────────────────────────────

local _menus: { [string]: MenuEntry } = {}
local _locked = false
local _inFirstPerson = false

--- Debounce for button clicks (seconds). Prevents double-firing on laggy input.
local TOGGLE_DEBOUNCE = 0.15
--- Camera zoom magnitude below which the player is considered in first-person.
local FP_THRESHOLD = 0.51
--- When a menu opens, ensure its ScreenGui stacks above the default HUD (DisplayOrder 0–10),
--- otherwise clicks can hit LeftSide (e.g. Collect) through the inventory.
local MENU_MIN_DISPLAY_ORDER = 50

-- ──────────────────────────────────────────────────────────────────────────────
-- Internal helpers
-- ──────────────────────────────────────────────────────────────────────────────

local function _useSpring(entry: MenuEntry): boolean
	local reg = entry.reg
	return reg.contentFrame ~= nil and reg.useSpringOpen ~= false
end

local function _forceClose(entry: MenuEntry)
	if not entry.open then
		return
	end
	entry.open = false
	local reg = entry.reg
	reg.screenGui.DisplayOrder = entry.originalDisplayOrder
	if _useSpring(entry) then
		task.spawn(function()
			SpringUI.closeUI(reg.contentFrame)
		end)
	else
		reg.screenGui.Enabled = false
	end
	entry.toggled:Fire(false)
end

local function _doOpen(entry: MenuEntry)
	entry.open = true
	local reg = entry.reg
	reg.screenGui.DisplayOrder = math.max(reg.screenGui.DisplayOrder, MENU_MIN_DISPLAY_ORDER)
	reg.screenGui.Enabled = true
	if _useSpring(entry) then
		-- SpringUI.openUI calls task.wait internally; run in a separate thread
		-- so we don't block the input callback or any code calling toggle().
		task.spawn(function()
			SpringUI.openUI(reg.contentFrame)
		end)
	end
	entry.toggled:Fire(true)
end

local function _doClose(entry: MenuEntry)
	if not entry.open then
		return
	end
	entry.open = false
	local reg = entry.reg
	reg.screenGui.DisplayOrder = entry.originalDisplayOrder
	if _useSpring(entry) then
		task.spawn(function()
			SpringUI.closeUI(reg.contentFrame)
		end)
	else
		reg.screenGui.Enabled = false
	end
	entry.toggled:Fire(false)
end

local function _closeAllExcept(excludeId: string)
	for id, entry in _menus do
		if id ~= excludeId then
			_doClose(entry)
		end
	end
end

local GameMenus = {}

local function _wireOpenButton(entry: MenuEntry, button: GuiButton)
	if entry._openConn then
		entry._openConn:Disconnect()
		entry._openConn = nil
	end
	local id = entry.reg.id
	entry._openConn = button.Activated:Connect(function()
		local now = os.clock()
		if now - entry._lastToggleClock < TOGGLE_DEBOUNCE then
			return
		end
		entry._lastToggleClock = now
		GameMenus.toggle(id)
	end)
end

--- Menu id for dock binding: String attribute `GameMenuId` wins when non-empty;
--- otherwise the button's `Name` must match the id passed to `register`.
local function _dockMenuIdFromButton(button: GuiButton): string?
	local attr = button:GetAttribute("GameMenuId")
	if type(attr) == "string" and attr ~= "" then
		return attr
	end
	if button.Name ~= "" then
		return button.Name
	end
	return nil
end

-- ──────────────────────────────────────────────────────────────────────────────
-- First-person polling (infrequent transitions; avoid per-frame work)
-- ──────────────────────────────────────────────────────────────────────────────

task.spawn(function()
	while true do
		task.wait(0.1)
		local cam = workspace.CurrentCamera
		if cam then
			local zoom = (cam.CFrame.Position - cam.Focus.Position).Magnitude
			if zoom < FP_THRESHOLD and not _inFirstPerson then
				_inFirstPerson = true
				for _, entry in _menus do
					if entry.open and entry.reg.closeInFirstPerson then
						_forceClose(entry)
					end
				end
			elseif zoom >= FP_THRESHOLD and _inFirstPerson then
				_inFirstPerson = false
			end
		end
	end
end)

-- ──────────────────────────────────────────────────────────────────────────────
-- Public API
-- ──────────────────────────────────────────────────────────────────────────────

--- Registers a new menu. Calling register with a duplicate id replaces the
--- previous registration (old button connections are cleaned up first).
function GameMenus.register(reg: MenuRegistration)
	assert(type(reg.id) == "string" and reg.id ~= "", "GameMenus.register: id must be a non-empty string")
	assert(
		typeof(reg.screenGui) == "Instance" and reg.screenGui:IsA("ScreenGui"),
		"GameMenus.register: screenGui must be a ScreenGui"
	)

	-- Clean up any previous registration for the same id
	local existing = _menus[reg.id]
	if existing then
		warn("[GameMenus] Duplicate register for id '" .. reg.id .. "'; replacing previous entry.")
		if existing._openConn then
			existing._openConn:Disconnect()
			existing._openConn = nil
		end
		if existing._closeConn then
			existing._closeConn:Disconnect()
			existing._closeConn = nil
		end
		existing.toggled:DisconnectAll()
	end

	-- Default exclusive to true
	if reg.exclusive == nil then
		(reg :: any).exclusive = true
	end

	-- Ensure initial closed state
	reg.screenGui.Enabled = false
	if reg.contentFrame then
		reg.contentFrame.Visible = false
	end

	local entry: MenuEntry = {
		reg = reg,
		open = false,
		originalDisplayOrder = reg.screenGui.DisplayOrder,
		toggled = (Relay.Signal :: any).new(),
		_openConn = nil,
		_closeConn = nil,
		_lastToggleClock = 0,
	}

	-- Wire openButton
	if reg.openButton then
		_wireOpenButton(entry, reg.openButton)
	end

	-- Wire closeButton (separate from openButton)
	if reg.closeButton and reg.closeButton ~= reg.openButton then
		entry._closeConn = reg.closeButton.Activated:Connect(function()
			GameMenus.toggle(reg.id, false)
		end)
	end

	_menus[reg.id] = entry
end

--- Toggles (or forces open/closed) a registered menu.
--- open == nil → flip current state.
--- open == true → open.
--- open == false → close.
function GameMenus.toggle(id: string, open: boolean?)
	if _locked then
		return
	end

	local entry = _menus[id]
	if not entry then
		warn("[GameMenus] toggle: no menu registered with id '" .. id .. "'")
		return
	end

	-- Resolve target state
	local targetOpen: boolean
	if open == nil then
		targetOpen = not entry.open
	else
		targetOpen = open
	end

	-- No-op if already in the correct state
	if targetOpen == entry.open then
		return
	end

	-- First-person guard: cannot open FP-closing menus while in FP
	if targetOpen and _inFirstPerson and entry.reg.closeInFirstPerson then
		return
	end

	if targetOpen then
		if entry.reg.exclusive then
			_closeAllExcept(id)
		end
		_doOpen(entry)
	else
		_doClose(entry)
	end
end

--- Closes all registered menus unconditionally (ignores lock).
function GameMenus.closeAll()
	for _, entry in _menus do
		_forceClose(entry)
	end
end

--- Prevents all toggle calls until unlock() is called.
--- Does NOT close open menus; call closeAll() first if needed.
function GameMenus.lock()
	_locked = true
end

--- Re-enables toggle calls.
function GameMenus.unlock()
	_locked = false
end

--- Returns true if the menu with `id` is currently open.
function GameMenus.isOpen(id: string): boolean
	local entry = _menus[id]
	return entry ~= nil and entry.open
end

--- Returns the id of the currently open exclusive menu, or nil if none are open.
function GameMenus.getOpenId(): string?
	for id, entry in _menus do
		if entry.open then
			return id
		end
	end
	return nil
end

--- Scans `root` (including descendants) for `GuiButton`s. If a button's menu id
--- (see `_dockMenuIdFromButton`) matches a registered menu, that button becomes
--- the open/toggle control for that menu. Replaces any previous open-button
--- connection for that menu (from `register` or an earlier bind).
---
--- Call this after all `register` calls for those ids (e.g. from `LeftSide`
--- frame `Start`, which runs after `Inventory` alphabetically in `UI:Start`).
function GameMenus.bindOpenButtonsIn(root: Instance)
	for _, desc in root:GetDescendants() do
		if desc:IsA("GuiButton") then
			local menuId = _dockMenuIdFromButton(desc)
			if menuId then
				local entry = _menus[menuId]
				if entry then
					_wireOpenButton(entry, desc)
				end
			end
		end
	end
end

--- Connects a callback that fires when the menu's open state changes.
--- The callback receives `open: boolean`.
--- Returns a Connection with a :Disconnect() method.
function GameMenus.onToggle(id: string, callback: (open: boolean) -> ()): any
	local entry = _menus[id]
	assert(entry, "[GameMenus] onToggle: no menu registered with id '" .. id .. "'")
	return entry.toggled:Connect(callback)
end

return GameMenus
