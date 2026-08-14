--!strict
-- Template for a tag-bound component. Copy into ServerRuntime/Modules (server logic),
-- ClientRuntime/Modules (client visuals), or Core/Modules (shared), rename, and require
-- it once from a service/controller Start so the binding activates.
-- Then tag instances with "MyTag" in Studio or via CollectionService:AddTag.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Core = require(ReplicatedStorage:WaitForChild("Core"))

local Component = Core:Get("Component")

local MyComponent = Component.new({
	tag = "MyTag",
	-- ancestors = { workspace }, -- default
})

-- Runs synchronously when a tagged instance appears. Set up fields here.
function MyComponent:Construct()
	-- self.Instance: the tagged Instance
	-- self.Janitor:  cleaned automatically when the component stops
end

-- Runs (on its own thread) after Construct. Wire connections here, via the Janitor.
function MyComponent:Start()
	-- self.Janitor:Add(self.Instance.Touched:Connect(function() end))
end

-- Optional: auto-connected to RunService.Heartbeat while the component lives.
-- function MyComponent:HeartbeatUpdate(dt: number) end

-- Optional: runs when the instance is untagged/destroyed/streamed out, before Janitor cleanup.
-- function MyComponent:Stop() end

return MyComponent
