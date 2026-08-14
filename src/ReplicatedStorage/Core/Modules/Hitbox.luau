--!strict
-- Reusable spatial hitbox with overlap queries and per-activation deduplication.

local Scheduler = require(script.Parent:WaitForChild("Scheduler"))
local Signal = require(script.Parent:WaitForChild("Signal"))

local Hitbox = {}
Hitbox.__index = Hitbox

export type Config = {
	Size: Vector3,
	Offset: CFrame?,
	GetCFrame: (() -> CFrame)?,
	Filter: ((target: Model) -> boolean)?,
	FilterInstances: { Instance }?,
	MaxHits: number?,
}

export type HitboxType = {
	Hit: any,
	Start: (self: HitboxType, frequency: number?) -> (),
	Stop: (self: HitboxType) -> (),
	Reset: (self: HitboxType) -> (),
	Query: (self: HitboxType) -> { Model },
	IsActive: (self: HitboxType) -> boolean,
	Destroy: (self: HitboxType) -> (),
}

type HitboxImpl = HitboxType & {
	_owner: Instance?,
	_ownerModel: Model?,
	_config: Config,
	_overlapParams: OverlapParams,
	_hitTargets: { [Model]: boolean },
	_handle: any,
	_active: boolean,
	_destroyed: boolean,
}

local function _getTarget(part: BasePart): Model?
	local model = part:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then
		return model
	end
	return nil
end

local function _getCFrame(self: HitboxImpl): CFrame?
	if self._config.GetCFrame then
		return self._config.GetCFrame()
	end
	local owner = self._owner
	if not owner then
		return nil
	end
	local base = if owner:IsA("Model") then owner:GetPivot() else if owner:IsA("BasePart") then owner.CFrame else nil
	return if base then base * (self._config.Offset or CFrame.identity) else nil
end

function Hitbox.new(owner: Instance?, config: Config): HitboxType
	assert(config and config.Size, "Hitbox: Size is required")
	local ownerModel = if owner and owner:IsA("Model") then owner else nil
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filterInstances = table.clone(config.FilterInstances or {})
	if owner then
		table.insert(filterInstances, owner)
	end
	params.FilterDescendantsInstances = filterInstances
	return setmetatable({
		_owner = owner,
		_ownerModel = ownerModel,
		_config = config,
		_overlapParams = params,
		_hitTargets = {},
		_handle = nil,
		_active = false,
		_destroyed = false,
		Hit = Signal.new(),
	}, Hitbox) :: HitboxImpl
end

function Hitbox:Start(frequency: number?)
	if self._destroyed then
		return
	end
	self:Stop()
	self:Reset()
	self._active = true
	self._handle = Scheduler.Every(frequency or 30, function()
		if self._active then
			self:Query()
		end
	end)
end

function Hitbox:Stop()
	self._active = false
	if self._handle then
		self._handle:Disconnect()
		self._handle = nil
	end
end

function Hitbox:Reset()
	table.clear(self._hitTargets)
end

function Hitbox:Query(): { Model }
	local center = _getCFrame(self)
	if not center or self._destroyed then
		return {}
	end
	local parts = workspace:GetPartBoundsInBox(center, self._config.Size, self._overlapParams)
	local result = {}
	local seen = {}
	for _, part in parts do
		local target = _getTarget(part)
		if target and not seen[target] and not self._hitTargets[target] and target ~= self._ownerModel then
			seen[target] = true
			if not self._config.Filter or self._config.Filter(target) then
				table.insert(result, target)
				self._hitTargets[target] = true
				self.Hit:Fire(target)
				if self._config.MaxHits and #result >= self._config.MaxHits then
					break
				end
			end
		end
	end
	return result
end

function Hitbox:IsActive(): boolean
	return self._active
end

function Hitbox:Destroy()
	if self._destroyed then
		return
	end
	self:Stop()
	self._destroyed = true
	self.Hit:Destroy()
	table.clear(self._hitTargets)
end

return Hitbox
