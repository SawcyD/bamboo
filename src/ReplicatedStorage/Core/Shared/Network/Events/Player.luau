--!strict

local Channel = require(script.Parent.Parent:WaitForChild("Channel"))

local NS = "Player"
local function b(key: string): string
	return NS .. "_" .. key
end

return {
	-- Server → all clients: a plot changed owner
	PlotOwnerChanged = Channel({
		bridge = b("PlotOwnerChanged"),
		kind = "fire",
		direction = "s2all",
		value = {
			plotId = function(v)
				return type(v) == "string"
			end,
			ownerName = function(v)
				return type(v) == "string"
			end,
		},
	}),

	-- Server → owner only: their eggs-hatched count updated
	EggsHatchedUpdated = Channel({
		bridge = b("EggsHatchedUpdated"),
		kind = "fire",
		direction = "s2c",
		value = {
			count = function(v)
				return type(v) == "number" and v >= 0 and v == math.floor(v)
			end,
		},
	}),

	-- Client → server: collect ATM pending balance into wallet
	-- No fields required; nil or empty table is a valid payload.
	CollectAtm = Channel({
		bridge = b("CollectAtm"),
		kind = "fire",
		direction = "c2s",
	}),

	-- Server → all clients: system line for in-experience chat (client calls TextChannel:DisplaySystemMessage).
	ServerChatBroadcast = Channel({
		bridge = b("ServerChatBroadcast"),
		kind = "fire",
		direction = "s2all",
		value = {
			message = function(v)
				return type(v) == "string" and #v > 0 and #v <= 500
			end,
		},
	}),
}
