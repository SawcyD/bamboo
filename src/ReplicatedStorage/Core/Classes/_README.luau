--!strict
--[[
	Core/Classes: plain Luau classes shared by server and client.
	Access with Core:GetClass("Name"). Files starting with "_" are skipped by loaders.

	Conventions (see _ClassTemplate.luau):
	- setmetatable + __index, typed with `export type` (no OOP library).
	- Constructor is `ClassName.new(...)`.
	- Every class that owns connections/instances has a Janitor and a `Destroy()`
	  that cleans it; nothing should need manual disconnect bookkeeping.

	For classes bound to tagged Instances (doors, pickups, zones...), use the
	Component system instead: Core:Get("Component") — see _ComponentTemplate.luau.
	Components get construction/teardown and a Janitor for free.
]]

return {}
