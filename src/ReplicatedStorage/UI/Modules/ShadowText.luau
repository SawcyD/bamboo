--!strict
--[[
	ShadowText: drives the two-layer text component from the UI kit.

	The kit builds punchy text out of two stacked TextLabels — a root label that
	sits slightly low and dark (the shadow) and a child label offset up and
	forward (the face). Both carry the same string, so setting only one leaves
	the other showing a stale value.

	This module hides that. Point it at the root and it keeps both in sync.

		local ShadowText = UI:GetModule("ShadowText")

		ShadowText.Set(cashFrame.Double, "$1,240")

		-- or bind once and reuse
		local cash = ShadowText.Wrap(cashFrame.Double)
		cash:Set("$1,240")
		cash:SetColor(Color3.fromRGB(150, 255, 160))

	Roots are tagged with a `ComponentName` attribute of "ShadowText" in the kit,
	but the layout is also detected structurally, so untagged copies still work.
]]

local ShadowText = {}

local COMPONENT_ATTRIBUTE = "ComponentName"
local COMPONENT_NAME = "ShadowText"

export type Handle = {
	Root: TextLabel,
	Face: TextLabel?,
	Set: (self: Handle, text: string) -> (),
	SetColor: (self: Handle, color: Color3) -> (),
	SetTransparency: (self: Handle, transparency: number) -> (),
}

-- ── detection ────────────────────────────────────────────────────────────────

--[[
	Whether an instance is a ShadowText root.
	@param instance Instance Candidate to test.
	@return boolean True for a tagged root, or a TextLabel with a TextLabel child.
]]
function ShadowText.Is(instance: Instance): boolean
	if not instance:IsA("TextLabel") then
		return false
	end
	if instance:GetAttribute(COMPONENT_ATTRIBUTE) == COMPONENT_NAME then
		return true
	end
	return instance:FindFirstChildWhichIsA("TextLabel") ~= nil
end

-- The face is the front layer: the first TextLabel child of the root. The kit
-- names it inconsistently (Amount, Double, Title), so it is found by class.
local function _face(root: TextLabel): TextLabel?
	return root:FindFirstChildWhichIsA("TextLabel")
end

-- ── one-shot setters ─────────────────────────────────────────────────────────

--[[
	Sets the string on both layers of a ShadowText.
	Safe to call on a plain TextLabel, which just sets the one layer.
	@param root TextLabel The ShadowText root (the shadow layer).
	@param text string Text to show on both layers.
]]
function ShadowText.Set(root: TextLabel, text: string)
	root.Text = text
	local face = _face(root)
	if face then
		face.Text = text
	end
end

--[[
	Recolours the face layer, leaving the shadow dark so the depth survives.
	@param root TextLabel The ShadowText root.
	@param color Color3 Colour for the front layer.
	@param shadowColor Color3? Optional shadow colour; unchanged when omitted.
]]
function ShadowText.SetColor(root: TextLabel, color: Color3, shadowColor: Color3?)
	local face = _face(root)
	if face then
		face.TextColor3 = color
		if shadowColor then
			root.TextColor3 = shadowColor
		end
	else
		root.TextColor3 = color
	end
end

--[[
	Fades both layers together, e.g. for a label that animates out.
	@param root TextLabel The ShadowText root.
	@param transparency number 0 is opaque, 1 is invisible.
]]
function ShadowText.SetTransparency(root: TextLabel, transparency: number)
	root.TextTransparency = transparency
	local face = _face(root)
	if face then
		face.TextTransparency = transparency
	end
end

--[[
	Sets several ShadowTexts at once by child name.
	Skips names that are missing, so partial UI never errors.
	@param container Instance Ancestor holding the labels.
	@param values { [string]: string } Descendant name → text to show.
]]
function ShadowText.SetAll(container: Instance, values: { [string]: string })
	for name, text in values do
		local label = container:FindFirstChild(name, true)
		if label and label:IsA("TextLabel") then
			ShadowText.Set(label, text)
		end
	end
end

-- ── handle ───────────────────────────────────────────────────────────────────

--[[
	Binds a ShadowText root once, for labels updated repeatedly.
	Caches the face lookup so a per-frame counter isn't searching every update.
	@param root TextLabel The ShadowText root.
	@return Handle Object with Set / SetColor / SetTransparency.
]]
function ShadowText.Wrap(root: TextLabel): Handle
	local handle = {
		Root = root,
		Face = _face(root),
	} :: any

	function handle:Set(text: string)
		self.Root.Text = text
		if self.Face then
			self.Face.Text = text
		end
	end

	function handle:SetColor(color: Color3)
		if self.Face then
			self.Face.TextColor3 = color
		else
			self.Root.TextColor3 = color
		end
	end

	function handle:SetTransparency(transparency: number)
		self.Root.TextTransparency = transparency
		if self.Face then
			self.Face.TextTransparency = transparency
		end
	end

	return handle :: Handle
end

return ShadowText
