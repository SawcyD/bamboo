--!strict
-- Snappy highlight ramp for egg pop (Back Out, short duration).

local TweenService = game:GetService("TweenService")

local POP_DURATION = 0.10

local HighlightBurst = {}

function HighlightBurst.popDuration(): number
	return POP_DURATION
end

--- Easing for highlight opacity vs normalized time t in [0, 1]
function HighlightBurst.popEase(t: number): number
	return TweenService:GetValue(math.clamp(t, 0, 1), Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

return HighlightBurst
