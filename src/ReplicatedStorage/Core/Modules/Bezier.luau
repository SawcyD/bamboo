--!strict
--[[
	Bezier: quadratic/cubic bezier curves over numbers or Vector3s.

		local curve = Bezier.new(startPos, controlPos, endPos)            -- quadratic
		local curve = Bezier.new(startPos, c1, c2, endPos)                -- cubic

		curve:Position(t)        -- point at t (0..1)
		curve:Derivative(t)      -- velocity/tangent at t (orient projectiles with this)
		curve:Length()           -- cached arc length estimate
		curve:PositionAtDistance(d) -- point d studs along the curve (arc-length parameterized,
		                            -- use for constant-speed travel; plain t is not constant speed)

	Static helpers (no allocation):
		Bezier.Quadratic(p0, p1, p2, t)
		Bezier.Cubic(p0, p1, p2, p3, t)
]]

local Bezier = {}
Bezier.__index = Bezier

local ARC_SAMPLES = 32

type Point = Vector3 | number

function Bezier.Quadratic(p0: Point, p1: Point, p2: Point, t: number): Point
	local u = 1 - t
	return (p0 :: any) * (u * u) + (p1 :: any) * (2 * u * t) + (p2 :: any) * (t * t)
end

function Bezier.Cubic(p0: Point, p1: Point, p2: Point, p3: Point, t: number): Point
	local u = 1 - t
	return (p0 :: any) * (u * u * u)
		+ (p1 :: any) * (3 * u * u * t)
		+ (p2 :: any) * (3 * u * t * t)
		+ (p3 :: any) * (t * t * t)
end

export type BezierType = typeof(setmetatable(
	{} :: {
		_points: { Point },
		_cubic: boolean,
		_lengths: { number }?,
		_totalLength: number?,
	},
	Bezier
))

function Bezier.new(...: Point): BezierType
	local points = { ... }
	assert(#points == 3 or #points == 4, "Bezier.new expects 3 (quadratic) or 4 (cubic) points")
	return setmetatable({
		_points = points,
		_cubic = #points == 4,
		_lengths = nil,
		_totalLength = nil,
	}, Bezier)
end

function Bezier.Position(self: BezierType, t: number): Point
	local p = self._points
	if self._cubic then
		return Bezier.Cubic(p[1], p[2], p[3], p[4], t)
	end
	return Bezier.Quadratic(p[1], p[2], p[3], t)
end

function Bezier.Derivative(self: BezierType, t: number): Point
	local p = self._points
	local u = 1 - t
	if self._cubic then
		return ((p[2] :: any) - (p[1] :: any)) * (3 * u * u)
			+ ((p[3] :: any) - (p[2] :: any)) * (6 * u * t)
			+ ((p[4] :: any) - (p[3] :: any)) * (3 * t * t)
	end
	return ((p[2] :: any) - (p[1] :: any)) * (2 * u) + ((p[3] :: any) - (p[2] :: any)) * (2 * t)
end

local function magnitudeOf(delta: any): number
	if typeof(delta) == "Vector3" then
		return delta.Magnitude
	end
	return math.abs(delta)
end

-- builds the cumulative arc-length table (lazy, once)
local function ensureLengths(self: BezierType)
	if self._lengths then
		return
	end
	local lengths = table.create(ARC_SAMPLES)
	local total = 0
	local prev = Bezier.Position(self, 0)
	for i = 1, ARC_SAMPLES do
		local point = Bezier.Position(self, i / ARC_SAMPLES)
		total += magnitudeOf((point :: any) - (prev :: any))
		lengths[i] = total
		prev = point
	end
	self._lengths = lengths
	self._totalLength = total
end

function Bezier.Length(self: BezierType): number
	ensureLengths(self)
	return self._totalLength :: number
end

--- t such that the curve covers `distance` studs from the start (clamped to [0, 1]).
function Bezier.TAtDistance(self: BezierType, distance: number): number
	ensureLengths(self)
	local lengths = self._lengths :: { number }
	local total = self._totalLength :: number
	if distance <= 0 then
		return 0
	end
	if distance >= total then
		return 1
	end
	for i = 1, ARC_SAMPLES do
		if lengths[i] >= distance then
			local prevLength = if i == 1 then 0 else lengths[i - 1]
			local segment = lengths[i] - prevLength
			local frac = if segment > 0 then (distance - prevLength) / segment else 0
			return (i - 1 + frac) / ARC_SAMPLES
		end
	end
	return 1
end

function Bezier.PositionAtDistance(self: BezierType, distance: number): Point
	return Bezier.Position(self, Bezier.TAtDistance(self, distance))
end

return Bezier
