--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

assert(RunService:IsServer(), "ServerRuntime must only be required on the server")

local ModuleLoader = require(ReplicatedStorage:WaitForChild("Core"):WaitForChild("ModuleLoader"))

local ServerRuntime = {}

local _services = ModuleLoader.new(script:WaitForChild("Services") :: Folder)
local _modules = ModuleLoader.new(script:WaitForChild("Modules") :: Folder)
local _configs = ModuleLoader.new(script:WaitForChild("Configs") :: Folder)
local _packages = ModuleLoader.new(script:WaitForChild("Packages") :: Folder)
local _started = false

function ServerRuntime:GetService(name: string): any
	return _services:Get(name)
end

function ServerRuntime:GetModule(name: string): any
	return _modules:Get(name)
end

function ServerRuntime:GetConfig(name: string): any
	return _configs:Get(name)
end

function ServerRuntime:GetPackage(name: string): any
	return _packages:Get(name)
end

function ServerRuntime:Start()
	assert(not _started, "ServerRuntime:Start() called more than once")
	_started = true
	_services:StartAll("ServerRuntime", ServerRuntime)
end

return ServerRuntime
