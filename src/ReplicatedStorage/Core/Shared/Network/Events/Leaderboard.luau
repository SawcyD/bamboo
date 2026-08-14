--!strict

local Channel = require(script.Parent.Parent:WaitForChild("Channel"))

local NS = "Leaderboard"
local function b(key: string): string
	return NS .. "_" .. key
end

return {
	--- Client → server: toggle per-player leaderboard replica + which boards to sync.
	PersonalSubscribe = Channel({
		bridge = b("PersonalSubscribe"),
		kind = "fire",
		direction = "c2s",
		value = {
			enabled = function(v)
				return type(v) == "boolean"
			end,
			coins = function(v)
				return type(v) == "boolean"
			end,
			eggs = function(v)
				return type(v) == "boolean"
			end,
			timePlayed = function(v)
				return type(v) == "boolean"
			end,
		},
	}),
}
