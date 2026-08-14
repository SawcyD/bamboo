--!strict
-- Player preference channels (audio volumes, keybinds...). See SettingsService.

local Channel = require(script.Parent.Parent:WaitForChild("Channel"))

local NS = "Settings"
local function b(key: string): string
	return NS .. "_" .. key
end

return {
	-- Client → server: persist one setting. The server only accepts keys
	-- registered with SettingsService and values passing their validators.
	SetSetting = Channel({
		bridge = b("SetSetting"),
		kind = "fire",
		direction = "c2s",
		rateLimit = 20,
		value = {
			key = function(v)
				return type(v) == "string" and #v > 0 and #v <= 64
			end,
			-- value is validated per-key by SettingsService's registered validators
		},
	}),
}
