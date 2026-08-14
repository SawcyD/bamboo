--!strict
-- Animated rainbow ColorSequence on a UIGradient (RenderStepped).

local RunService = game:GetService("RunService")

local RAINBOW = {
	Color3.fromRGB(255, 0, 0),
	Color3.fromRGB(255, 127, 0),
	Color3.fromRGB(255, 255, 0),
	Color3.fromRGB(0, 255, 0),
	Color3.fromRGB(0, 255, 255),
	Color3.fromRGB(0, 0, 255),
	Color3.fromRGB(255, 0, 255),
}

return function(gradient: UIGradient): (() -> (), RBXScriptConnection)
	if not gradient:IsA("UIGradient") then
		local g = Instance.new("UIGradient")
		g.Rotation = 45
		g.Parent = gradient
		gradient = g
	end

	local nCols = #RAINBOW
	local seg = 1 / nCols

	local function update()
		local cycle = os.clock() % 3 / 3
		local keypoints: { ColorSequenceKeypoint } = {}
		local edge = false
		for k = 1, nCols + 1 do
			local col = RAINBOW[k] or RAINBOW[k - nCols]
			local t = cycle + (k - 1) / nCols
			if t > 1 then
				t -= 1
			end
			if t == 0 or t == 1 then
				edge = true
			end
			table.insert(keypoints, ColorSequenceKeypoint.new(t, col))
		end
		if not edge then
			local idx = (1 - cycle) / seg + 1
			local i0 = math.floor(math.clamp(idx, 1, nCols))
			local i1 = math.ceil(math.clamp(idx, 1, nCols))
			local c = RAINBOW[i0]:Lerp(RAINBOW[math.clamp(i1, 1, nCols)] or RAINBOW[1], idx % 1)
			table.insert(keypoints, ColorSequenceKeypoint.new(0, c))
			table.insert(keypoints, ColorSequenceKeypoint.new(1, c))
		end
		table.sort(keypoints, function(a, b)
			return a.Time < b.Time
		end)
		gradient.Color = ColorSequence.new(keypoints)
	end

	local conn = RunService.RenderStepped:Connect(update)

	local function stop()
		conn:Disconnect()
	end

	return stop, conn
end
