--!strict
--[[
	SettingsService: validated, persisted player preferences.

	The audio volume groups (Volume_Master, Volume_SFX, Volume_Music, Volume_UI,
	Volume_Environment, Volume_Voice, Volume_Ambient) are registered by default —
	SettingsController applies them to the Audio system on the client.

	Register game-specific settings before players join (e.g. from another service):

		local SettingsService = Framework:GetService("SettingsService")
		SettingsService.RegisterSetting("HideOtherPlayers", {
			default = false,
			validate = function(v) return type(v) == "boolean" end,
		})

	Clients write via Relay.Settings.SetSetting (SettingsController does this);
	unregistered keys and invalid values are rejected server-side. Values persist
	in profile.Data.Settings and replicate back through the player replica.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Relay = Core:GetShared("Network")

local SettingsService = {}
local Framework: any

type SettingDef = {
	default: any,
	validate: (value: any) -> boolean,
}

local _settings: { [string]: SettingDef } = {}

local function volumeValidator(v: any): boolean
	return type(v) == "number" and v >= 0 and v <= 1
end

-- default audio settings, one per SoundLibrary group
for _, group in { "Master", "SFX", "Music", "UI", "Environment", "Voice", "Ambient" } do
	_settings["Volume_" .. group] = { default = 1, validate = volumeValidator }
end

function SettingsService.RegisterSetting(key: string, def: SettingDef)
	assert(type(key) == "string" and #key > 0, "SettingsService.RegisterSetting: key required")
	assert(
		type(def) == "table" and type(def.validate) == "function",
		"SettingsService.RegisterSetting: validate required"
	)
	_settings[key] = def
end

--- Current value for `player`, falling back to the registered default.
function SettingsService.GetSetting(player: Player, key: string): any
	local def = _settings[key]
	local DataService = Framework:GetService("DataService")
	local value = DataService.Get(player, { "Settings", key })
	if value ~= nil then
		return value
	end
	return def and def.default or nil
end

--- Server-side write (same validation as client writes).
function SettingsService.SetSetting(player: Player, key: string, value: any): boolean
	local def = _settings[key]
	if not def then
		warn("SettingsService: unregistered setting key:", key)
		return false
	end
	if not def.validate(value) then
		warn("SettingsService: invalid value for", key)
		return false
	end
	local DataService = Framework:GetService("DataService")
	return DataService.Set(player, { "Settings", key }, value)
end

function SettingsService:Start(fw: any)
	Framework = fw

	local DataService = Framework:GetService("DataService")

	-- backfill defaults for registered settings on profile load
	DataService.RegisterDataNormalizer(function(data: any)
		if type(data.Settings) ~= "table" then
			data.Settings = {}
		end
		for key, def in _settings do
			-- backfill missing values and heal corrupted ones
			if data.Settings[key] == nil or not def.validate(data.Settings[key]) then
				data.Settings[key] = def.default
			end
		end
	end)

	Relay.Settings.SetSetting.listen(function(payload: any, player: Player)
		SettingsService.SetSetting(player, payload.key, payload.value)
	end)
end

return SettingsService
