--!strict
--[[
	AntiCheatController: client-side tripwires that REPORT to the server.

	This is the smoke detector, not the lock. Everything here runs on the client,
	so a determined exploiter can disable it — that's exactly why it does nothing
	but send hints to AntiCheatService, which corroborates them server-side. Two
	jobs:

	  1. Heartbeat — ping the server ~1/s. If an exploiter deletes this controller,
	     the pings stop and the server's watchdog notices. (Hiding the script does
	     not help; a server-enforced heartbeat does.)

	  2. UI-injection scan — flag ScreenGuis in PlayerGui that aren't approved,
	     catching cheat menus injected there.

	     IMPORTANT LIMITATION: most cheat menus inject into CoreGui, which game
	     scripts physically cannot read. This only sees PlayerGui, so it catches
	     lazy/public menus, not serious ones. Keep ApprovedGuiNames current with
	     your own top-level ScreenGui names or you'll get false positives.

	Register your own UI as approved:
		local AntiCheat = ClientRuntime:GetController("AntiCheatController")
		AntiCheat.Approve("ShopGui")
]]

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Relay = Core:GetShared("Network")
local Scheduler = Core:Get("Scheduler")

local AntiCheatController = {}

-- Fill with the names of top-level GUIs your game creates in PlayerGui. Names
-- present in StarterGui are auto-approved at Start.
AntiCheatController.ApprovedGuiNames = {} :: { [string]: boolean }

local reported: { [Instance]: boolean } = {}

--- Approve a GUI by name (or pass the instance) so the scanner ignores it.
function AntiCheatController.Approve(nameOrInstance: string | Instance)
	if typeof(nameOrInstance) == "Instance" then
		AntiCheatController.ApprovedGuiNames[nameOrInstance.Name] = true
	else
		AntiCheatController.ApprovedGuiNames[nameOrInstance] = true
	end
end

local function report(reason: string, detail: string?)
	Relay.AntiCheat.Report.send({ reason = reason, detail = detail })
end

local function inspect(child: Instance)
	-- only LayerCollectors (ScreenGui / etc.) are interesting as injected menus
	if not child:IsA("LayerCollector") then
		return
	end
	if AntiCheatController.ApprovedGuiNames[child.Name] then
		return
	end
	if reported[child] then
		return
	end
	reported[child] = true
	report("UnapprovedGui", child.Name)
end

function AntiCheatController:Start(_fw: any)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	-- anything the game ships in StarterGui is legitimate
	for _, child in StarterGui:GetChildren() do
		AntiCheatController.ApprovedGuiNames[child.Name] = true
	end

	-- heartbeat: prove this controller is alive ~1/s
	Scheduler.Every(1, function()
		Relay.AntiCheat.Heartbeat.send({})
	end)

	-- scan now, on every new child, and periodically (in case ChildAdded is hooked)
	for _, child in playerGui:GetChildren() do
		inspect(child)
	end
	playerGui.ChildAdded:Connect(inspect)
	Scheduler.Every(0.5, function()
		for _, child in playerGui:GetChildren() do
			inspect(child)
		end
	end)
end

return AntiCheatController
