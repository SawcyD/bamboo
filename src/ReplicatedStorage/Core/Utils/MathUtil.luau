--!strict

local MathUtil = {}

-- clamps value between min and max
function MathUtil.clamp(value: number, min: number, max: number): number
	return math.max(min, math.min(max, value))
end

-- linearly interpolates between a and b by t (unclamped)
function MathUtil.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- linearly interpolates between a and b by t, clamped to [0, 1]
function MathUtil.lerpClamped(a: number, b: number, t: number): number
	return MathUtil.lerp(a, b, MathUtil.clamp(t, 0, 1))
end

-- inverse lerp: returns t such that lerp(a, b, t) == value
function MathUtil.inverseLerp(a: number, b: number, value: number): number
	if a == b then
		return 0
	end
	return (value - a) / (b - a)
end

-- remaps value from [inMin, inMax] to [outMin, outMax]
function MathUtil.remap(value: number, inMin: number, inMax: number, outMin: number, outMax: number): number
	return MathUtil.lerp(outMin, outMax, MathUtil.inverseLerp(inMin, inMax, value))
end

-- rounds to the nearest multiple
function MathUtil.roundTo(value: number, multiple: number): number
	return math.round(value / multiple) * multiple
end

-- returns a random number in [min, max]
function MathUtil.randomRange(min: number, max: number): number
	return min + math.random() * (max - min)
end

-- returns a random integer in [min, max] inclusive
function MathUtil.randomInt(min: number, max: number): number
	return math.random(min, max)
end

-- returns sign of value: -1, 0, or 1
function MathUtil.sign(value: number): number
	if value > 0 then
		return 1
	elseif value < 0 then
		return -1
	end
	return 0
end

-- frame-rate independent exponential decay toward target (use instead of lerp(a, b, k) in loops)
function MathUtil.damp(current: number, target: number, smoothing: number, dt: number): number
	return MathUtil.lerp(current, target, 1 - math.exp(-smoothing * dt))
end

-- smooth hermite interpolation of t in [0, 1] (ease in/out)
function MathUtil.smoothstep(t: number): number
	t = MathUtil.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- common easings over t in [0, 1]; pair with lerp: lerp(a, b, MathUtil.easeOutQuad(t))
function MathUtil.easeInQuad(t: number): number
	return t * t
end

function MathUtil.easeOutQuad(t: number): number
	return 1 - (1 - t) * (1 - t)
end

function MathUtil.easeInOutQuad(t: number): number
	return if t < 0.5 then 2 * t * t else 1 - (-2 * t + 2) ^ 2 / 2
end

function MathUtil.easeOutCubic(t: number): number
	return 1 - (1 - t) ^ 3
end

function MathUtil.easeOutExpo(t: number): number
	return if t >= 1 then 1 else 1 - 2 ^ (-10 * t)
end

return MathUtil
