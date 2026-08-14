--!strict
-- Template for bounded instance spawning and lifecycle management.

local Scheduler = require(script.Parent:WaitForChild("Scheduler"))
local Signal = require(script.Parent:WaitForChild("Signal"))

local SpawnService = {}
SpawnService.__index = SpawnService

export type Config = {
	Parent: Instance?,
	MaxActive: number?,
	OnSpawn: ((instance: Instance, data: any?) -> ())?,
	OnDespawn: ((instance: Instance) -> ())?,
}

export type SpawnServiceType = {
	Spawned: any,
	Despawned: any,
	Spawn: (self: SpawnServiceType, pivot: CFrame?, parent: Instance?, data: any?) -> Instance?,
	Despawn: (self: SpawnServiceType, instance: Instance) -> boolean,
	ScheduleRespawn: (self: SpawnServiceType, delayTime: number, pivot: CFrame?, parent: Instance?, data: any?) -> any,
	GetActive: (self: SpawnServiceType) -> { Instance },
	Destroy: (self: SpawnServiceType) -> (),
}

type SpawnServiceImpl = SpawnServiceType & {
	_template: Instance,
	_config: Config,
	_active: { [Instance]: boolean },
	_connections: { [Instance]: RBXScriptConnection },
	_destroyed: boolean,
}

local function _setPivot(instance: Instance, pivot: CFrame?)
	if not pivot then
		return
	end
	if instance:IsA("Model") then
		instance:PivotTo(pivot)
	elseif instance:IsA("BasePart") then
		instance.CFrame = pivot
	end
end

function SpawnService.new(template: Instance, config: Config?): SpawnServiceType
	assert(template.Archivable, "SpawnService: template must be Archivable")
	return setmetatable({
		_template = template,
		_config = config or {},
		_active = {},
		_connections = {},
		_destroyed = false,
		Spawned = Signal.new(),
		Despawned = Signal.new(),
	}, SpawnService) :: SpawnServiceImpl
end

function SpawnService:Spawn(pivot: CFrame?, parent: Instance?, data: any?): Instance?
	if self._destroyed then
		return nil
	end
	local maxActive = self._config.MaxActive
	if maxActive and #self:GetActive() >= maxActive then
		return nil
	end
	local instance = self._template:Clone()
	instance.Parent = parent or self._config.Parent or self._template.Parent
	_setPivot(instance, pivot)
	self._active[instance] = true
	self._connections[instance] = instance.AncestryChanged:Connect(function(_, newParent)
		if newParent == nil then
			self:_remove(instance, false)
		end
	end)
	if self._config.OnSpawn then
		self._config.OnSpawn(instance, data)
	end
	self.Spawned:Fire(instance, data)
	return instance
end

function SpawnService:_remove(instance: Instance, destroy: boolean): boolean
	if not self._active[instance] then
		return false
	end
	local connection = self._connections[instance]
	if connection then
		connection:Disconnect()
	end
	self._connections[instance] = nil
	self._active[instance] = nil
	if self._config.OnDespawn then
		self._config.OnDespawn(instance)
	end
	self.Despawned:Fire(instance)
	if destroy and instance.Parent then
		instance:Destroy()
	end
	return true
end

function SpawnService:Despawn(instance: Instance): boolean
	return self:_remove(instance, true)
end

function SpawnService:ScheduleRespawn(delayTime: number, pivot: CFrame?, parent: Instance?, data: any?): any
	return Scheduler.Delay(delayTime, function()
		self:Spawn(pivot, parent, data)
	end)
end

function SpawnService:GetActive(): { Instance }
	local result = {}
	for instance in self._active do
		table.insert(result, instance)
	end
	return result
end

function SpawnService:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	for _, instance in self:GetActive() do
		self:_remove(instance, true)
	end
	self.Spawned:Destroy()
	self.Despawned:Destroy()
	table.clear(self._active)
	table.clear(self._connections)
end

return SpawnService
