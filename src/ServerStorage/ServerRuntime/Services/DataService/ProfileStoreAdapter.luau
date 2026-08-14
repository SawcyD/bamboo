--!strict
-- Wraps ProfileStore library with studio/live key selection and migration

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local ProfileStoreAdapter = {}

local Migration = require(script.Parent:WaitForChild("Migration"))
local Schema = require(script.Parent:WaitForChild("Schema"))

local Core = require(game:GetService("ReplicatedStorage"):WaitForChild("Core"))
local Promise = Core:GetPackage("Promise")
local ProfileStore = Core:GetPackage("ProfileStore")
local TAG = "[ProfileStoreAdapter]"

-- requires ProfileStore from ServerRuntime packages
-- local ServerRuntime = require(game:GetService("ServerStorage"):WaitForChild("ServerRuntime"))

local _storeKey = RunService:IsStudio() and "PlayerData_Test" or "PlayerData"
local _store = ProfileStore.New(_storeKey, Schema.defaultData)
print(TAG, "Initialized store", _storeKey, "Studio=", RunService:IsStudio())

-- loads a profile, reconciles defaults, then runs migrations; returns a Promise
function ProfileStoreAdapter.StartSessionAsync(userId: number): any
	return Promise.new(function(resolve: (any) -> (), reject: (any) -> ())
		local ok, profileOrErr = pcall(function()
			return _store:StartSessionAsync("Player_" .. userId, {
				-- Studio test sessions can leave stale locks; allow force-steal there.
				Steal = RunService:IsStudio(),
				Cancel = function()
					-- cancel if the player with this UserId is no longer in-server
					local shouldCancel = Players:GetPlayerByUserId(userId) == nil
					if shouldCancel then
						print(TAG, "Canceling load for userId=", userId, "because player is no longer in server")
					end
					return shouldCancel
				end,
			})
		end)
		if not ok then
			warn(TAG, "StartSessionAsync error", userId, profileOrErr)
			reject("ProfileStore error for userId=" .. userId .. ": " .. tostring(profileOrErr))
			return
		end
		local profile = profileOrErr
		if profile then
			print(TAG, "StartSessionAsync success", userId)
			profile:Reconcile()
			profile.Data = Migration.Run(profile.Data)
			resolve(profile)
		else
			local state = tostring(ProfileStore.DataStoreState)
			warn(TAG, "StartSessionAsync returned nil", userId, "DataStoreState=", state)
			local reason = "ProfileStore failed to load for userId=" .. userId .. " (DataStoreState=" .. state .. ")"
			if RunService:IsStudio() and state ~= "Access" then
				reason ..= " - Enable Studio API access in Game Settings > Security."
			end
			reject(reason)
		end
	end)
end

function ProfileStoreAdapter.Save(profile: any)
	print(TAG, "Save called", profile and profile.Key or "nil")
	local ok, err = pcall(function()
		if profile:IsActive() then
			profile:Save()
		end
	end)
	if not ok then
		warn(TAG, "Save error:", err)
	end
end

function ProfileStoreAdapter.EndSession(profile: any)
	print(TAG, "EndSession called", profile and profile.Key or "nil")
	local ok, err = pcall(function()
		profile:EndSession()
	end)
	if not ok then
		warn(TAG, "EndSession error:", err)
	end
end

return ProfileStoreAdapter
