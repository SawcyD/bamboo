--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Core = require(ReplicatedStorage:WaitForChild("Core"))
local ServerStorage = game:GetService("ServerStorage")
local ServerRuntime = require(ServerStorage:WaitForChild("ServerRuntime"))

Core:GetShared("Network")
ServerRuntime:Start()
