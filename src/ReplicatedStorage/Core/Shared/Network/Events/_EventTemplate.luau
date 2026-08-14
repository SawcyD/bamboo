--!strict
-- Template for a BridgeNet2 Relay channel namespace.
-- Copy this file, rename it (no leading _), and define your channels.

-- selene: allow(unused_variable)
local Channel = require(script.Parent.Parent:WaitForChild("Channel"))

local NS = "Example" -- change to your namespace name
-- selene: allow(unused_variable)
local function b(key: string): string
	return NS .. "_" .. key
end

return {
	-- ExampleEvent = Channel({
	--     bridge = b("ExampleEvent"),
	--     kind = "fire",       -- "fire" (default) or "invoke"
	--     direction = "c2s",   -- c2s | s2c | s2all | s2some (or full names)
	--     value = {            -- per-field validators; omit for empty-payload channels
	--         someField = function(v) return type(v) == "string" end,
	--     },
	-- }),
}
