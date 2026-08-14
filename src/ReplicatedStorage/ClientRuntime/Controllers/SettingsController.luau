--!strict
--[[
	SettingsController: client side of player preferences.

	On data load it applies persisted audio volumes to the Audio system, and keeps
	applying server-confirmed changes. Settings UI should call:

		local Settings = ClientRuntime:GetController("SettingsController")
		Settings:Set("Volume_Music", 0.3)  -- applies instantly + persists
		Settings:Get("Volume_Music")       -- current local value
		Settings.Changed:Connect(function(key, value) ... end)

	Volume_<Group> keys map straight to Audio:SetVolumeScale(<Group>, value), so a
	"lower all enemy sounds to 30%" slider is just sounds in an "Enemy" SoundGroup
	plus Settings:Set("Volume_Enemy", 0.3) (register the key in SettingsService).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Relay = Core:GetShared("Network")
local Replica = Core:Get("Replica")
local Audio = require(ReplicatedStorage:WaitForChild("Audio"))

local SettingsController = {}
SettingsController.Changed = Relay.Signal.new()

local _values: { [string]: any } = {}

local function applySetting(key: string, value: any)
	if _values[key] == value then
		return
	end
	_values[key] = value

	local group = string.match(key, "^Volume_(.+)$")
	if group and type(value) == "number" then
		Audio:SetVolumeScale(group, value)
	end

	SettingsController.Changed:Fire(key, value)
end

local function applyAll(settings: any)
	if type(settings) ~= "table" then
		return
	end
	for key, value in settings do
		applySetting(key, value)
	end
end

function SettingsController:Get(key: string): any
	return _values[key]
end

--- Applies the setting locally right away and asks the server to persist it.
function SettingsController:Set(key: string, value: any)
	applySetting(key, value)
	Relay.Settings.SetSetting.send({ key = key, value = value })
end

function SettingsController:Start(_fw: any)
	Replica:WaitForData("Player"):andThen(function(replica: any)
		applyAll(replica.Data.Settings)

		-- server-confirmed changes (rejected writes revert, other devices sync)
		local ok = pcall(function()
			replica:ListenToChange({ "Settings" }, function(newSettings: any)
				applyAll(newSettings)
			end)
		end)
		if not ok then
			warn("SettingsController: replica ListenToChange unavailable; settings apply on load only")
		end
	end)
end

return SettingsController
