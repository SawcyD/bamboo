--!strict
-- Clones `ReplicatedStorage.Assets.UI.Message` for brief bottom notifications.
-- Rich text: outer stroke; **body** = muted description, **action** = colored emphasis (variant).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Audio = require(ReplicatedStorage:WaitForChild("Audio"))
local ToastTemplates = require(script.Parent:WaitForChild("MessageToastTemplates"))

local FADE_IN = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local LocalPlayer = Players.LocalPlayer

local _warnedMissingTemplate = false
local _warnedMissingNotificationsGui = false
local _layoutOrderSeq = 0

export type ToastVariant = "success" | "error" | "warning" | "info"
export type ToastTone = "result" | "info"

--[[ Studio: StarterGui → Notifications (ScreenGui) → Frame (UIListLayout lives here). ]]
local function _getStudioNotificationFrame(): Frame?
	local notifications = LocalPlayer.PlayerGui:FindFirstChild("Notifications")
	if not notifications or not notifications:IsA("ScreenGui") then
		return nil
	end
	local holder = notifications:FindFirstChild("Frame")
	if holder and holder:IsA("Frame") then
		notifications.Enabled = true
		return holder
	end
	return nil
end

local function _getFallbackListContainer(): Frame
	local existing = LocalPlayer.PlayerGui:FindFirstChild("MessageToasts")
	local gui: ScreenGui
	if existing and existing:IsA("ScreenGui") then
		gui = existing
	else
		gui = Instance.new("ScreenGui")
		gui.Name = "MessageToasts"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 1000
		gui.IgnoreGuiInset = true
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.Parent = LocalPlayer.PlayerGui
	end
	local container = gui:FindFirstChild("Container")
	if container and container:IsA("Frame") then
		return container
	end
	local c = Instance.new("Frame")
	c.Name = "Container"
	c.BackgroundTransparency = 1
	c.Size = UDim2.fromScale(1, 1)
	c.Position = UDim2.new(0.5, 0, 1, -24)
	c.AnchorPoint = Vector2.new(0.5, 1)
	c.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = c
	return c
end

export type ToastOpts = {
	--[[ Plain single line (escaped). Ignored if `richText`, or if `body`+`action` set. ]]
	message: string?,
	--[[ Trusted RichText (full control). ]]
	richText: string?,
	--[[ Muted context line (escaped). Pair with `action`. ]]
	body: string?,
	--[[ Emphasized takeaway (escaped). Pair with `body`. ]]
	action: string?,
	--[[ Semantic accent for `action` / single-line `message`. Default from `success` when legacy. ]]
	variant: ToastVariant?,
	--[[ Named preset from MessageToastTemplates (merged last; explicit opts override). ]]
	template: string?,
	--[[ Legacy: maps to variant success vs error when `variant` omitted. ]]
	success: boolean?,
	--[[ Legacy: "info" tone → info variant for plain message. ]]
	tone: ToastTone?,
	duration: number?,
	playSound: boolean?,
}

--- Muted description (always).
local BODY_HEX = "a8bdd4"
--- Emphasis color per variant
local ACTION_HEX: { [ToastVariant]: string } = {
	success = "8ef5b0",
	error = "ff9090",
	warning = "ffcc77",
	info = "FFFFFF",
}

local function _escapeRich(s: string): string
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local function _resolveVariant(opts: ToastOpts): ToastVariant
	local v = opts.variant
	if v == "success" or v == "error" or v == "warning" or v == "info" then
		return v
	end
	if opts.tone == "info" then
		return "info"
	end
	if opts.success == true then
		return "success"
	end
	return "error"
end

local function _wrapStrokeInner(inner: string): string
	return `<stroke color="#172b39" joins="bevel" thickness="3" transparency="0">{inner}</stroke>`
end

local function _richBodyAction(bodyEscaped: string, actionEscaped: string, variant: ToastVariant): string
	local b = BODY_HEX
	local a = ACTION_HEX[variant]
	local inner = `<font color="#{b}">{bodyEscaped}</font> <font color="#{a}"><b>{actionEscaped}</b></font>`
	return _wrapStrokeInner(inner)
end

local function _richSingleLine(messageEscaped: string, variant: ToastVariant): string
	local a = ACTION_HEX[variant]
	local inner = `<font color="#{a}">{messageEscaped}</font>`
	return _wrapStrokeInner(inner)
end

--- If the string contains an em dash or " - ", split into muted body + accent action.
local function _trySplitMessage(msg: string): (string?, string?)
	local sep = " — "
	local i = string.find(msg, sep, 1, true)
	local cutLen = #sep
	if not i then
		sep = " - "
		i = string.find(msg, sep, 1, true)
		cutLen = #sep
	end
	if i and i > 1 and i + cutLen <= #msg then
		local left = string.match(string.sub(msg, 1, i - 1), "^%s*(.-)%s*$")
		local right = string.match(string.sub(msg, i + cutLen), "^%s*(.-)%s*$")
		if left and right and left ~= "" and right ~= "" then
			return left, right
		end
	end
	return nil, nil
end

local function _buildLabelText(opts: ToastOpts): string?
	if type(opts.richText) == "string" and opts.richText ~= "" then
		return opts.richText
	end

	local variant: ToastVariant = _resolveVariant(opts)

	if type(opts.body) == "string" and opts.body ~= "" and type(opts.action) == "string" and opts.action ~= "" then
		return _richBodyAction(_escapeRich(opts.body), _escapeRich(opts.action), variant)
	end

	if type(opts.message) == "string" and opts.message ~= "" then
		local plain = opts.message
		local splitA, splitB = _trySplitMessage(plain)
		if splitA and splitB then
			return _richBodyAction(_escapeRich(splitA), _escapeRich(splitB), variant)
		end
		return _richSingleLine(_escapeRich(plain), variant)
	end

	return nil
end

local function _findTextTarget(root: Instance): TextLabel?
	local named = root:FindFirstChild("TextLabel", true)
	if named and named:IsA("TextLabel") then
		return named
	end
	local frame = root:FindFirstChild("Frame", true)
	if frame then
		local tl = frame:FindFirstChildWhichIsA("TextLabel", true)
		if tl and tl:IsA("TextLabel") then
			return tl
		end
	end
	return root:FindFirstChildWhichIsA("TextLabel", true)
end

local function _collectCanvasGroups(root: GuiObject): { CanvasGroup }
	local list: { CanvasGroup } = {}
	if root:IsA("CanvasGroup") then
		table.insert(list, root :: CanvasGroup)
	end
	for _, d in root:GetDescendants() do
		if d:IsA("CanvasGroup") then
			table.insert(list, d :: CanvasGroup)
		end
	end
	return list
end

local function _setGroupTransparency(groups: { CanvasGroup }, alpha: number)
	for _, g in groups do
		g.GroupTransparency = alpha
	end
end

local function _playTweensParallel(
	groups: { CanvasGroup },
	info: TweenInfo,
	goalTransparency: number,
	onAllFinished: (() -> ())?
)
	if #groups == 0 then
		if onAllFinished then
			onAllFinished()
		end
		return
	end
	local remaining = #groups
	local function oneDone()
		remaining -= 1
		if remaining <= 0 and onAllFinished then
			onAllFinished()
		end
	end
	for _, g in groups do
		local tw = TweenService:Create(g, info, { GroupTransparency = goalTransparency })
		tw.Completed:Connect(oneDone)
		tw:Play()
	end
end

local function _fallbackTemplate(): Frame
	local f = Instance.new("Frame")
	f.Name = "Message"
	f.BackgroundColor3 = Color3.fromRGB(24, 28, 36)
	f.BackgroundTransparency = 0.15
	f.BorderSizePixel = 0
	f.Size = UDim2.fromOffset(320, 44)
	f.AutomaticSize = Enum.AutomaticSize.Y
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = f
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = f
	local lbl = Instance.new("TextLabel")
	lbl.Name = "TextLabel"
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 0)
	lbl.AutomaticSize = Enum.AutomaticSize.Y
	lbl.Font = Enum.Font.GothamMedium
	lbl.TextSize = 16
	lbl.TextWrapped = true
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text = ""
	lbl.Parent = f
	return f
end

local MessageToast = {}

--- Merge a named template with optional overrides (e.g. `{ duration = 5 }`).
function MessageToast.ShowTemplate(name: string, overrides: ToastOpts?)
	local base = ToastTemplates.Get(name)
	if not base then
		warn("[MessageToast] Unknown template:", name)
		return
	end
	local merged: ToastOpts = {
		body = base.body,
		action = base.action,
		variant = base.variant,
	}
	if overrides then
		for k, v in overrides :: any do
			(merged :: any)[k] = v
		end
	end
	MessageToast.Show(merged)
end

function MessageToast.Show(opts: ToastOpts)
	local playSound = opts.playSound ~= false
	if playSound then
		Audio:Play("UINotification", "SFX")
	end

	if type(opts.template) == "string" and opts.template ~= "" then
		local base = ToastTemplates.Get(opts.template)
		if base then
			local userMsg = type(opts.message) == "string" and opts.message ~= ""
			local userRich = type(opts.richText) == "string" and opts.richText ~= ""
			local merged: ToastOpts
			if userMsg or userRich then
				-- Custom copy wins; keep variant from template unless overridden.
				merged = {
					richText = opts.richText,
					message = opts.message,
					variant = opts.variant or base.variant,
					success = opts.success,
					tone = opts.tone,
					duration = opts.duration,
					playSound = opts.playSound,
				}
			else
				merged = {
					body = opts.body or base.body,
					action = opts.action or base.action,
					variant = opts.variant or base.variant,
					richText = opts.richText,
					message = opts.message,
					success = opts.success,
					tone = opts.tone,
					duration = opts.duration,
					playSound = opts.playSound,
				}
			end
			opts = merged
		else
			warn("[MessageToast] Unknown template id:", opts.template)
		end
	end

	local labelText = _buildLabelText(opts)
	if not labelText then
		return
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local uiFolder = assets and assets:FindFirstChild("UI")
	local proto = uiFolder and uiFolder:FindFirstChild("Message")

	local root: GuiObject
	if proto and proto:IsA("GuiObject") then
		local c = (proto :: GuiObject):Clone()
		if c:IsA("Frame") or c:IsA("CanvasGroup") then
			root = c
		else
			if not _warnedMissingTemplate then
				_warnedMissingTemplate = true
				warn("[MessageToast] Assets.UI.Message must be a Frame or CanvasGroup; using fallback template.")
			end
			root = _fallbackTemplate()
		end
	else
		if not _warnedMissingTemplate then
			_warnedMissingTemplate = true
			warn("[MessageToast] ReplicatedStorage.Assets.UI.Message missing; using fallback template.")
		end
		root = _fallbackTemplate()
	end

	local canvasGroups = _collectCanvasGroups(root)
	_setGroupTransparency(canvasGroups, 1)

	local label = _findTextTarget(root)
	if label then
		label.RichText = true
		label.Text = labelText
		label.TextColor3 = Color3.new(1, 1, 1)
	else
		warn("[MessageToast] No TextLabel under Message template; showing nothing.")
		root:Destroy()
		return
	end

	local studioFrame = _getStudioNotificationFrame()
	local container: Frame
	local useStudioList: boolean
	if studioFrame then
		container = studioFrame
		useStudioList = true
	else
		if not _warnedMissingNotificationsGui then
			_warnedMissingNotificationsGui = true
			warn(
				"[MessageToast] PlayerGui.Notifications.Frame not found; using fallback ScreenGui MessageToasts. "
					.. "Add a ScreenGui named Notifications with a child Frame + UIListLayout under StarterGui."
			)
		end
		container = _getFallbackListContainer()
		useStudioList = false
	end

	_layoutOrderSeq += 1
	root.LayoutOrder = _layoutOrderSeq
	if not useStudioList then
		root.AnchorPoint = Vector2.new(0.5, 1)
		root.Position = UDim2.fromScale(0.5, 1)
	end
	root.Parent = container

	_playTweensParallel(canvasGroups, FADE_IN, 0, nil)

	local duration = if type(opts.duration) == "number" then opts.duration else 3.2
	task.delay(duration, function()
		if not root.Parent then
			return
		end
		if #canvasGroups > 0 then
			_playTweensParallel(canvasGroups, FADE_OUT, 1, function()
				if root.Parent then
					root:Destroy()
				end
			end)
		else
			root:Destroy()
		end
	end)
end

return MessageToast
