--!strict
-- AntiCheat channels. Both are client → server and treated as UNTRUSTED hints:
-- the heartbeat proves the client script is still alive, and reports are tripwire
-- signals the server corroborates — never proof on their own. See AntiCheatService.

local Channel = require(script.Parent.Parent:WaitForChild("Channel"))

local NS = "AntiCheat"
local function b(key: string): string
	return NS .. "_" .. key
end

return {
	-- Liveness ping. The server flags clients that stop sending these (which is
	-- what happens if an exploiter deletes/disables the client controller).
	Heartbeat = Channel({
		bridge = b("Heartbeat"),
		kind = "fire",
		direction = "c2s",
		rateLimit = 5,
	}),

	-- A client-side tripwire fired (e.g. an unapproved ScreenGui appeared). Logged
	-- as a low-severity hint; the client cannot be trusted to report honestly.
	Report = Channel({
		bridge = b("Report"),
		kind = "fire",
		direction = "c2s",
		rateLimit = 10,
		value = {
			reason = function(v)
				return type(v) == "string" and #v > 0 and #v <= 100
			end,
			detail = function(v)
				return v == nil or (type(v) == "string" and #v <= 200)
			end,
		},
	}),
}
