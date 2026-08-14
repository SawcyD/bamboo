--!strict
--[[
	Ripple: material-style click feedback for any GuiButton.

	Bind a button once and every press expands a fading circle from the exact
	point of contact. Written as a module so no button has to carry its own
	copy of the animation.

		local Ripple = UI:GetModule("Ripple")

		Ripple.Bind(myButton, { Color = Color3.fromRGB(255, 255, 255) })

	`Bind` returns a cleanup function; call it when the button goes away.
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Ripple = {}

local DEFAULT_COLOR = Color3.fromRGB(255, 255, 255)
local DEFAULT_TRANSPARENCY = 0.6
local DEFAULT_DURATION = 0.45
-- Circle grows to this multiple of the button's longest side, so it always
-- clears the corners no matter where the press landed.
local COVERAGE = 2.2

export type Options = {
	Color: Color3?,
	Transparency: Color3 | number?,
	Duration: number?,
	-- Ripples are clipped to the button by default; the module sets
	-- ClipsDescendants for you unless this is false.
	Clip: boolean?,
}

local function _resolveOrigin(button: GuiObject, inputPosition: Vector2?): Vector2
	if not inputPosition then
		return button.AbsoluteSize * 0.5
	end
	-- AbsolutePosition excludes the topbar inset that input positions include.
	local inset = game:GetService("GuiService"):GetGuiInset()
	return inputPosition + inset - button.AbsolutePosition
end

--[[
	Plays one ripple on a GuiObject.
	@param button GuiObject The frame or button the ripple is drawn inside.
	@param inputPosition Vector2? Screen position of the press; centres if omitted.
	@param options Options? Colour, transparency, and duration overrides.
]]
function Ripple.Play(button: GuiObject, inputPosition: Vector2?, options: Options?)
	if not RunService:IsClient() or not button.Parent then
		return
	end

	local opts = options or {}
	local duration = opts.Duration or DEFAULT_DURATION
	local transparency = if type(opts.Transparency) == "number" then opts.Transparency else DEFAULT_TRANSPARENCY

	local origin = _resolveOrigin(button, inputPosition)
	local diameter = math.max(button.AbsoluteSize.X, button.AbsoluteSize.Y) * COVERAGE

	local circle = Instance.new("Frame")
	circle.Name = "Ripple"
	circle.AnchorPoint = Vector2.new(0.5, 0.5)
	circle.Position = UDim2.fromOffset(origin.X, origin.Y)
	circle.Size = UDim2.fromOffset(0, 0)
	circle.BackgroundColor3 = opts.Color or DEFAULT_COLOR
	circle.BackgroundTransparency = transparency
	circle.BorderSizePixel = 0
	circle.ZIndex = button.ZIndex + 1
	circle.Parent = button

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = circle

	local grow =
		TweenService:Create(circle, TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(diameter, diameter),
			BackgroundTransparency = 1,
		})
	grow:Play()
	grow.Completed:Once(function()
		circle:Destroy()
	end)
end

--[[
	Makes every press on a button ripple from where it was pressed.
	@param button GuiButton The button to decorate.
	@param options Options? Colour, transparency, duration, and clipping overrides.
	@return () -> () Cleanup that disconnects the binding.
]]
function Ripple.Bind(button: GuiButton, options: Options?): () -> ()
	local opts = options or {}
	if opts.Clip ~= false then
		button.ClipsDescendants = true
	end

	local connection = button.InputBegan:Connect(function(input: InputObject)
		local isPress = input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		if not isPress then
			return
		end
		Ripple.Play(button, Vector2.new(input.Position.X, input.Position.Y), options)
	end)

	-- Gamepad/keyboard activation has no input position, so ripple from centre.
	local activated = button.Activated:Connect(function(inputObject: InputObject?)
		if inputObject and UserInputService:GetLastInputType() ~= Enum.UserInputType.Gamepad1 then
			return
		end
		Ripple.Play(button, nil, options)
	end)

	return function()
		connection:Disconnect()
		activated:Disconnect()
	end
end

return Ripple
