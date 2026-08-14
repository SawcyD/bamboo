--!strict
--[[
	Core.Index: typed, autocomplete-friendly access to Core modules.

		local Index = require(ReplicatedStorage.Core.Index)
		Index.RNG.Roll(drops)      -- full type info + autocomplete
		Index.FormatUtil.Compact(12345)

	Modules still load lazily (first access requires them); the type annotations
	below are resolved statically by luau-lsp, so the editor knows every API
	without anything being required at runtime.

	When you add a module you use often, add one line to the type and one to the
	resolver map. Core:Get("Name") keeps working for dynamic/untyped access.
]]

local Modules = script.Parent:WaitForChild("Modules")
local Utils = script.Parent:WaitForChild("Utils")
local Shared = script.Parent:WaitForChild("Shared")

type IndexType = {
	-- Modules
	Bezier: typeof(require(script.Parent.Modules.Bezier)),
	Component: typeof(require(script.Parent.Modules.Component)),
	Janitor: typeof(require(script.Parent.Modules.Janitor)),
	Log: typeof(require(script.Parent.Modules.Log)),
	ObjectPool: typeof(require(script.Parent.Modules.ObjectPool)),
	OptimizedZone: typeof(require(script.Parent.Modules.OptimizedZone)),
	Projectile: typeof(require(script.Parent.Modules.Projectile)),
	RNG: typeof(require(script.Parent.Modules.RNG)),
	Replica: typeof(require(script.Parent.Modules.Replica)),
	Scheduler: typeof(require(script.Parent.Modules.Scheduler)),
	Signal: typeof(require(script.Parent.Modules.Signal)),
	Spring: typeof(require(script.Parent.Modules.Spring)),
	SpringUI: typeof(require(script.Parent.Modules.SpringUI)),
	Brain: typeof(require(script.Parent.Modules.Brain.init)),
	Motion: typeof(require(script.Parent.Modules.Motion.init)),
	Enums: typeof(require(script.Parent.Shared.Enums.init)),
	Animations: typeof(require(script.Parent.Shared.Animations.init)),
	ActorRegistry: typeof(require(script.Parent.Modules.ActorRegistry)),
	AnimationRegistry: typeof(require(script.Parent.Modules.AnimationRegistry)),
	Combat: typeof(require(script.Parent.Modules.Combat)),
	DebugDraw: typeof(require(script.Parent.Modules.DebugDraw)),
	Hitbox: typeof(require(script.Parent.Modules.Hitbox)),
	Interaction: typeof(require(script.Parent.Modules.Interaction)),
	Navigation: typeof(require(script.Parent.Modules.Navigation)),
	Perception: typeof(require(script.Parent.Modules.Perception)),
	Profiler: typeof(require(script.Parent.Modules.Profiler)),
	SpawnService: typeof(require(script.Parent.Modules.SpawnService)),
	Targeting: typeof(require(script.Parent.Modules.Targeting)),
	Validation: typeof(require(script.Parent.Modules.Validation)),

	-- Utils
	Cooldown: typeof(require(script.Parent.Utils.Cooldown)),
	DebounceUtil: typeof(require(script.Parent.Utils.DebounceUtil)),
	FormatUtil: typeof(require(script.Parent.Utils.FormatUtil)),
	MathUtil: typeof(require(script.Parent.Utils.MathUtil)),
	StringUtil: typeof(require(script.Parent.Utils.StringUtil)),
	TableUtil: typeof(require(script.Parent.Utils.TableUtil)),
}

local sources: { [string]: Instance } = {
	Bezier = Modules,
	Component = Modules,
	Janitor = Modules,
	Log = Modules,
	ObjectPool = Modules,
	OptimizedZone = Modules,
	Projectile = Modules,
	RNG = Modules,
	Replica = Modules,
	Scheduler = Modules,
	Signal = Modules,
	Spring = Modules,
	SpringUI = Modules,
	Brain = Modules,
	Motion = Modules,
	Enums = Shared,
	Animations = Shared,
	ActorRegistry = Modules,
	AnimationRegistry = Modules,
	Combat = Modules,
	DebugDraw = Modules,
	Hitbox = Modules,
	Interaction = Modules,
	Navigation = Modules,
	Perception = Modules,
	Profiler = Modules,
	SpawnService = Modules,
	Targeting = Modules,
	Validation = Modules,

	Cooldown = Utils,
	DebounceUtil = Utils,
	FormatUtil = Utils,
	MathUtil = Utils,
	StringUtil = Utils,
	TableUtil = Utils,
}

local function resolveSource(folder: Instance, name: string): ModuleScript
	local source = folder:WaitForChild(name)
	if source:IsA("Folder") then
		source = source:WaitForChild("init")
	end
	assert(source:IsA("ModuleScript"), "Core.Index: not a loadable module: " .. name)
	return source
end

local Index = setmetatable({}, {
	__index = function(self, name: string): any
		local folder = sources[name]
		assert(folder, "Core.Index: unknown module: " .. tostring(name))
		local module = resolveSource(folder, name)
		local result = require(module) :: any
		rawset(self, name, result) -- cache so __index only fires once per module
		return result
	end,
})

return (Index :: any) :: IndexType
