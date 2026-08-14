--!strict
-- Vision, line-of-sight, and short-term target memory for actors.

local Signal = require(script.Parent:WaitForChild("Signal"))

local Perception = {}
Perception.__index = Perception

export type Config = {
	VisionRadius: number?,
	FieldOfView: number?,
	HearingRadius: number?,
	MemoryDuration: number?,
	CanDetect: ((observer: Model, target: Model) -> boolean)?,
}

export type PerceptionType = {
	Detected: any,
	Lost: any,
	CanSee: (self: PerceptionType, target: Model) -> boolean,
	Scan: (self: PerceptionType, candidates: { Model }) -> { Model },
	Remember: (self: PerceptionType, target: Model, position: Vector3?, duration: number?) -> (),
	Forget: (self: PerceptionType, target: Model) -> (),
	GetLastKnownPosition: (self: PerceptionType, target: Model) -> Vector3?,
	ClearMemory: (self: PerceptionType) -> (),
	Destroy: (self: PerceptionType) -> (),
}

type PerceptionImpl = PerceptionType & {
	_observer: Model,
	_root: BasePart,
	_config: Config,
	_visible: { [Model]: boolean },
	_memory: { [Model]: { Position: Vector3, ExpiresAt: number } },
	_destroyed: boolean,
}

local function _root(model: Model): BasePart?
	local part = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	return if part and part:IsA("BasePart") then part else nil
end

function Perception.new(observer: Model, config: Config?): PerceptionType
	local root = _root(observer)
	assert(root, "Perception: observer requires a root BasePart")
	return setmetatable({
		_observer = observer,
		_root = root :: BasePart,
		_config = config or {},
		_visible = {},
		_memory = {},
		_destroyed = false,
		Detected = Signal.new(),
		Lost = Signal.new(),
	}, Perception) :: PerceptionImpl
end

function Perception:CanSee(target: Model): boolean
	if self._destroyed or target == self._observer then
		return false
	end
	if self._config.CanDetect and not self._config.CanDetect(self._observer, target) then
		return false
	end
	local targetRoot = _root(target)
	if not targetRoot then
		return false
	end
	local offset = targetRoot.Position - self._root.Position
	local distance = offset.Magnitude
	if distance > (self._config.VisionRadius or 80) then
		return false
	end
	local fieldOfView = self._config.FieldOfView or 120
	if fieldOfView < 360 then
		local direction = offset.Unit
		local minimumDot = math.cos(math.rad(fieldOfView * 0.5))
		if self._root.CFrame.LookVector:Dot(direction) < minimumDot then
			return false
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { self._observer }
	local result = workspace:Raycast(self._root.Position, offset, params)
	return result == nil or result.Instance:IsDescendantOf(target)
end

function Perception:Scan(candidates: { Model }): { Model }
	local seen = {}
	local result = {}
	for _, candidate in candidates do
		if self:CanSee(candidate) then
			seen[candidate] = true
			table.insert(result, candidate)
			if not self._visible[candidate] then
				self.Detected:Fire(candidate)
			end
		end
	end
	for target in self._visible do
		if not seen[target] then
			self.Lost:Fire(target)
		end
	end
	self._visible = seen
	return result
end

function Perception:Remember(target: Model, position: Vector3?, duration: number?)
	local targetRoot = _root(target)
	local rememberedPosition = position or (targetRoot and targetRoot.Position)
	if not rememberedPosition then
		return
	end
	self._memory[target] = {
		Position = rememberedPosition,
		ExpiresAt = workspace:GetServerTimeNow() + (duration or self._config.MemoryDuration or 5),
	}
end

function Perception:Forget(target: Model)
	self._memory[target] = nil
	self._visible[target] = nil
end

function Perception:GetLastKnownPosition(target: Model): Vector3?
	local memory = self._memory[target]
	if not memory then
		return nil
	end
	if workspace:GetServerTimeNow() >= memory.ExpiresAt then
		self._memory[target] = nil
		return nil
	end
	return memory.Position
end

function Perception:ClearMemory()
	table.clear(self._memory)
	table.clear(self._visible)
end

function Perception:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	table.clear(self._memory)
	table.clear(self._visible)
	self.Detected:Destroy()
	self.Lost:Destroy()
end

return Perception
