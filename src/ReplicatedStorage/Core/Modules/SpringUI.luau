--!strict
-- Spring-based UI motion; optional CameraEffects hook for layered hide/show.

local TweenService = game:GetService("TweenService")

local SpringUI = {}

local CameraEffects
local hasCameraEffects = false

local success, cameraModule = pcall(function()
	return require(script.Parent:WaitForChild("CameraEffects"))
end)

if success then
	CameraEffects = cameraModule.getInstance()
	hasCameraEffects = true
else
	warn("[SpringUI] CameraEffects module unavailable")
end

-- Named UI groups for cinematics (set Instance Attribute "SpringUILayer" = layer name in Studio).
local uiLayers: { [string]: { GuiObject | ScreenGui } } = {}

local function _setLayerInstanceVisible(inst: GuiObject | ScreenGui, visible: boolean)
	if inst:IsA("ScreenGui") then
		(inst :: ScreenGui).Enabled = visible
	else
		(inst :: GuiObject).Visible = visible
	end
end

function SpringUI.registerUILayer(layerName: string, instance: Instance)
	if type(layerName) ~= "string" or layerName == "" then
		warn("[SpringUI] registerUILayer: invalid layer name")
		return
	end
	if not (instance:IsA("GuiObject") or instance:IsA("ScreenGui")) then
		warn("[SpringUI] registerUILayer: expected GuiObject or ScreenGui, got", instance.ClassName)
		return
	end
	local list = uiLayers[layerName]
	if not list then
		list = {}
		uiLayers[layerName] = list
	end
	for _, existing in list do
		if existing == instance then
			return
		end
	end
	table.insert(list, instance :: GuiObject | ScreenGui)
end

function SpringUI.unregisterUILayer(layerName: string, instance: Instance)
	local list = uiLayers[layerName]
	if not list then
		return
	end
	for i = #list, 1, -1 do
		if list[i] == instance then
			table.remove(list, i)
		end
	end
	if #list == 0 then
		uiLayers[layerName] = nil
	end
end

function SpringUI.setUILayerVisible(layerName: string, visible: boolean)
	local list = uiLayers[layerName]
	if not list or #list == 0 then
		return
	end
	for _, inst in list do
		if inst.Parent ~= nil then
			_setLayerInstanceVisible(inst, visible)
		end
	end
end

function SpringUI.setUILayersVisible(layerNames: { string }, visible: boolean)
	for _, name in layerNames do
		SpringUI.setUILayerVisible(name, visible)
	end
end

local SPRINGUILAYER_ATTR = "SpringUILayer"

function SpringUI.registerUILayersInInstance(root: Instance)
	local rootLayer = root:GetAttribute(SPRINGUILAYER_ATTR)
	if type(rootLayer) == "string" and rootLayer ~= "" then
		SpringUI.registerUILayer(rootLayer, root)
	end
	for _, d in root:GetDescendants() do
		local layerName = d:GetAttribute(SPRINGUILAYER_ATTR)
		if type(layerName) == "string" and layerName ~= "" then
			SpringUI.registerUILayer(layerName, d)
		end
	end
end

function SpringUI.registerUILayersFromPlayerGui(playerGui: PlayerGui)
	for _, child in playerGui:GetChildren() do
		SpringUI.registerUILayersInInstance(child)
	end
end

local SPRING_TWEENS = {
	popIn = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	fadeOut = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In),
	buttonHover = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	buttonClick = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	buttonRelease = TweenInfo.new(0.6, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
}

local function storeOriginalProperties(frame)
	if not frame:GetAttribute("OriginalSizeStored") then
		frame:SetAttribute("OriginalSizeX_Scale", frame.Size.X.Scale)
		frame:SetAttribute("OriginalSizeX_Offset", frame.Size.X.Offset)
		frame:SetAttribute("OriginalSizeY_Scale", frame.Size.Y.Scale)
		frame:SetAttribute("OriginalSizeY_Offset", frame.Size.Y.Offset)
		frame:SetAttribute("OriginalPosX_Scale", frame.Position.X.Scale)
		frame:SetAttribute("OriginalPosX_Offset", frame.Position.X.Offset)
		frame:SetAttribute("OriginalPosY_Scale", frame.Position.Y.Scale)
		frame:SetAttribute("OriginalPosY_Offset", frame.Position.Y.Offset)
		frame:SetAttribute("OriginalTransparency", frame.BackgroundTransparency)
		frame:SetAttribute("OriginalSizeStored", true)
	end

	for _, child in ipairs(frame:GetDescendants()) do
		if child:IsA("GuiObject") then
			if not child:GetAttribute("OriginalTransparencyStored") then
				child:SetAttribute("OriginalBgTransparency", child.BackgroundTransparency)

				if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
					child:SetAttribute("OriginalTextTransparency", child.TextTransparency)
					child:SetAttribute("OriginalStrokeTransparency", child.TextStrokeTransparency)
				end

				if child:IsA("ImageLabel") or child:IsA("ImageButton") then
					child:SetAttribute("OriginalImageTransparency", child.ImageTransparency)
				end

				child:SetAttribute("OriginalTransparencyStored", true)
			end
		end
	end
end

local function getOriginalSize(frame)
	return UDim2.new(
		frame:GetAttribute("OriginalSizeX_Scale") or frame.Size.X.Scale,
		frame:GetAttribute("OriginalSizeX_Offset") or frame.Size.X.Offset,
		frame:GetAttribute("OriginalSizeY_Scale") or frame.Size.Y.Scale,
		frame:GetAttribute("OriginalSizeY_Offset") or frame.Size.Y.Offset
	)
end

local function restoreTransparency(frame)
	frame.BackgroundTransparency = frame:GetAttribute("OriginalTransparency") or 0

	for _, child in ipairs(frame:GetDescendants()) do
		if child:IsA("GuiObject") then
			child.BackgroundTransparency = child:GetAttribute("OriginalBgTransparency") or child.BackgroundTransparency

			if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
				child.TextTransparency = child:GetAttribute("OriginalTextTransparency") or 0
				child.TextStrokeTransparency = child:GetAttribute("OriginalStrokeTransparency") or 0
			end

			if child:IsA("ImageLabel") or child:IsA("ImageButton") then
				child.ImageTransparency = child:GetAttribute("OriginalImageTransparency") or 0
			end
		end
	end
end

local function getTweenProperties(guiObject, targetTransparency)
	local properties = {
		BackgroundTransparency = targetTransparency,
	}

	if guiObject:IsA("TextLabel") or guiObject:IsA("TextButton") or guiObject:IsA("TextBox") then
		properties.TextTransparency = targetTransparency
		properties.TextStrokeTransparency = targetTransparency
	end

	if guiObject:IsA("ImageLabel") or guiObject:IsA("ImageButton") then
		properties.ImageTransparency = targetTransparency
	end

	return properties
end

function SpringUI.openUI(frame, customTweenInfo)
	if not frame or not frame:IsA("GuiObject") then
		warn("❌ SpringUI.openUI: Invalid frame")
		return
	end

	if frame.Visible then
		warn("frame alr visible", frame.Name)
		return
	end

	if hasCameraEffects then
		CameraEffects:enableForUI()
	end

	storeOriginalProperties(frame)

	local originalSize = getOriginalSize(frame)

	frame.Size = UDim2.new(0, 0, 0, 0)
	frame.BackgroundTransparency = 1
	frame.Visible = true

	for _, child in ipairs(frame:GetDescendants()) do
		if child:IsA("GuiObject") then
			child.BackgroundTransparency = 1

			if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
				child.TextTransparency = 1
				child.TextStrokeTransparency = 1
			end

			if child:IsA("ImageLabel") or child:IsA("ImageButton") then
				child.ImageTransparency = 1
			end
		end
	end

	local tweenInfo = customTweenInfo or SPRING_TWEENS.popIn

	local sizeTween = TweenService:Create(frame, tweenInfo, {
		Size = originalSize,
		BackgroundTransparency = frame:GetAttribute("OriginalTransparency") or 0,
	})

	sizeTween:Play()

	task.wait(0.1)

	for _, child in ipairs(frame:GetDescendants()) do
		if child:IsA("GuiObject") then
			local targetProps = {}

			targetProps.BackgroundTransparency = child:GetAttribute("OriginalBgTransparency") or 0

			if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
				targetProps.TextTransparency = child:GetAttribute("OriginalTextTransparency") or 0
				targetProps.TextStrokeTransparency = child:GetAttribute("OriginalStrokeTransparency") or 0
			end

			if child:IsA("ImageLabel") or child:IsA("ImageButton") then
				targetProps.ImageTransparency = child:GetAttribute("OriginalImageTransparency") or 0
			end

			local fadeInTween = TweenService:Create(child, tweenInfo, targetProps)
			fadeInTween:Play()
		end
	end
end

function SpringUI.closeUI(frame, customTweenInfo)
	if not frame or not frame:IsA("GuiObject") then
		warn("SpringUI.closeUI: frame??")
		return
	end

	if not frame.Visible then
		return
	end

	if hasCameraEffects then
		CameraEffects:disableForUI()
	end

	storeOriginalProperties(frame)

	local originalSize = getOriginalSize(frame)

	local tweenInfo = customTweenInfo or SPRING_TWEENS.fadeOut

	local sizeTween = TweenService:Create(frame, tweenInfo, {
		Size = UDim2.new(0, 0, 0, 0),
		BackgroundTransparency = 1,
	})

	for _, child in ipairs(frame:GetDescendants()) do
		if child:IsA("GuiObject") then
			local tweenProps = getTweenProperties(child, 1)

			local fadeTween = TweenService:Create(child, tweenInfo, tweenProps)
			fadeTween:Play()
		end
	end

	sizeTween:Play()

	sizeTween.Completed:Connect(function()
		frame.Visible = false

		frame.Size = originalSize
		restoreTransparency(frame)

		if frame.Parent and frame.Parent:IsA("ScreenGui") then
			frame.Parent.Enabled = false
		end
	end)
end

function SpringUI.toggleUI(frame)
	if frame.Visible then
		SpringUI.closeUI(frame)
	else
		SpringUI.openUI(frame)
	end
end

function SpringUI.getTweenInfo(tweenName)
	return SPRING_TWEENS[tweenName]
end

local INTERACTIVE_BUTTON = {
	HOVER_SCALE = 1.1,
	CLICK_SCALE = 0.9,
	NORMAL_SCALE = 1,
	HOVER_SOUND_ID = "rbxassetid://6895079853",
	CLICK_SOUND_ID = "rbxassetid://6042053626",
}

local function setupInteractiveButtonInternal(button: GuiButton)
	if button:GetAttribute("TweenSetup") then
		return
	end

	if not (button:IsA("TextButton") or button:IsA("ImageButton")) then
		return
	end

	button:SetAttribute("TweenSetup", true)

	local uiScale = button:FindFirstChild("TweenUIScale") :: UIScale?
	if not uiScale then
		uiScale = button:FindFirstChildOfClass("UIScale")
	end
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Name = "TweenUIScale"
		uiScale.Scale = 1
		uiScale.Parent = button
	end

	local hoverSound = button:FindFirstChild("HoverSound")
	if not hoverSound or not hoverSound:IsA("Sound") then
		hoverSound = Instance.new("Sound")
		hoverSound.Name = "HoverSound"
		hoverSound.SoundId = INTERACTIVE_BUTTON.HOVER_SOUND_ID
		hoverSound.Volume = 0.5
		hoverSound.Parent = button
	end

	local clickSound = button:FindFirstChild("ClickSound")
	if not clickSound or not clickSound:IsA("Sound") then
		clickSound = Instance.new("Sound")
		clickSound.Name = "ClickSound"
		clickSound.SoundId = INTERACTIVE_BUTTON.CLICK_SOUND_ID
		clickSound.Volume = 0.7
		clickSound.Parent = button
	end

	local hoverTween = SPRING_TWEENS.buttonHover
	local clickTween = SPRING_TWEENS.buttonClick
	local releaseTween = SPRING_TWEENS.buttonRelease

	local currentTween: Tween? = nil
	local isPressed = false
	local isHovering = false

	local function tweenScale(scale: number, info: TweenInfo)
		if currentTween then
			currentTween:Cancel()
		end

		local newTween = TweenService:Create(uiScale, info, { Scale = scale })
		currentTween = newTween
		newTween:Play()
	end

	button.MouseEnter:Connect(function()
		isHovering = true

		if not isPressed then
			tweenScale(INTERACTIVE_BUTTON.HOVER_SCALE, hoverTween)

			if hoverSound and hoverSound:IsA("Sound") then
				hoverSound:Play()
			end
		end
	end)

	button.MouseLeave:Connect(function()
		isHovering = false

		if not isPressed then
			tweenScale(INTERACTIVE_BUTTON.NORMAL_SCALE, releaseTween)
		end
	end)

	button.MouseButton1Down:Connect(function()
		isPressed = true
		tweenScale(INTERACTIVE_BUTTON.CLICK_SCALE, clickTween)

		if clickSound and clickSound:IsA("Sound") then
			clickSound:Play()
		end
	end)

	button.MouseButton1Up:Connect(function()
		isPressed = false

		local targetScale = if isHovering then INTERACTIVE_BUTTON.HOVER_SCALE else INTERACTIVE_BUTTON.NORMAL_SCALE
		local targetInfo = if isHovering then hoverTween else releaseTween
		tweenScale(targetScale, targetInfo)
	end)
end

function SpringUI.setupInteractiveButton(button: GuiButton)
	setupInteractiveButtonInternal(button)
end

function SpringUI.setupInteractiveButtonsInContainer(container: Instance)
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("TextButton") or descendant:IsA("ImageButton") then
			local ok, err = pcall(function()
				setupInteractiveButtonInternal(descendant :: GuiButton)
			end)
			if not ok then
				warn("[SpringUI] setupInteractiveButtonsInContainer failed:", descendant:GetFullName(), err)
			end
		end
	end
end

function SpringUI.bootstrapInteractiveButtons(playerGui: PlayerGui)
	for _, gui in playerGui:GetChildren() do
		if gui:IsA("ScreenGui") and gui.Enabled then
			SpringUI.setupInteractiveButtonsInContainer(gui)
		end
	end
end

return SpringUI
