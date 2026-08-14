--!strict
-- Template for a client controller
-- Copy this file, rename it, implement Start and public methods

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- selene: allow(unused_variable)
local Core = require(ReplicatedStorage:WaitForChild("Core"))

local ControllerName = {}
-- selene: allow(unused_variable)
local Framework

function ControllerName:Start(fw: any)
	Framework = fw
	-- wire connections here
	-- use Framework:GetController() inside methods, not here
end

-- public methods go here

return ControllerName
