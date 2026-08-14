--!strict
--[[
	Projectile: shared simulation for client visuals + server validation.

	The same config drives both sides, so what the player sees is what the server
	checks. Flow for a typical weapon:

	  1. Client casts locally for instant feedback and reports the hit:
			local Projectile = Core:Get("Projectile")
			local cast = Projectile.Cast({
				origin = muzzle.Position,
				direction = aimDirection, -- unit
				speed = 120,
				gravity = Vector3.new(0, -50, 0), -- or Vector3.zero for straight shots
				maxDistance = 300,
				lifetime = 3,
				filter = { character },
				onStep = function(position, velocity, dt) bullet.Position = position end,
				onHit = function(result) reportHitToServer(result) end,
			})

	  2. Server validates the report instead of trusting it:
			local verdict = Projectile.Validate({
				origin = muzzleOnServer, direction = dir, speed = 120,
				gravity = Vector3.new(0, -50, 0), maxDistance = 300,
				filter = { shooter.Character },
			}, reportedHitPosition, reportedHitInstance)
			if verdict.valid then applyDamage(...) end

	Validate re-simulates the trajectory server-side and accepts the hit only if
	the path passes within `tolerance` studs of the reported position (latency and
	moving targets need some slack — default 8 studs; tighten for slow projectiles).
]]

local RunService = game:GetService("RunService")

local Projectile = {}

export type CastConfig = {
	origin: Vector3,
	direction: Vector3, -- unit vector
	speed: number,
	gravity: Vector3?, -- default zero (straight line)
	maxDistance: number?, -- default 500
	lifetime: number?, -- seconds, default 5
	filter: { Instance }?, -- ignored instances (shooter character etc.)
	filterType: Enum.RaycastFilterType?, -- default Exclude
	onStep: ((position: Vector3, velocity: Vector3, dt: number) -> ())?,
	onHit: ((result: RaycastResult) -> ())?,
	onExpire: (() -> ())?,
}

export type CastHandle = {
	Cancel: () -> (),
}

local function buildParams(config: CastConfig): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = config.filterType or Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = config.filter or {}
	params.IgnoreWater = true
	return params
end

--- Steps a projectile along its (optionally gravity-curved) path with raycasts
--- between steps. Runs until hit, max distance, or lifetime. Returns a handle
--- with Cancel().
function Projectile.Cast(config: CastConfig): CastHandle
	assert(typeof(config.origin) == "Vector3", "Projectile.Cast: origin required")
	assert(typeof(config.direction) == "Vector3", "Projectile.Cast: direction required")
	assert(type(config.speed) == "number" and config.speed > 0, "Projectile.Cast: speed must be > 0")

	local gravity = config.gravity or Vector3.zero
	local maxDistance = config.maxDistance or 500
	local lifetime = config.lifetime or 5
	local params = buildParams(config)

	local position = config.origin
	local velocity = config.direction.Unit * config.speed
	local travelled = 0
	local elapsed = 0
	local cancelled = false

	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt: number)
		if cancelled then
			connection:Disconnect()
			return
		end

		elapsed += dt
		velocity += gravity * dt
		local step = velocity * dt
		local result = workspace:Raycast(position, step, params)

		if result then
			connection:Disconnect()
			if config.onStep then
				config.onStep(result.Position, velocity, dt)
			end
			if config.onHit then
				config.onHit(result)
			end
			return
		end

		position += step
		travelled += step.Magnitude

		if config.onStep then
			config.onStep(position, velocity, dt)
		end

		if travelled >= maxDistance or elapsed >= lifetime then
			connection:Disconnect()
			if config.onExpire then
				config.onExpire()
			end
		end
	end)

	return {
		Cancel = function()
			cancelled = true
			connection:Disconnect()
		end,
	}
end

export type ValidateConfig = {
	origin: Vector3,
	direction: Vector3,
	speed: number,
	gravity: Vector3?,
	maxDistance: number?,
	filter: { Instance }?,
	filterType: Enum.RaycastFilterType?,
	tolerance: number?, -- studs of slack around the reported hit (default 8)
}

export type Verdict = {
	valid: boolean,
	reason: string?,
	-- closest simulated point to the reported hit (debugging / hit correction)
	closestPoint: Vector3?,
}

local VALIDATE_STEP = 1 / 30 -- fixed step keeps validation deterministic

--- Re-simulates the trajectory server-side and checks the reported hit lies on it.
--- This rejects shots through walls, beyond range, or nowhere near the real path.
function Projectile.Validate(config: ValidateConfig, reportedPosition: Vector3, reportedInstance: Instance?): Verdict
	local tolerance = config.tolerance or 8
	local gravity = config.gravity or Vector3.zero
	local maxDistance = config.maxDistance or 500
	local params = buildParams(config :: any)

	-- quick rejects before simulating
	local originDistance = (reportedPosition - config.origin).Magnitude
	if originDistance > maxDistance + tolerance then
		return { valid = false, reason = "beyond max distance", closestPoint = nil }
	end

	local position = config.origin
	local velocity = config.direction.Unit * config.speed
	local travelled = 0
	local closestPoint = position
	local closestDistance = (reportedPosition - position).Magnitude

	while travelled < maxDistance + tolerance do
		velocity += gravity * VALIDATE_STEP
		local step = velocity * VALIDATE_STEP
		local result = workspace:Raycast(position, step, params)

		if result then
			-- the real trajectory ends here; the reported hit must be near this point
			local hitDistance = (reportedPosition - result.Position).Magnitude
			if hitDistance <= tolerance then
				return { valid = true, reason = nil, closestPoint = result.Position }
			end
			return { valid = false, reason = "trajectory blocked before reported hit", closestPoint = result.Position }
		end

		position += step
		travelled += step.Magnitude

		local distance = (reportedPosition - position).Magnitude
		if distance < closestDistance then
			closestDistance = distance
			closestPoint = position
		end
		-- reported point reached without obstruction
		if distance <= tolerance then
			-- if an instance was reported, sanity-check it's actually near the hit
			if reportedInstance and reportedInstance:IsA("BasePart") then
				local partDistance = ((reportedInstance :: BasePart).Position - reportedPosition).Magnitude
				local partSize = (reportedInstance :: BasePart).Size.Magnitude
				if partDistance > partSize + tolerance then
					return { valid = false, reason = "reported instance not at hit position", closestPoint = position }
				end
			end
			return { valid = true, reason = nil, closestPoint = position }
		end
	end

	return { valid = false, reason = "reported hit not on trajectory", closestPoint = closestPoint }
end

return Projectile
