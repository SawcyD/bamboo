--!strict
-- Template for a server service
-- Copy this file, rename it, implement Start and public methods

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- selene: allow(unused_variable)
local Core = require(ReplicatedStorage:WaitForChild("Core"))

local ServiceName = {}
-- selene: allow(unused_variable)
local Framework

-- private state goes here

function ServiceName:Start(fw: any)
	Framework = fw
	-- wire connections here
	-- use Framework:GetService() inside methods, not here
end

-- public methods go here

return ServiceName
