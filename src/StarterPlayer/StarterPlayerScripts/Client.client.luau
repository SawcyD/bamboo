--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientRuntime = require(ReplicatedStorage:WaitForChild("ClientRuntime"))
local UI = require(ReplicatedStorage:WaitForChild("UI"))

ClientRuntime:Start()
UI:Start()
