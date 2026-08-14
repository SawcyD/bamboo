--!strict
-- Lightweight world-space debug drawing for AI and gameplay development.

local Scheduler = require(script.Parent:WaitForChild("Scheduler"))

local DebugDraw = {}

local folder: Folder? = nil
local enabled = true
local drawings: { [Instance]: boolean } = {}

local function _getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	folder = workspace:FindFirstChild("__FrameworkDebug") :: Folder?
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "__FrameworkDebug"
		folder.Parent = workspace
	end
	return folder
end

local function _finish(instance: Instance, lifetime: number?)
	drawings[instance] = true
	if lifetime and lifetime > 0 then
		Scheduler.Delay(lifetime, function()
			if drawings[instance] then
				drawings[instance] = nil
				instance:Destroy()
			end
		end)
	end
	return instance
end

local function _newPart(color: Color3, transparency: number): Part?
	if not enabled then
		return nil
	end
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency
	part.Parent = _getFolder()
	return part
end

function DebugDraw.SetEnabled(value: boolean)
	enabled = value
	if not value then
		DebugDraw.Clear()
	end
end

function DebugDraw.IsEnabled(): boolean
	return enabled
end

function DebugDraw.Point(position: Vector3, color: Color3?, size: number?, lifetime: number?): Part?
	local part = _newPart(color or Color3.fromRGB(255, 255, 0), 0.1)
	if not part then
		return nil
	end
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * (size or 0.35)
	part.Position = position
	return _finish(part, lifetime) :: Part
end

function DebugDraw.Line(from: Vector3, to: Vector3, color: Color3?, thickness: number?, lifetime: number?): Part?
	local part = _newPart(color or Color3.fromRGB(0, 255, 255), 0.15)
	if not part then
		return nil
	end
	local delta = to - from
	part.Size = Vector3.new(thickness or 0.08, thickness or 0.08, delta.Magnitude)
	part.CFrame = CFrame.lookAt((from + to) * 0.5, to)
	return _finish(part, lifetime) :: Part
end

function DebugDraw.Box(cframe: CFrame, size: Vector3, color: Color3?, lifetime: number?): Part?
	local part = _newPart(color or Color3.fromRGB(255, 80, 80), 0.8)
	if not part then
		return nil
	end
	part.Size = size
	part.CFrame = cframe
	return _finish(part, lifetime) :: Part
end

function DebugDraw.Radius(position: Vector3, radius: number, color: Color3?, lifetime: number?): Part?
	local part = _newPart(color or Color3.fromRGB(80, 255, 80), 0.85)
	if not part then
		return nil
	end
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * radius * 2
	part.Position = position
	return _finish(part, lifetime) :: Part
end

function DebugDraw.Path(waypoints: { PathWaypoint }, color: Color3?, lifetime: number?)
	for index = 1, #waypoints - 1 do
		DebugDraw.Line(waypoints[index].Position, waypoints[index + 1].Position, color, 0.08, lifetime)
	end
	for _, waypoint in waypoints do
		DebugDraw.Point(waypoint.Position, color, 0.25, lifetime)
	end
end

function DebugDraw.Clear()
	for instance in drawings do
		drawings[instance] = nil
		instance:Destroy()
	end
	if folder then
		folder:ClearAllChildren()
	end
end

function DebugDraw.Destroy()
	DebugDraw.Clear()
	if folder then
		folder:Destroy()
		folder = nil
	end
end

return DebugDraw
