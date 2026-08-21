--!strict
-- Vertical break cascade: a felled stalk comes apart at its joints, bottom
-- segment first, each one snapping a beat after the one below it.
--
-- This is a *reaction*, never a decision. By the time anything here runs the
-- server has already resolved the swing, confirmed the stalk broke, and granted
-- the reward. The cascade cannot cut, cannot grant, and cannot fail in a way
-- that affects the bag — worst case it degrades to a plain collapse.
--
-- Two design points worth knowing:
--
--   * Every segment is cloned and the originals hidden *up front*, in one pass,
--     before any animation starts. The real stalk model is destroyed by the
--     growth controller ~0.85s after the cut, which is shorter than a tall
--     stalk's full cascade. Snapshotting first means the show cannot be cut off
--     halfway by the corpse being cleaned up.
--
--   * The whole thing is budgeted. A wide multi-hit plus a Chain proc can
--     confirm a dozen stalks in one packet; a dozen unbudgeted cascades is
--     several hundred loose parts and tweens arriving in the same frame. Over
--     budget, a stalk collapses instead — still a break, just without the
--     per-joint theatre.

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Orbify = Core:Get("Orbify")

local FeelBurst = require(script.Parent:WaitForChild("FeelBurst"))
local BambooAudio = require(script.Parent:WaitForChild("BambooAudio"))
local StalkPose = require(script.Parent:WaitForChild("StalkPose"))
local FeelConfig = require(script.Parent.Parent:WaitForChild("Configs"):WaitForChild("FeelConfig"))

local SegmentCascade = {}

local CASCADE = FeelConfig.Cascade

-- Marks a model as already cascading. An attribute rather than a table so it
-- cannot outlive the Instance and leak.
local CASCADING_ATTRIBUTE = "BambooCascading"

local _liveSegments = 0
local _liveCascades = 0
local _effectsFolder: Folder? = nil

export type CascadeConfig = {
	Model: Model,
	-- Where the stalk stood, at ground level.
	Position: Vector3,
	-- Where the swing came from; segments are thrown away from it.
	Origin: Vector3,
	Rarity: any,
	Mutation: any,
	-- Player root the reward fragments fly to, or nil when the bag was full.
	Target: BasePart?,
	-- Extra delay before this stalk starts, so several stalks felled together
	-- read as a run of cascades rather than one mush.
	StartDelay: number?,
}

local function _folder(): Folder
	local existing = _effectsFolder
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "BambooCascade"
	created.Parent = workspace
	_effectsFolder = created
	return created
end

-- ── snapshot ─────────────────────────────────────────────────────────────────

-- Detaches the stalk's visuals into per-joint groups of anchored clones, and
-- hides the originals. Returns the groups bottom-first.
--
-- The clones sit exactly where the originals were, so the moment of snapshotting
-- is invisible — the stalk looks untouched until the first joint lets go.
local function _snapshot(model: Model, segmentCount: number): { { BasePart } }
	local groups: { { BasePart } } = {}
	for index = 1, segmentCount do
		groups[index] = {}
	end

	local parent = _folder()

	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end
		local segmentIndex = part:GetAttribute("SegmentIndex") :: number?
		if not segmentIndex then
			continue
		end
		local slot = groups[math.clamp(segmentIndex, 1, segmentCount)]
		if not slot then
			continue
		end

		local clone = part:Clone()
		-- Anchored throughout: a break must never become a physics assembly that
		-- can be flung across the plot or wake the solver on a phone.
		clone.Anchored = true
		clone.CanCollide = false
		clone.CanQuery = false
		clone.CanTouch = false
		clone.CastShadow = false
		-- Attributes were only ever for the builder and the cascade; the clone is
		-- about to be thrown away, so it does not need them.
		clone:SetAttribute("SegmentIndex", nil)
		clone:SetAttribute("BaseSize", nil)
		clone:SetAttribute("BaseOffset", nil)
		clone.Parent = parent
		table.insert(slot, clone)

		-- Hide rather than destroy: the growth controller owns this model and
		-- destroys it on its own schedule. Reparenting or destroying it here
		-- would race that.
		part.Transparency = 1
	end

	return groups
end

-- ── one joint ────────────────────────────────────────────────────────────────

-- Snaps one group free: a short tilt at the joint, then an outward throw that
-- tumbles and fades.
local function _breakSegment(
	group: { BasePart },
	index: number,
	segmentCount: number,
	away: Vector3,
	tuning: any,
	rarity: any,
	mutation: any
)
	if #group == 0 then
		return
	end

	local snapSeconds = CASCADE.SegmentSnapSeconds
	local flightSeconds = CASCADE.SegmentFlightSeconds

	-- Taken from the segment's own parts rather than measured up from the stalk's
	-- foot. Stalks are built with up to 7 degrees of tilt, so a joint height
	-- projected straight up from the base misses the real joint by a couple of
	-- studs near the top — enough for the chips and the snap to fire off the
	-- stalk entirely on a tall one.
	local centroid = Vector3.zero
	for _, part in group do
		centroid += part.Position
	end
	local jointPosition = centroid / #group

	-- Higher joints are thrown harder, so the cascade visibly travels upward
	-- rather than every segment falling the same way.
	local climb = (index - 1) / math.max(segmentCount - 1, 1)
	local kick = (CASCADE.KickSpeedBase + CASCADE.KickSpeedPerSegment * (index - 1)) * tuning.kick
	local spin = CASCADE.SpinRadians * tuning.spin

	-- Sideways scatter so a stalk does not come apart in a flat plane.
	local lateral = Vector3.new(-away.Z, 0, away.X) * (math.random() - 0.5) * kick * 0.5
	local throw = away * kick * 0.3 + lateral * 0.3 + Vector3.new(0, CASCADE.KickUpSpeed * 0.12, 0)

	for _, part in group do
		-- Beat 1: the joint gives. A small tilt before it leaves, which is what
		-- makes it read as snapping rather than being deleted.
		local tilt = CFrame.fromAxisAngle(Vector3.new(-away.Z, 0, away.X), math.rad(9) * tuning.spin)
		local snapTarget = CFrame.new(jointPosition) * tilt * CFrame.new(jointPosition):ToObjectSpace(part.CFrame)

		TweenService:Create(part, TweenInfo.new(snapSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			CFrame = snapTarget,
		}):Play()

		-- Beat 2: thrown clear, tumbling and fading. CFrame and Transparency ride
		-- one tween, so a segment costs one tween per part rather than two.
		task.delay(snapSeconds, function()
			if not part.Parent then
				return
			end
			local flightTarget = CFrame.new(part.Position + throw)
				* CFrame.Angles(
					math.random() * spin - spin * 0.5,
					math.random() * spin - spin * 0.5,
					math.random() * spin - spin * 0.5
				)
			TweenService:Create(part, TweenInfo.new(flightSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = flightTarget,
				Transparency = 1,
			}):Play()
		end)

		Debris:AddItem(part, snapSeconds + flightSeconds + 0.2)
	end

	-- Wood chips at the joint itself, tinted by the mutation so a Golden stalk
	-- sheds gold at every break rather than only at the end.
	local chipColor = if mutation.id == "None" then rarity.color else mutation.color
	FeelBurst.Chips(jointPosition, chipColor, rarity.impactWeight * 0.8, FeelConfig.Burst.Chip.Count)

	BambooAudio.SegmentSnap(jointPosition, rarity.id, climb)
end

-- The payoff beat, shared by both paths so a stalk that was over budget still
-- pays out visually exactly like one that cascaded. Owns dust, the rare-mutation
-- reveal, the finale sting, and the reward fragments.
local function _finale(config: CascadeConfig, rarity: any, mutation: any, weight: number)
	FeelBurst.Dust(config.Position, rarity.impactWeight * weight, FeelConfig.Burst.Dust.Count)
	FeelBurst.Reveal(config.Position, mutation, FeelConfig.Reveal.BaseCount)
	BambooAudio.CascadeFinale(config.Position, rarity.id)

	local target = config.Target
	if not target then
		return
	end

	-- Visual only. The server granted this stalk's reward once, before any of
	-- this ran; these fragments carry that value to the eye and are capped
	-- independently of both the segment count and the amount collected, so a
	-- taller stalk can never look like — or be — a bigger payout.
	local color = if mutation.id == "None" then rarity.color else mutation.color
	Orbify.Burst({
		Origin = config.Position + Vector3.new(0, 1.5, 0),
		Target = target,
		Count = CASCADE.MaxRewardFragments,
		Color = color,
		Size = Vector3.new(1.4, 0.5 * rarity.thicknessScale, 0.5 * rarity.thicknessScale),
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Grass,
		Parent = _folder(),
		PopSpeed = 0,
		TumbleSeconds = 0,
		ArcHeight = 5,
	})
end

-- ── public ───────────────────────────────────────────────────────────────────

--[[
	Runs the break cascade for one confirmed-destroyed stalk.

	Safe to call more than once for the same model — the second call is ignored,
	so a duplicate SwingResult can never double the show.

	@param config CascadeConfig The stalk, where it stood, and how it should break.
	@return boolean True when the full per-joint cascade ran; false when the stalk
		was over budget and collapsed instead.
]]
function SegmentCascade.Run(config: CascadeConfig): boolean
	local model = config.Model
	if not model.Parent then
		return false
	end

	-- Runs exactly once per stalk, whatever the caller does.
	if model:GetAttribute(CASCADING_ATTRIBUTE) then
		return false
	end
	model:SetAttribute(CASCADING_ATTRIBUTE, true)

	local rarity = config.Rarity
	local mutation = config.Mutation
	local segmentCount = (model:GetAttribute("SegmentCount") :: number?) or 0

	local tuning = CASCADE.Rarity[rarity.id] or CASCADE.Rarity.Normal

	-- Budget gate. Over the ceiling the stalk still breaks, it just topples as one
	-- piece — one pivot per frame instead of a few dozen parts and tweens.
	local overBudget = segmentCount <= 0
		or _liveSegments + segmentCount > CASCADE.MaxLiveSegments
		or _liveCascades >= CASCADE.MaxConcurrentCascades

	if overBudget then
		StalkPose.Topple(model, config.Origin, rarity.id)
		_finale(config, rarity, mutation, 1)
		return false
	end

	_liveSegments += segmentCount
	_liveCascades += 1

	local groups = _snapshot(model, segmentCount)

	local away = Vector3.new(config.Position.X - config.Origin.X, 0, config.Position.Z - config.Origin.Z)
	if away.Magnitude < 0.05 then
		away = Vector3.xAxis
	end
	away = away.Unit

	local baseDelay = CASCADE.SegmentDelay * tuning.delay
	local startDelay = config.StartDelay or 0
	local lastAt = startDelay

	for index = 1, segmentCount do
		-- Slight per-joint jitter so the run is not metronomic, but bounded so the
		-- cascade still reads as travelling in one direction.
		local jitter = 1 + (math.random() * 2 - 1) * CASCADE.SegmentDelayJitter
		local at = startDelay + baseDelay * (index - 1) * jitter
		lastAt = math.max(lastAt, at)

		task.delay(at, function()
			_breakSegment(groups[index], index, segmentCount, away, tuning, rarity, mutation)
		end)
	end

	-- Once the top joint has let go, the stalk is gone. The payoff lands here, at
	-- the end of the cascade, rather than at the start of it.
	task.delay(lastAt + CASCADE.SegmentSnapSeconds, function()
		_finale(config, rarity, mutation, 1.3)
	end)

	-- Release the budget once the last segment has finished its flight, not when
	-- it starts, or a long cascade would let the next one in too early.
	task.delay(lastAt + CASCADE.SegmentSnapSeconds + CASCADE.SegmentFlightSeconds + 0.2, function()
		_liveSegments = math.max(_liveSegments - segmentCount, 0)
		_liveCascades = math.max(_liveCascades - 1, 0)
	end)

	return true
end

--[[
	Live cascade counters, for the performance overlay.
	@return number Segments currently animating.
	@return number Cascades currently running.
]]
function SegmentCascade.GetLoad(): (number, number)
	return _liveSegments, _liveCascades
end

return SegmentCascade
