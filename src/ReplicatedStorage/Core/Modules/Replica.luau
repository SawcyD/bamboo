--!strict
--[[
	Client replica registry. The "Player" class (your profile data) is tracked by
	default; register any extra replica classes your game's server creates:

		local Replica = Core:Get("Replica")

		Replica:WaitForData("Player"):andThen(function(replica)
			print(replica.Data.Coins)
			replica:ListenToChange({ "Coins" }, function(new) ... end)
		end)

		-- a game-specific global replica:
		Replica.Register("MatchState")
		Replica.MatchStateLoaded:Connect(function(replica) ... end)

	Register with ownerOnly = true for per-player replicas where the client should
	only track its own (matched via replica.Tags.UserId).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Core = require(ReplicatedStorage:WaitForChild("Core"))

local Relay = Core:GetShared("Network")
local ReplicaController = Core:GetPackage("ReplicaController")
local Promise = Core:GetPackage("Promise")

local module = {
	--- The local player's data replica (nil until DataLoaded fires).
	Player = nil :: any,
	DataLoaded = Relay.Signal.new(),
}

local _replicas: { [string]: any } = {}
local _loadedSignals: { [string]: any } = {}
local _registered: { [string]: boolean } = {}

--- Tracks replicas of `className`. Exposes module[className], a
--- module[className .. "Loaded"] signal, and Get/WaitForData support.
function module.Register(className: string, ownerOnly: boolean?)
	if _registered[className] then
		return
	end
	_registered[className] = true

	local loadedSignal = _loadedSignals[className] or Relay.Signal.new()
	_loadedSignals[className] = loadedSignal
	module[className .. "Loaded"] = loadedSignal

	if not RunService:IsClient() then
		return
	end

	ReplicaController.ReplicaOfClassCreated(className, function(replica: any)
		if ownerOnly and replica.Tags and replica.Tags.UserId ~= Players.LocalPlayer.UserId then
			return
		end
		_replicas[className] = replica
		module[className] = replica
		loadedSignal:Fire(replica)
		replica:AddCleanupTask(function()
			if _replicas[className] == replica then
				_replicas[className] = nil
				module[className] = nil
			end
		end)
	end)
end

function module:Get(className: string): any?
	return _replicas[className]
end

--- Promise resolving with the replica once it exists (immediately if already loaded).
function module:WaitForData(className: string): any
	local existing = _replicas[className]
	if existing then
		return Promise.resolve(existing)
	end
	local loadedSignal = _loadedSignals[className]
	if not loadedSignal then
		return Promise.reject(`Replica: class "{className}" was never registered`)
	end
	return Promise.new(function(resolve: (any) -> ())
		loadedSignal:Once(function(replica: any)
			resolve(replica)
		end)
	end)
end

-- built-in: the local player's profile replica (DataService creates one per player)
module.Register("Player", true)
_loadedSignals.Player:Connect(function(replica: any)
	module.Player = replica
	module.DataLoaded:Fire(replica)
end)

if RunService:IsClient() then
	ReplicaController.RequestData()
end

return module
