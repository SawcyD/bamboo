--!strict
-- Fullscreen-style flash: tween transparency in, then out, destroy frame.

local TweenService = game:GetService("TweenService")

export type FlashParams = {
	fadeInSec: number?,
	fadeOutSec: number?,
	color: Color3?,
	peakTransparency: number?,
}

return function(parent: Instance, params: FlashParams?)
	local fadeInSec = if params and params.fadeInSec ~= nil then params.fadeInSec else 1
	local fadeOutSec = if params and params.fadeOutSec ~= nil then params.fadeOutSec else 1
	local color = if params and params.color ~= nil then params.color else Color3.new(1, 1, 1)
	local peakTransparency = if params and params.peakTransparency ~= nil then params.peakTransparency else 0

	task.spawn(function()
		local frame = Instance.new("Frame")
		frame.BackgroundTransparency = 1
		frame.BackgroundColor3 = color
		frame.Size = UDim2.fromScale(2, 2)
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5, 0.5)
		frame.BorderSizePixel = 0
		frame.ZIndex = 10000
		frame.Parent = parent

		if fadeInSec > 0 then
			TweenService:Create(
				frame,
				TweenInfo.new(fadeInSec, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
				{ BackgroundTransparency = peakTransparency }
			):Play()
			task.wait(fadeInSec)
		else
			frame.BackgroundTransparency = peakTransparency
		end

		if fadeOutSec > 0 then
			TweenService:Create(
				frame,
				TweenInfo.new(fadeOutSec, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ BackgroundTransparency = 1 }
			):Play()
			task.wait(fadeOutSec)
		else
			frame.BackgroundTransparency = 1
		end

		frame:Destroy()
	end)
end
