--!strict
-- Lightweight PathfindingService wrapper for Brain-controlled actors.

local PathfindingService = game:GetService("PathfindingService")
local Signal = require(script.Parent:WaitForChild("Signal"))

local Navigation = {}
Navigation.__index = Navigation

export type Config = {
	AgentRadius: number?,
	AgentHeight: number?,
	AgentCanJump: boolean?,
	AgentCanClimb: boolean?,
	WaypointSpacing: number?,
	AcceptanceRadius: number?,
	RepathInterval: number?,
}

export type NavigatorType = {
	Blocked: any,
	Completed: any,
	Failed: any,
	SetDestination: (self: NavigatorType, destination: Vector3) -> boolean,
	Update: (self: NavigatorType, deltaTime: number) -> boolean,
	Stop: (self: NavigatorType) -> (),
	IsMoving: (self: NavigatorType) -> boolean,
	GetDestination: (self: NavigatorType) -> Vector3?,
	GetWaypoints: (self: NavigatorType) -> { PathWaypoint },
	Destroy: (self: NavigatorType) -> (),
}

type NavigatorImpl = NavigatorType & {
	_actor: Model,
	_humanoid: Humanoid,
	_root: BasePart,
	_config: Config,
	_path: Path?,
	_waypoints: { PathWaypoint },
	_waypointIndex: number,
	_destination: Vector3?,
	_lastRepath: number,
	_needsRepath: boolean,
	_moving: boolean,
	_blockedConnection: RBXScriptConnection?,
	_destroyed: boolean,
}

local function _getParts(actor: Model): (Humanoid, BasePart)
	local humanoid = actor:FindFirstChildOfClass("Humanoid")
	local root = actor.PrimaryPart or actor:FindFirstChild("HumanoidRootPart")
	assert(humanoid, "Navigation: actor requires a Humanoid")
	assert(root and root:IsA("BasePart"), "Navigation: actor requires a root BasePart")
	return humanoid, root :: BasePart
end

local function _now(): number
	return workspace:GetServerTimeNow()
end

function Navigation.new(actor: Model, config: Config?): NavigatorType
	local humanoid, root = _getParts(actor)
	local options = config or {}
	return setmetatable({
		_actor = actor,
		_humanoid = humanoid,
		_root = root,
		_config = options,
		_path = nil,
		_waypoints = {},
		_waypointIndex = 0,
		_destination = nil,
		_lastRepath = -math.huge,
		_needsRepath = false,
		_moving = false,
		_blockedConnection = nil,
		_destroyed = false,
		Blocked = Signal.new(),
		Completed = Signal.new(),
		Failed = Signal.new(),
	}, Navigation) :: NavigatorImpl
end

function Navigation:_compute(destination: Vector3): boolean
	local path = PathfindingService:CreatePath({
		AgentRadius = self._config.AgentRadius or 2,
		AgentHeight = self._config.AgentHeight or 5,
		AgentCanJump = self._config.AgentCanJump ~= false,
		AgentCanClimb = self._config.AgentCanClimb == true,
		WaypointSpacing = self._config.WaypointSpacing or 4,
	})
	local ok, err = pcall(function()
		path:ComputeAsync(self._root.Position, destination)
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		self.Failed:Fire(destination, err or path.Status.Name)
		return false
	end
	if self._blockedConnection then
		self._blockedConnection:Disconnect()
	end
	self._blockedConnection = path.Blocked:Connect(function(blockedIndex)
		if blockedIndex >= self._waypointIndex then
			self._needsRepath = true
			self.Blocked:Fire(blockedIndex)
		end
	end)
	self._path = path
	self._waypoints = path:GetWaypoints()
	self._waypointIndex = if #self._waypoints > 1 then 2 else 1
	self._lastRepath = _now()
	self._needsRepath = false
	return #self._waypoints > 0
end

function Navigation:SetDestination(destination: Vector3): boolean
	assert(not self._destroyed, "Navigation: navigator is destroyed")
	self._destination = destination
	self._moving = self:_compute(destination)
	if self._moving then
		self:_moveToWaypoint()
	end
	return self._moving
end

function Navigation:_moveToWaypoint()
	local waypoint = self._waypoints[self._waypointIndex]
	if not waypoint then
		return
	end
	if waypoint.Action == Enum.PathWaypointAction.Jump then
		self._humanoid.Jump = true
	end
	self._humanoid:MoveTo(waypoint.Position)
end

function Navigation:Update(deltaTime: number): boolean
	if self._destroyed or not self._moving then
		return false
	end
	assert(deltaTime >= 0, "Navigation: deltaTime cannot be negative")
	local destination = self._destination
	if not destination then
		return false
	end
	if self._needsRepath and _now() - self._lastRepath >= (self._config.RepathInterval or 0.5) then
		if not self:_compute(destination) then
			self._moving = false
			return false
		end
	end
	local waypoint = self._waypoints[self._waypointIndex]
	if not waypoint then
		self._moving = false
		self.Completed:Fire(destination)
		return true
	end
	if (self._root.Position - waypoint.Position).Magnitude <= (self._config.AcceptanceRadius or 2) then
		self._waypointIndex += 1
		self:_moveToWaypoint()
		if self._waypointIndex > #self._waypoints then
			self._moving = false
			self.Completed:Fire(destination)
			return true
		end
	end
	return false
end

function Navigation:Stop()
	self._moving = false
	self._destination = nil
	self._waypoints = {}
	self._waypointIndex = 0
	self._humanoid:Move(Vector3.zero)
end

function Navigation:IsMoving(): boolean
	return self._moving
end

function Navigation:GetDestination(): Vector3?
	return self._destination
end

function Navigation:GetWaypoints(): { PathWaypoint }
	return table.clone(self._waypoints)
end

function Navigation:Destroy()
	if self._destroyed then
		return
	end
	self:Stop()
	self._destroyed = true
	if self._blockedConnection then
		self._blockedConnection:Disconnect()
	end
	self.Blocked:Destroy()
	self.Completed:Destroy()
	self.Failed:Destroy()
end

return Navigation
