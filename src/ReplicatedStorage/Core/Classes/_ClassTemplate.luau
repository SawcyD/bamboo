--!strict
-- Template for a plain class. Copy, rename, fill in.
-- Access with Core:GetClass("ClassName").

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Core = require(ReplicatedStorage:WaitForChild("Core"))

local Janitor = Core:Get("Janitor")

local ClassName = {}
ClassName.__index = ClassName

export type ClassNameType = typeof(setmetatable(
	{} :: {
		Janitor: any,
		-- public fields here
	},
	ClassName
))

function ClassName.new(): ClassNameType
	local self = setmetatable({
		Janitor = Janitor.new(),
	}, ClassName) :: ClassNameType
	return self
end

-- methods here

function ClassName.Destroy(self: ClassNameType)
	self.Janitor:Cleanup()
end

return ClassName
