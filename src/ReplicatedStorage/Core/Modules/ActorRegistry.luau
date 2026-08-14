--!strict
-- Registry for runtime actors such as players, NPCs, pets, and enemies.

local HttpService = game:GetService("HttpService")
local Signal = require(script.Parent:WaitForChild("Signal"))

local ActorRegistry = {}
ActorRegistry.__index = ActorRegistry

export type ActorRecord = {
	Id: string,
	Model: Model,
	Type: string?,
	Tags: { [string]: boolean },
	Data: { [string]: any },
}

export type RegistryType = {
	Changed: any,
	Register: (self: RegistryType, actor: Model, data: { [string]: any }?) -> ActorRecord,
	Unregister: (self: RegistryType, actor: Model) -> boolean,
	Get: (self: RegistryType, actor: Model) -> ActorRecord?,
	GetById: (self: RegistryType, id: string) -> ActorRecord?,
	List: (self: RegistryType, filter: ((record: ActorRecord) -> boolean)?) -> { ActorRecord },
	FindWithin: (
		self: RegistryType,
		position: Vector3,
		radius: number,
		filter: ((record: ActorRecord) -> boolean)?
	) -> { ActorRecord },
	FindNearest: (self: RegistryType, position: Vector3, filter: ((record: ActorRecord) -> boolean)?) -> ActorRecord?,
	Destroy: (self: RegistryType) -> (),
}

type RegistryImpl = RegistryType & {
	_records: { [Model]: ActorRecord },
	_byId: { [string]: ActorRecord },
	_connections: { [Model]: RBXScriptConnection },
	_destroyed: boolean,
}

local function _rootPosition(model: Model): Vector3?
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

function ActorRegistry.new(): RegistryType
	return setmetatable({
		_records = {},
		_byId = {},
		_connections = {},
		destroyed = false,
		Changed = Signal.new(),
	}, ActorRegistry) :: RegistryImpl
end

function ActorRegistry:Register(actor: Model, data: { [string]: any }?): ActorRecord
	assert(actor:IsA("Model"), "ActorRegistry:Register expects a Model")
	assert(not self._destroyed, "ActorRegistry: registry is destroyed")
	local existing = self._records[actor]
	if existing then
		return existing
	end

	local options = data or {}
	local id = options.Id or actor:GetAttribute("ActorId") or HttpService:GenerateGUID(false)
	assert(self._byId[id] == nil, "ActorRegistry: duplicate actor id " .. id)
	local record: ActorRecord = {
		Id = id,
		Model = actor,
		Type = options.Type,
		Tags = table.clone(options.Tags or {}),
		Data = options.Data or {},
	}
	self._records[actor] = record
	self._byId[id] = record
	self._connections[actor] = actor.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			self:Unregister(actor)
		end
	end)
	self.Changed:Fire("Registered", record)
	return record
end

function ActorRegistry:Unregister(actor: Model): boolean
	local record = self._records[actor]
	if not record then
		return false
	end
	local connection = self._connections[actor]
	if connection then
		connection:Disconnect()
	end
	self._connections[actor] = nil
	self._records[actor] = nil
	self._byId[record.Id] = nil
	self.Changed:Fire("Unregistered", record)
	return true
end

function ActorRegistry:Get(actor: Model): ActorRecord?
	return self._records[actor]
end

function ActorRegistry:GetById(id: string): ActorRecord?
	return self._byId[id]
end

function ActorRegistry:List(filter: ((record: ActorRecord) -> boolean)?): { ActorRecord }
	local result = {}
	for _, record in self._records do
		if not filter or filter(record) then
			table.insert(result, record)
		end
	end
	return result
end

function ActorRegistry:FindWithin(
	position: Vector3,
	radius: number,
	filter: ((record: ActorRecord) -> boolean)?
): { ActorRecord }
	assert(radius >= 0, "ActorRegistry: radius cannot be negative")
	local result = {}
	local radiusSquared = radius * radius
	for _, record in self._records do
		local actorPosition = _rootPosition(record.Model)
		if actorPosition and (actorPosition - position).Magnitude ^ 2 <= radiusSquared then
			if not filter or filter(record) then
				table.insert(result, record)
			end
		end
	end
	return result
end

function ActorRegistry:FindNearest(position: Vector3, filter: ((record: ActorRecord) -> boolean)?): ActorRecord?
	local nearest: ActorRecord?
	local nearestDistance = math.huge
	for _, record in self._records do
		local actorPosition = _rootPosition(record.Model)
		if actorPosition and (not filter or filter(record)) then
			local distance = (actorPosition - position).Magnitude ^ 2
			if distance < nearestDistance then
				nearest = record
				nearestDistance = distance
			end
		end
	end
	return nearest
end

function ActorRegistry:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	for actor in self._records do
		self:Unregister(actor)
	end
	self.Changed:Destroy()
	table.clear(self._records)
	table.clear(self._byId)
	table.clear(self._connections)
end

return ActorRegistry
