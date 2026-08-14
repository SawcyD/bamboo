--!strict
-- Spawns sparkle ImageLabels on a host GuiObject; requires template or builds a tiny dot.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RNG = Random.new()

local function getSparkleTemplate(): ImageLabel?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end
	local ui = assets:FindFirstChild("UI")
	if not ui then
		return nil
	end
	local fx = ui:FindFirstChild("FX")
	if fx then
		local s = fx:FindFirstChild("Sparkle")
		if s and s:IsA("ImageLabel") then
			return s
		end
	end
	return nil
end

local function makeFallbackSparkle(): ImageLabel
	local im = Instance.new("ImageLabel")
	im.BackgroundTransparency = 1
	im.Image = "rbxassetid://6031094669"
	im.ImageTransparency = 0.2
	return im
end

--- intervalRange: { minWait, maxWait } between spawns; extraSpawns: extra loop count (reference used 1 + p10)
return function(
	host: GuiObject,
	scaleMul: number?,
	intervalRange: { number }?,
	extraSpawns: number?,
	speedMul: number?
): () -> ()
	local scale = scaleMul or 1
	local intervalLo = if intervalRange and intervalRange[1] then intervalRange[1] else 1
	local intervalHi = if intervalRange and intervalRange[2] then intervalRange[2] else 2.5
	local extra = extraSpawns or 0
	local spd = speedMul or 1

	local gui = host:FindFirstAncestorOfClass("ScreenGui")
		or host:FindFirstAncestorOfClass("BillboardGui")
		or host:FindFirstAncestorOfClass("SurfaceGui")
	if not gui then
		return function() end
	end

	local template = getSparkleTemplate()
	local stop = false

	local function spawnOne()
		local spark = if template then (template :: ImageLabel):Clone() else makeFallbackSparkle()
		spark.Position = UDim2.fromScale(RNG:NextNumber(), RNG:NextNumber())
		spark.Size = UDim2.new(0, 0, 0, 0)
		spark.ZIndex = math.max(spark.ZIndex, 99)
		spark.Parent = host

		local sz = RNG:NextNumber(0.15 * scale, 0.2 * scale)
		TweenService:Create(
			spark,
			TweenInfo.new(RNG:NextNumber(0.75, 1) / spd, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.fromScale(sz, sz) }
		).Completed
			:Connect(function()
				TweenService:Create(
					spark,
					TweenInfo.new(RNG:NextNumber(1.75, 2.5) / spd, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ Size = UDim2.new(0, 0, 0, 0) }
				).Completed
					:Wait()
				spark:Destroy()
			end)
	end

	for _ = 1, 1 + extra do
		task.spawn(function()
			while not stop and host.Parent do
				if gui.Enabled then
					spawnOne()
				end
				task.wait(RNG:NextNumber(intervalLo, intervalHi))
			end
		end)
	end

	return function()
		stop = true
	end
end
