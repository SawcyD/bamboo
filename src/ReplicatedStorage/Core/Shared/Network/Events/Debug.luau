--!strict
-- Dev / diagnostics channels (invoke tests, performance profiler telemetry)

local Channel = require(script.Parent.Parent:WaitForChild("Channel"))

local NS = "Debug"
local function b(key: string): string
	return NS .. "_" .. key
end

return {
	-- Client → server: returns { success: boolean, message: string }
	PingInvoke = Channel({
		bridge = b("PingInvoke"),
		kind = "invoke",
		direction = "c2s",
	}),

	-- Client → server: the performance profiler opts in/out of server telemetry
	SetTelemetry = Channel({
		bridge = b("SetTelemetry"),
		kind = "fire",
		direction = "c2s",
		rateLimit = 5,
		value = {
			enabled = function(v)
				return type(v) == "boolean"
			end,
		},
	}),

	-- Server → client: per-source bandwidth rows the client can't measure itself
	-- (replica writes etc.); consumed by the PerformanceDebug profiler.
	ReplicaTelemetry = Channel({
		bridge = b("ReplicaTelemetry"),
		kind = "fire",
		direction = "s2c",
	}),
}
