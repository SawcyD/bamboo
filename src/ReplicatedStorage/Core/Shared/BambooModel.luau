--!strict
-- Procedural bamboo stalk builder.
--
-- Phase 1 has no Blender assets yet, so stalks are assembled from parts here.
-- When the real meshes land, replace the body of `_buildStalkParts` with a clone
-- of the authored model; the rest of the game only touches Build/ApplyStage and
-- never assumes the stalk is part-built.

local BambooFolder = script.Parent:WaitForChild("Domains"):WaitForChild("Bamboo")
local Bamboo = require(BambooFolder)
local BambooTypes = require(BambooFolder:WaitForChild("Types"))

local BambooModel = {}

local SEGMENT_COUNT = 4
local BASE_HEIGHT = 9 -- studs, a Normal mature stalk at variation 1.0
local BASE_DIAMETER = 0.65
local NODE_COLOR_DARKEN = 0.22
local LEAF_SIZE = Vector3.new(0.08, 1.5, 0.55)

export type StalkVisual = BambooTypes.StalkVisual

-- ── helpers ──────────────────────────────────────────────────────────────────

local function _darken(color: Color3, amount: number): Color3
	return Color3.new(color.R * (1 - amount), color.G * (1 - amount), color.B * (1 - amount))
end

local function _newSegment(name: string, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

local function _newLeaf(color: Color3): Part
	local leaf = Instance.new("Part")
	leaf.Name = "Leaf"
	leaf.Size = LEAF_SIZE
	leaf.Color = color
	leaf.Material = Enum.Material.SmoothPlastic
	leaf.Anchored = true
	leaf.CanCollide = false
	leaf.CanQuery = false
	leaf.CanTouch = false
	leaf.CastShadow = false
	return leaf
end

-- Builds the segments + leaves of one stalk, parented to `model`, standing on
-- `baseCFrame` (which sits on the ground with +Y up).
local function _buildStalkParts(model: Model, baseCFrame: CFrame, visual: StalkVisual, rng: Random)
	local height = BASE_HEIGHT * visual.heightScale
	local diameter = BASE_DIAMETER * visual.thicknessScale
	local segmentHeight = height / SEGMENT_COUNT
	local nodeColor = _darken(visual.color, NODE_COLOR_DARKEN)

	-- Tilt the whole stalk slightly so a field never reads as a grid.
	local tilt = CFrame.fromAxisAngle(
		Vector3.new(math.cos(visual.tiltAngle), 0, math.sin(visual.tiltAngle)),
		math.rad(visual.tiltDegrees)
	)
	local stalkCFrame = baseCFrame * tilt

	local trunk: Part? = nil

	for i = 1, SEGMENT_COUNT do
		local centreY = (i - 0.5) * segmentHeight
		-- Cylinders extend along X, so rotate 90° to stand them up.
		local segment = _newSegment("Segment" .. i, Vector3.new(segmentHeight * 0.94, diameter, diameter), visual.color)
		segment.CFrame = stalkCFrame * CFrame.new(0, centreY, 0) * CFrame.Angles(0, 0, math.rad(90))
		segment.Parent = model
		trunk = trunk or segment

		-- Node ring between segments reads as a bamboo joint at any distance.
		if i < SEGMENT_COUNT then
			local node =
				_newSegment("Node" .. i, Vector3.new(diameter * 0.35, diameter * 1.18, diameter * 1.18), nodeColor)
			node.CFrame = stalkCFrame * CFrame.new(0, i * segmentHeight, 0) * CFrame.Angles(0, 0, math.rad(90))
			node.Parent = model
		end
	end

	for _ = 1, visual.leafCount do
		local leaf = _newLeaf(visual.color)
		local heightAlong = rng:NextNumber(height * 0.45, height * 0.98)
		local yaw = rng:NextNumber(0, math.pi * 2)
		leaf.CFrame = stalkCFrame
			* CFrame.new(0, heightAlong, 0)
			* CFrame.Angles(0, yaw, math.rad(rng:NextNumber(35, 75)))
			* CFrame.new(0, LEAF_SIZE.Y * 0.5, 0)
		leaf.Size = LEAF_SIZE * Vector3.new(1, rng:NextNumber(0.75, 1.3), rng:NextNumber(0.8, 1.2))
		leaf.Parent = model
	end

	-- Cache each part's untouched size/offset so ApplyStage can rescale from the
	-- original values instead of compounding float error every stage change.
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part:SetAttribute("BaseSize", part.Size)
			part:SetAttribute("BaseOffset", baseCFrame:ToObjectSpace(part.CFrame))
		end
	end

	if trunk then
		model.PrimaryPart = trunk
	end
	-- Pivot sits at the stalk's foot, so PivotTo bends it from the ground the way
	-- a real stalk would rather than rotating it about its middle.
	model.WorldPivot = baseCFrame
	model:SetAttribute("StageScale", 1)
	model:SetAttribute("Height", height)
	model:SetAttribute("Diameter", diameter)
end

-- ── public API ───────────────────────────────────────────────────────────────

--[[
	Builds a whole stalk model, unparented, standing at `baseCFrame`.
	@param visual StalkVisual Look rolled by Bamboo.Rarity.RollVisual.
	@param baseCFrame CFrame Ground position, +Y up, where the stalk's foot sits.
	@param rng Random Stream used for leaf placement.
	@return Model The stalk; PrimaryPart is its lowest trunk segment.
]]
function BambooModel.Build(visual: StalkVisual, baseCFrame: CFrame, rng: Random): Model
	local model = Instance.new("Model")
	model.Name = "Bamboo"
	_buildStalkParts(model, baseCFrame, visual, rng)
	model:SetAttribute("Rarity", visual.rarity)
	return model
end

--[[
	Scales a stalk in place to match a growth stage.
	Shoot/Young are the same stalk shrunk, so growth costs no rebuild.
	@param model Model Stalk previously returned by Build.
	@param stage number A Bamboo.Field.Stage value.
	@param baseCFrame CFrame The stalk's ground CFrame, used as the scale pivot.
]]
function BambooModel.ApplyStage(model: Model, stage: number, baseCFrame: CFrame)
	local scale = Bamboo.Field.StageScale[stage] or 1
	local previous = model:GetAttribute("StageScale") or 1
	if math.abs(previous - scale) < 1e-3 then
		return
	end

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local baseSize = part:GetAttribute("BaseSize") :: Vector3?
			local baseOffset = part:GetAttribute("BaseOffset") :: CFrame?
			if baseSize and baseOffset then
				part.Size = baseSize * scale
				part.CFrame = baseCFrame * CFrame.new(baseOffset.Position * scale) * baseOffset.Rotation
			end
		end
	end

	model:SetAttribute("StageScale", scale)
	model:SetAttribute("Stage", stage)
end

return BambooModel
