--!strict
--[[
	Component: binds a Luau class to every Instance with a CollectionService tag.

	Tag an instance (in Studio or via CollectionService:AddTag) and the component is
	constructed for it automatically; untag it / destroy it / stream it out and the
	component is stopped and cleaned up. Works on server and client (each side runs
	its own components — tag the same instance and define a server component for
	logic and a client component for visuals).

	Definition (one module per component, e.g. ServerRuntime/Modules/Door.luau):

		local Component = Core:Get("Component")

		local Door = Component.new({
			tag = "Door",
			ancestors = { workspace }, -- optional; defaults to { workspace }
		})

		function Door:Construct()
			-- self.Instance: the tagged Instance
			-- self.Janitor:  cleaned automatically when the component stops
			self.OpenCount = 0
		end

		function Door:Start()
			self.Janitor:Add(self.Instance.ClickDetector.MouseClick:Connect(function()
				self:Toggle()
			end))
		end

		function Door:HeartbeatUpdate(dt) end -- optional, auto-connected when defined

		function Door:Stop() end -- optional, runs before Janitor cleanup

		return Door

	Lookup from other code:

		local door = Door.FromInstance(someModel)
		for _, door in Door.GetAll() do ... end
		Door.Added:Connect(function(component) ... end)
		Door.Removed:Connect(function(component) ... end)

	Components only construct while the instance is under one of `ancestors`, and are
	stopped if it leaves (covers client streaming and server-side reparenting).
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Janitor = require(script.Parent:WaitForChild("Janitor"))

-- minimal signal (avoids a dependency on the Network module)
local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} :: { [(...any) -> ()]: boolean } }, Signal)
end

function Signal:Connect(handler: (...any) -> ()): { Disconnect: () -> () }
	self._handlers[handler] = true
	return {
		Disconnect = function()
			self._handlers[handler] = nil
		end,
	}
end

function Signal:Fire(...)
	for handler in self._handlers do
		task.spawn(handler, ...)
	end
end

export type ComponentConfig = {
	tag: string,
	ancestors: { Instance }?,
}

local Component = {}

function Component.new(config: ComponentConfig)
	assert(
		type(config) == "table" and type(config.tag) == "string" and #config.tag > 0,
		"Component.new: config.tag is required"
	)

	local tag = config.tag
	local allowedAncestors: { Instance } = config.ancestors or { workspace }

	local class = {}
	class.__index = class
	class.Tag = tag
	class.Added = Signal.new()
	class.Removed = Signal.new()

	local instances: { [Instance]: any } = {}
	-- watchers for tagged instances currently outside allowed ancestors
	local pendingWatchers: { [Instance]: RBXScriptConnection } = {}

	local function isInAllowedAncestor(instance: Instance): boolean
		for _, ancestor in allowedAncestors do
			if instance:IsDescendantOf(ancestor) then
				return true
			end
		end
		return false
	end

	local function stopComponent(instance: Instance)
		local component = instances[instance]
		if not component then
			return
		end
		instances[instance] = nil
		if type(class.Stop) == "function" then
			local ok, err = pcall(class.Stop, component)
			if not ok then
				warn(`Component[{tag}]: error in Stop for {instance:GetFullName()}: {err}`)
			end
		end
		component.Janitor:Cleanup()
		class.Removed:Fire(component)
	end

	local function startComponent(instance: Instance)
		if instances[instance] then
			return
		end

		local component = setmetatable({
			Instance = instance,
			Janitor = Janitor.new(),
		}, class)
		instances[instance] = component

		-- stop if the instance leaves allowed ancestors (streaming out, reparent to nil)
		component.Janitor:Add(instance.AncestryChanged:Connect(function()
			if not isInAllowedAncestor(instance) then
				stopComponent(instance)
				-- if it comes back (streaming), tryStart's watcher path re-adds it
				if instance.Parent ~= nil and CollectionService:HasTag(instance, tag) then
					task.defer(function()
						if CollectionService:HasTag(instance, tag) and isInAllowedAncestor(instance) then
							startComponent(instance)
						end
					end)
				end
			end
		end))

		if type(class.Construct) == "function" then
			local ok, err = pcall(class.Construct, component)
			if not ok then
				warn(`Component[{tag}]: error in Construct for {instance:GetFullName()}: {err}`)
				instances[instance] = nil
				component.Janitor:Cleanup()
				return
			end
		end

		if type(class.Start) == "function" then
			task.spawn(function()
				local ok, err = pcall(class.Start, component)
				if not ok then
					warn(`Component[{tag}]: error in Start for {instance:GetFullName()}: {err}`)
				end
			end)
		end

		if type(class.HeartbeatUpdate) == "function" then
			component.Janitor:Add(RunService.Heartbeat:Connect(function(dt: number)
				component:HeartbeatUpdate(dt)
			end))
		end

		class.Added:Fire(component)
	end

	local function tryStart(instance: Instance)
		if instances[instance] or pendingWatchers[instance] then
			return
		end
		if isInAllowedAncestor(instance) then
			startComponent(instance)
			return
		end
		-- tagged but not yet under an allowed ancestor (e.g. cloned from ServerStorage);
		-- watch until it moves into one or loses the tag
		pendingWatchers[instance] = instance.AncestryChanged:Connect(function()
			if not CollectionService:HasTag(instance, tag) or instance.Parent == nil then
				return
			end
			if isInAllowedAncestor(instance) then
				local watcher = pendingWatchers[instance]
				if watcher then
					watcher:Disconnect()
					pendingWatchers[instance] = nil
				end
				startComponent(instance)
			end
		end)
	end

	local function onRemoved(instance: Instance)
		local watcher = pendingWatchers[instance]
		if watcher then
			watcher:Disconnect()
			pendingWatchers[instance] = nil
		end
		stopComponent(instance)
	end

	CollectionService:GetInstanceAddedSignal(tag):Connect(tryStart)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(onRemoved)
	for _, instance in CollectionService:GetTagged(tag) do
		task.spawn(tryStart, instance)
	end

	--- The component bound to `instance`, or nil if none.
	function class.FromInstance(instance: Instance): any?
		return instances[instance]
	end

	--- Array of all live components for this tag.
	function class.GetAll(): { any }
		local all = {}
		for _, component in instances do
			table.insert(all, component)
		end
		return all
	end

	--- Yields until `instance` has a component (with optional timeout in seconds).
	function class.WaitForInstance(instance: Instance, timeout: number?): any?
		local deadline = os.clock() + (timeout or 10)
		while os.clock() < deadline do
			local component = instances[instance]
			if component then
				return component
			end
			task.wait()
		end
		return nil
	end

	return class
end

return Component
