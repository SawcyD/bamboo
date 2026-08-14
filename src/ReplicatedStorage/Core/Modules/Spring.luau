--!strict
--[[
	Spring: critically-dampable numeric/vector spring (semi-implicit integration).
	Works with numbers, Vector2, and Vector3. Drive camera offsets, follower
	positions, recoil, UI values — anything that should move smoothly to a target.

		local spring = Spring.new(Vector3.zero, { speed = 20, damping = 1 })
		spring:SetTarget(goalPosition)

		RunService.Heartbeat:Connect(function(dt)
			part.Position = spring:Update(dt)
		end)

		spring:Impulse(Vector3.new(0, 50, 0)) -- kick velocity (recoil, hits)
		spring:Snap(value)                    -- jump instantly, zero velocity

	damping = 1 → critically damped (no overshoot); < 1 → bouncy; > 1 → sluggish.
]]

local Spring = {}
Spring.__index = Spring

export type SpringConfig = {
	speed: number?, -- responsiveness (default 15)
	damping: number?, -- 1 = critical (default 1)
}

export type SpringType = typeof(setmetatable(
	{} :: {
		Position: any,
		Velocity: any,
		Target: any,
		Speed: number,
		Damping: number,
	},
	Spring
))

local function zeroLike(value: any): any
	if typeof(value) == "Vector3" then
		return Vector3.zero
	elseif typeof(value) == "Vector2" then
		return Vector2.zero
	end
	return 0
end

function Spring.new(initial: any, config: SpringConfig?): SpringType
	local cfg = config or {}
	return setmetatable({
		Position = initial,
		Velocity = zeroLike(initial),
		Target = initial,
		Speed = cfg.speed or 15,
		Damping = cfg.damping or 1,
	}, Spring)
end

function Spring.SetTarget(self: SpringType, target: any)
	self.Target = target
end

function Spring.Impulse(self: SpringType, velocity: any)
	self.Velocity += velocity
end

function Spring.Snap(self: SpringType, value: any)
	self.Position = value
	self.Target = value
	self.Velocity = zeroLike(value)
end

--- Advances the spring by dt and returns the new position.
function Spring.Update(self: SpringType, dt: number): any
	local speed = self.Speed
	-- semi-implicit Euler: stable for typical speeds at variable frame times
	local accel = ((self.Target :: any) - self.Position) * (speed * speed) - self.Velocity * (2 * self.Damping * speed)
	self.Velocity += accel * dt
	self.Position += self.Velocity * dt
	return self.Position
end

--- True when close enough to the target to stop updating (visual settle check).
function Spring.IsSettled(self: SpringType, epsilon: number?): boolean
	local e = epsilon or 1e-3
	local delta = (self.Target :: any) - self.Position
	local distance = if typeof(delta) == "number" then math.abs(delta) else delta.Magnitude
	local speed = if typeof(self.Velocity) == "number" then math.abs(self.Velocity) else self.Velocity.Magnitude
	return distance < e and speed < e
end

return Spring
