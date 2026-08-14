--!strict
--[[
	ObjectPool: reuse instances/objects instead of churning Instance.new + Destroy.

	Spawning and destroying parts (bullets, hit effects, pooled UI rows, sound
	emitters) every frame is a major source of GC pressure and frame spikes. A pool
	keeps a stack of idle objects and hands them back out.

		local ObjectPool = Core:Get("ObjectPool")

		-- from a template Instance (cloned on demand)
		local bullets = ObjectPool.new(ReplicatedStorage.BulletTemplate, {
			initial = 50,        -- pre-clone this many up front
			max = 500,           -- cap idle objects retained (0 = unlimited)
			parent = workspace,  -- active objects parent here; idle are parented out
			onGet = function(part) part.Transparency = 0 end,
			onReturn = function(part) part.AssemblyLinearVelocity = Vector3.zero end,
		})

		local part = bullets:Get()
		bullets:Return(part)

		-- auto-return after a lifetime (uses the shared Scheduler)
		local fx = effects:GetFor(0.5)

	Works with non-Instance objects too — pass a factory function instead of a
	template and the pool just calls it to create more (Parent management is
	skipped for non-Instances):

		local tables = ObjectPool.new(function() return {} end)
]]

local Scheduler = require(script.Parent:WaitForChild("Scheduler"))

type Config = {
	initial: number?,
	max: number?,
	parent: Instance?,
	onGet: ((any) -> ())?,
	onReturn: ((any) -> ())?,
}

local ObjectPool = {}
ObjectPool.__index = ObjectPool

export type Pool = typeof(setmetatable(
	{} :: {
		_factory: () -> any,
		_idle: { any },
		_active: { [any]: boolean },
		_max: number,
		_parent: Instance?,
		_onGet: ((any) -> ())?,
		_onReturn: ((any) -> ())?,
	},
	ObjectPool
))

function ObjectPool.new(template: Instance | (() -> any), config: Config?): Pool
	local options: Config = config or {}

	local factory: () -> any
	if typeof(template) == "Instance" then
		factory = function()
			return (template :: Instance):Clone()
		end
	else
		factory = template :: () -> any
	end

	local self = setmetatable({
		_factory = factory,
		_idle = {},
		_active = {},
		_max = options.max or 0,
		_parent = options.parent,
		_onGet = options.onGet,
		_onReturn = options.onReturn,
	}, ObjectPool)

	if options.initial and options.initial > 0 then
		self:Prewarm(options.initial)
	end

	return (self :: any) :: Pool
end

-- park an idle Instance out of the world so it doesn't render/collide/tick
local function park(object: any)
	if typeof(object) == "Instance" then
		object.Parent = nil
	end
end

--- Pre-create `count` idle objects so the first bursts don't allocate.
function ObjectPool.Prewarm(self: Pool, count: number)
	for _ = 1, count do
		local object = self._factory()
		park(object)
		table.insert(self._idle, object)
	end
end

--- Take an object from the pool (reused if available, otherwise freshly created).
function ObjectPool.Get(self: Pool): any
	local object = table.remove(self._idle) or self._factory()
	self._active[object] = true

	if typeof(object) == "Instance" and self._parent then
		object.Parent = self._parent
	end
	if self._onGet then
		self._onGet(object)
	end
	return object
end

--- Get an object and automatically Return it after `seconds` (via the Scheduler).
function ObjectPool.GetFor(self: Pool, seconds: number): any
	local object = self:Get()
	Scheduler.Delay(seconds, function()
		-- only return if it's still checked out (caller may have returned early)
		if self._active[object] then
			self:Return(object)
		end
	end)
	return object
end

--- Hand an object back. Reset state in `onReturn`; over the `max` cap it's destroyed.
function ObjectPool.Return(self: Pool, object: any)
	if not self._active[object] then
		return -- not from this pool, or already returned
	end
	self._active[object] = nil

	if self._onReturn then
		self._onReturn(object)
	end

	-- honor the idle cap: destroy the overflow rather than leak memory
	if self._max > 0 and #self._idle >= self._max then
		if typeof(object) == "Instance" then
			object:Destroy()
		end
		return
	end

	park(object)
	table.insert(self._idle, object)
end

function ObjectPool.GetActiveCount(self: Pool): number
	local count = 0
	for _ in self._active do
		count += 1
	end
	return count
end

function ObjectPool.GetIdleCount(self: Pool): number
	return #self._idle
end

--- Destroy idle objects (keeps checked-out ones alive).
function ObjectPool.Clear(self: Pool)
	for _, object in self._idle do
		if typeof(object) == "Instance" then
			object:Destroy()
		end
	end
	table.clear(self._idle)
end

--- Destroy everything, idle and active. The pool is unusable afterwards.
function ObjectPool.Destroy(self: Pool)
	self:Clear()
	for object in self._active do
		if typeof(object) == "Instance" then
			object:Destroy()
		end
	end
	table.clear(self._active)
end

return ObjectPool
