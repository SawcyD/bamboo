--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

assert(not RunService:IsServer(), "ClientRuntime must only be required on the client")

local ModuleLoader = require(ReplicatedStorage:WaitForChild("Core"):WaitForChild("ModuleLoader"))

local ClientRuntime = {}

local _controllers = ModuleLoader.new(script:WaitForChild("Controllers") :: Folder)
local _modules = ModuleLoader.new(script:WaitForChild("Modules") :: Folder)
local _configs = ModuleLoader.new(script:WaitForChild("Configs") :: Folder)
local _started = false

function ClientRuntime:GetController(name: string): any
	return _controllers:Get(name)
end

function ClientRuntime:GetModule(name: string): any
	return _modules:Get(name)
end

function ClientRuntime:GetConfig(name: string): any
	return _configs:Get(name)
end

function ClientRuntime:Start()
	assert(not _started, "ClientRuntime:Start() called more than once")
	_started = true
	_controllers:StartAll("ClientRuntime", ClientRuntime)
end

return ClientRuntime
