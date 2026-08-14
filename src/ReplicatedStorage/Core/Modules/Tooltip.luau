--!strict
-- Tooltip module: attach a hover tooltip to any GuiObject.
-- Usage:
--   local stopTooltip = Tooltip(guiObject, "My tooltip text")
--   -- call stopTooltip() to disconnect and hide

local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local function getOrCreateHolder(playerGui: PlayerGui): ScreenGui
	local existing = playerGui:FindFirstChild("TooltipsFolder")
	if existing and existing:IsA("ScreenGui") then
		return existing :: ScreenGui
	end
	local sg = Instance.new("ScreenGui")
	sg.Name = "TooltipsFolder"
	sg.DisplayOrder = 999
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.Parent = playerGui
	return sg
end

return function(target: GuiObject, text: string): () -> ()
	-- Skip on mobile (no mouse hover)
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return function() end
	end

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local holder = getOrCreateHolder(playerGui)

	local label: TextLabel? = nil
	local dismissed = false
	local connections: { RBXScriptConnection } = {}

	local function removeLabel()
		if label then
			label:Destroy()
			label = nil
		end
	end

	local function showLabel()
		holder:ClearAllChildren()
		dismissed = false

		local lbl = Instance.new("TextLabel")
		lbl.BorderSizePixel = 0
		lbl.BackgroundColor3 = Color3.new(1, 1, 1)
		lbl.TextColor3 = Color3.fromRGB(26, 26, 26)
		lbl.TextSize = 18
		lbl.Font = Enum.Font.FredokaOne
		lbl.Text = text
		lbl.ZIndex = 10

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.45, 0)
		corner.Parent = lbl

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(26, 26, 26)
		stroke.Thickness = 2
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = lbl

		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 6)
		padding.PaddingBottom = UDim.new(0, 6)
		padding.PaddingLeft = UDim.new(0, 8)
		padding.PaddingRight = UDim.new(0, 8)
		padding.Parent = lbl

		local textSize = TextService:GetTextSize(text, 18, Enum.Font.FredokaOne, Vector2.new(1000, 1000))
		lbl.Size = UDim2.fromOffset(textSize.X + 16, textSize.Y + 12)
		lbl.Parent = holder
		label = lbl

		-- Follow the mouse each frame until cursor leaves target
		task.spawn(function()
			while not dismissed and label and label.Parent and target and target.Parent do
				local mouse = Players.LocalPlayer:GetMouse()
				local mx, my = mouse.X, mouse.Y
				local ap = target.AbsolutePosition
				local as = target.AbsoluteSize
				-- If mouse has moved outside the target, dismiss
				if mx < ap.X - 10 or mx > ap.X + as.X + 10 or my < ap.Y - 10 or my > ap.Y + as.Y + 10 then
					dismissed = true
					break
				end
				lbl.Position = UDim2.fromOffset(mx + 17, my)
				RunService.RenderStepped:Wait()
			end
			removeLabel()
		end)
	end

	connections[#connections + 1] = target.MouseEnter:Connect(function()
		removeLabel()
		showLabel()
	end)

	connections[#connections + 1] = target.MouseLeave:Connect(function()
		dismissed = true
		removeLabel()
	end)

	return function()
		dismissed = true
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
		removeLabel()
	end
end
