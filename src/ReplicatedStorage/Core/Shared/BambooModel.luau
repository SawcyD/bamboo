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

--[[
	Stalk proportions, in one place.

	Height is expressed as `BaseHeight * HeightMultiplier` rather than as a single
	tuned number so the original Phase 1 scale stays visible and the forest can be
	made taller or shorter by moving one value. Segment count is *derived* from the
	finished height instead of fixed, which is what lets a Tall stalk break into
	visibly more joints than a Normal one without a second code path.
]]
BambooModel.Config = table.freeze({
	-- Studs, a Normal mature stalk at variation 1.0, before the multiplier.
	BaseHeight = 9,
	-- Forest scale. 2.0 puts a Normal stalk at 18 studs and a Tall near 28 — high
	-- enough to close the canopy overhead, while the rotor orbits at chest height
	-- and the stalk bases stay clear, so targeting and the sell direction still
	-- read from inside the field.
	HeightMultiplier = 2.0,
	BaseDiameter = 0.65,

	-- Target studs per visual segment. The joint spacing the cascade breaks at.
	StudsPerSegment = 3.5,
	-- A stalk always has at least this many joints to cascade through, and never
	-- more than this many — the cap is a part-count ceiling as much as an art
	-- decision, since a full field multiplies whatever this is by ~180.
	MinSegments = 3,
	MaxSegments = 8,
})

local CONFIG = BambooModel.Config
local BASE_HEIGHT = CONFIG.BaseHeight * CONFIG.HeightMultiplier
local BASE_DIAMETER = CONFIG.BaseDiameter
local NODE_COLOR_DARKEN = 0.22
local LEAF_SIZE = Vector3.new(0.08, 1.5, 0.55)
-- Mutations at or above this glow get a PointLight, so only the genuinely rare
-- ones cost a light.
local AURA_GLOW_THRESHOLD = 0.5

-- How many joints a stalk of this height breaks into.
local function _segmentCountFor(height: number): number
	local count = math.round(height / CONFIG.StudsPerSegment)
	return math.clamp(count, CONFIG.MinSegments, CONFIG.MaxSegments)
end

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

-- Mutations restyle the stalk rather than adding decoration on top: a mutated
-- stalk changes colour, node colour, leaf colour, and material together, so it
-- is recognisable at a glance on a phone rather than only up close.
local function _mutationStyle(visual: StalkVisual)
	local mutation = Bamboo.Mutations.Get(visual.mutation)
	if mutation.id == "None" then
		return {
			color = visual.color,
			nodeColor = _darken(visual.color, NODE_COLOR_DARKEN),
			leafColor = visual.color,
			material = Enum.Material.Grass,
			glow = 0,
		}
	end

	return {
		-- Keep a little of the stalk's own colour jitter so mutated bamboo still
		-- varies between stalks instead of looking stamped.
		color = mutation.color:Lerp(visual.color, 0.12),
		nodeColor = mutation.nodeColor,
		leafColor = mutation.leafColor,
		material = mutation.material,
		glow = mutation.glow,
	}
end

-- Builds the segments + leaves of one stalk, parented to `model`, standing on
-- `baseCFrame` (which sits on the ground with +Y up).
local function _buildStalkParts(model: Model, baseCFrame: CFrame, visual: StalkVisual, rng: Random)
	local height = BASE_HEIGHT * visual.heightScale
	local diameter = BASE_DIAMETER * visual.thicknessScale
	-- Derived, not fixed: a Tall stalk earns more joints purely by being taller,
	-- so its cascade is naturally longer than a Normal one's.
	local segmentCount = _segmentCountFor(height)
	local segmentHeight = height / segmentCount
	local style = _mutationStyle(visual)
	local nodeColor = style.nodeColor

	-- Tilt the whole stalk slightly so a field never reads as a grid.
	local tilt = CFrame.fromAxisAngle(
		Vector3.new(math.cos(visual.tiltAngle), 0, math.sin(visual.tiltAngle)),
		math.rad(visual.tiltDegrees)
	)
	local stalkCFrame = baseCFrame * tilt

	local trunk: Part? = nil

	for i = 1, segmentCount do
		local centreY = (i - 0.5) * segmentHeight
		-- Cylinders extend along X, so rotate 90° to stand them up.
		local segment = _newSegment("Segment" .. i, Vector3.new(segmentHeight * 0.94, diameter, diameter), style.color)
		segment.Material = style.material
		segment.CFrame = stalkCFrame * CFrame.new(0, centreY, 0) * CFrame.Angles(0, 0, math.rad(90))
		-- Which joint this part belongs to. The cascade groups the model by this
		-- rather than by name, so nodes and leaves travel with their segment.
		segment:SetAttribute("SegmentIndex", i)
		segment.Parent = model
		trunk = trunk or segment

		-- Node ring between segments reads as a bamboo joint at any distance, and
		-- marks exactly where the stalk is about to snap.
		if i < segmentCount then
			local node =
				_newSegment("Node" .. i, Vector3.new(diameter * 0.35, diameter * 1.18, diameter * 1.18), nodeColor)
			node.CFrame = stalkCFrame * CFrame.new(0, i * segmentHeight, 0) * CFrame.Angles(0, 0, math.rad(90))
			-- The joint at the top of segment i goes with segment i, so a detaching
			-- segment carries its own cap.
			node:SetAttribute("SegmentIndex", i)
			node.Parent = model
		end
	end

	for _ = 1, visual.leafCount do
		local leaf = _newLeaf(style.leafColor)
		local heightAlong = rng:NextNumber(height * 0.45, height * 0.98)
		local yaw = rng:NextNumber(0, math.pi * 2)
		leaf.CFrame = stalkCFrame
			* CFrame.new(0, heightAlong, 0)
			* CFrame.Angles(0, yaw, math.rad(rng:NextNumber(35, 75)))
			* CFrame.new(0, LEAF_SIZE.Y * 0.5, 0)
		leaf.Size = LEAF_SIZE * Vector3.new(1, rng:NextNumber(0.75, 1.3), rng:NextNumber(0.8, 1.2))
		-- Leaves ride the segment they sprout from, so they fall with it.
		leaf:SetAttribute("SegmentIndex", math.clamp(math.ceil(heightAlong / segmentHeight), 1, segmentCount))
		leaf.Parent = model
	end

	-- Rare mutations get a light so they are visible before the stalk itself
	-- resolves. One light per stalk, only on the mutations that earn it.
	if style.glow >= AURA_GLOW_THRESHOLD and trunk then
		local light = Instance.new("PointLight")
		light.Name = "MutationAura"
		light.Color = style.color
		light.Brightness = 1.5 * style.glow
		light.Range = 10 + 8 * style.glow
		light.Shadows = false
		light.Parent = trunk
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
	-- Read by the cascade to know how many joints to break and where each one is.
	model:SetAttribute("SegmentCount", segmentCount)
	model:SetAttribute("SegmentHeight", segmentHeight)
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
	model:SetAttribute("Mutation", visual.mutation)
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
	BambooModel.ApplyScale(model, scale, baseCFrame)
	model:SetAttribute("Stage", stage)
end

--[[
	Scales a stalk in place to an arbitrary factor, for continuous growth. The
	stage scales are just three points on this curve — the client walks between
	them smoothly instead of snapping.
	@param model Model Stalk previously returned by Build.
	@param scale number Multiplier, e.g. 0.5 for half height.
	@param baseCFrame CFrame The stalk's ground CFrame, used as the scale pivot.
]]
function BambooModel.ApplyScale(model: Model, scale: number, baseCFrame: CFrame)
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
end

return BambooModel
