--!strict
-- Activates the tag-bound AnimatedNPC component on the client.

local AnimatedNPCController = {}

function AnimatedNPCController:Start()
	require(script.Parent.Parent.Modules.AnimatedNPC)
end

return AnimatedNPCController
