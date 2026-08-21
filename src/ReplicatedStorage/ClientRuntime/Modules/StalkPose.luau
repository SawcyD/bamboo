--!strict
-- Single owner of every rendered stalk's visual transform.
--
-- Four effects want to move a stalk: idle sway, hit recoil, growth pop, and the
-- break topple. Before this module they would have fought — the old recoil
-- captured its rest pose with `model:GetPivot()`, so a stalk struck mid-sway
-- would have adopted the swayed pose as "upright" and drifted a little further
-- with every hit. Routing all four through one module means there is exactly one
-- writer per stalk and one authoritative rest pose.
--
-- The rest pose is the plot's *slot* CFrame — the same ground frame the growth
-- controller plants from — never a sampled pivot. Everything is expressed as a
-- rotation of that ground frame, so no amount of hitting, popping, or toppling
-- can accumulate drift.
--
-- Cost control: one shared RenderStep bind for the whole field, bound only while
-- something is registered. Stalks that are merely swaying are updated on a
-- round-robin budget rather than every frame, because sway is a slow sine and
-- nobody can tell a 13 Hz sway from a 60 Hz one.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Bamboo = Core:GetDomain("Bamboo")
local BambooModel = Core:GetShared("BambooModel")
local Spring = Core:GetPackage("Spring")

local FeelConfig = require(script.Parent.Parent:WaitForChild("Configs"):WaitForChild("FeelConfig"))

local StalkPose = {}

local POSE_BIND = "BambooStalkPose"
local LOCAL_PLAYER = Players.LocalPlayer

local SWAY = FeelConfig.Sway
local POP = FeelConfig.GrowthPop
local TOPPLE = FeelConfig.Topple
local HIT = FeelConfig.StalkHit

-- The pop only stores its overshoot spring. The scale it settles back to is
-- always `entry.Scale`, which the growth pass keeps current — storing a private
-- copy would let a stalk that popped mid-growth settle to a stale size.
type PopState = {
	Spring: any,
}

type ToppleState = {
	StartedAt: number,
	Duration: number,
	-- Horizontal axis the stalk falls about.
	Axis: Vector3,
	FallRadians: number,
	TwistRadians: number,
	BounceRadians: number,
	BounceFraction: number,
}

type Entry = {
	Model: Model,
	-- Ground frame the stalk was planted on. The one authoritative rest pose.
	Slot: CFrame,
	-- Rest pivot expressed in slot space, so a pose is `Slot * rot * PivotFromFoot`
	-- and every rotation happens about the stalk's foot rather than its middle.
	PivotFromFoot: CFrame,
	-- Current growth scale, mirrored so a pop can punch around it.
	Scale: number,
	Stage: number,

	-- Sway character, derived from the stalk id so it is stable across rebuilds.
	Phase: number,
	FrequencyMul: number,
	AmplitudeMul: number,
	SwayAmplitude: number,

	Recoil: any?,
	RecoilAxis: Vector3,
	Pop: PopState?,
	Topple: ToppleState?,
}

local _entries: { [Model]: Entry } = {}
-- Parallel array for round-robin sway, so the budget walks the field evenly
-- instead of favouring whatever order the hash map happens to yield.
local _order: { Model } = {}
local _cursor = 1
local _count = 0
local _bound = false

-- ── helpers ──────────────────────────────────────────────────────────────────

local function _observerPosition(): Vector3?
	local camera = workspace.CurrentCamera
	if camera then
		return camera.CFrame.Position
	end
	local character = LOCAL_PLAYER.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if root then root.Position else nil
end

-- Deterministic per-stalk variation. Derived from the id rather than math.random
-- so a stalk that streams out and back in resumes the same sway character
-- instead of visibly re-rolling.
local function _hash01(id: number, salt: number): number
	local x = math.sin(id * 12.9898 + salt * 78.233) * 43758.5453
	return x - math.floor(x)
end

-- Peak sway angle for one stalk, folding in rarity shape and growth stage.
local function _swayAmplitude(rarityId: string, stage: number, amplitudeMul: number): number
	local rarity = Bamboo.Rarity.Get(rarityId)

	-- Taller bends more, thicker bends less. A Thick is a fence post; a Tall is
	-- a fishing rod.
	local height = 1 + (rarity.heightScale - 1) * SWAY.HeightInfluence
	local stiffness = rarity.thicknessScale ^ SWAY.ThicknessStiffness
	local amplitude = SWAY.MaxRadians * height / math.max(stiffness, 0.01) * amplitudeMul

	if stage == Bamboo.Field.Stage.Shoot then
		return amplitude * SWAY.ShootAmplitude
	elseif stage == Bamboo.Field.Stage.Young then
		return amplitude * SWAY.YoungAmplitude
	end
	return amplitude
end

-- Recomputes the rest pivot after anything changes the stalk's scale. ApplyScale
-- rewrites every part from the slot frame, so the pivot moves with it.
local function _syncPivot(entry: Entry)
	local model = entry.Model
	if not model.Parent then
		return
	end
	-- Read the pivot while the stalk is in its *unrotated* laid-out state, which
	-- is exactly what ApplyScale just produced.
	entry.PivotFromFoot = entry.Slot:ToObjectSpace(model:GetPivot())
end

local function _unbindIfIdle()
	if _count <= 0 and _bound then
		RunService:UnbindFromRenderStep(POSE_BIND)
		_bound = false
	end
end

local _frameUpdate: (dt: number) -> ()

local function _bindIfNeeded()
	if _bound or _count <= 0 then
		return
	end
	_bound = true
	-- Deliberately one step *after* BambooGrowthController's bind (Character + 1).
	-- Its growth pass calls BambooModel.ApplyScale, which relays every part from
	-- the slot frame and would wipe this module's rotation if it ran second. Scale
	-- first, then pose, every frame.
	RunService:BindToRenderStep(POSE_BIND, Enum.RenderPriority.Character.Value + 2, _frameUpdate)
end

-- ── registration ─────────────────────────────────────────────────────────────

--[[
	Starts posing a stalk. Safe to call again for the same model; the later call
	only refreshes the slot and stage.
	@param model Model The rendered stalk.
	@param id number Stalk id, used as the seed for its sway character.
	@param slot CFrame Ground frame the stalk was planted on — its rest pose.
	@param rarityId string Rarity id, which sets how much the stalk bends.
	@param stage number A Bamboo.Field.Stage value.
	@param scale number Current growth scale (1 for a mature stalk).
]]
function StalkPose.Register(model: Model, id: number, slot: CFrame, rarityId: string, stage: number, scale: number)
	local existing = _entries[model]
	if existing then
		existing.Slot = slot
		existing.Stage = stage
		existing.Scale = scale
		existing.SwayAmplitude = _swayAmplitude(rarityId, stage, existing.AmplitudeMul)
		_syncPivot(existing)
		return
	end

	local frequencyMul = 1 + (_hash01(id, 1) * 2 - 1) * SWAY.FrequencyJitter
	local amplitudeMul = 1 + (_hash01(id, 2) * 2 - 1) * SWAY.AmplitudeJitter

	local entry: Entry = {
		Model = model,
		Slot = slot,
		PivotFromFoot = CFrame.identity,
		Scale = scale,
		Stage = stage,
		Phase = _hash01(id, 3) * math.pi * 2,
		FrequencyMul = frequencyMul,
		AmplitudeMul = amplitudeMul,
		SwayAmplitude = _swayAmplitude(rarityId, stage, amplitudeMul),
		Recoil = nil,
		RecoilAxis = Vector3.xAxis,
		Pop = nil,
		Topple = nil,
	}
	_syncPivot(entry)

	_entries[model] = entry
	table.insert(_order, model)
	_count += 1
	_bindIfNeeded()
end

--[[
	Stops posing a stalk and drops every reference to it.
	Must be called before the model is destroyed, or the pose loop keeps a dead
	model alive in its table until the next sweep notices the missing parent.
	@param model Model The stalk to release.
]]
function StalkPose.Unregister(model: Model)
	if not _entries[model] then
		return
	end
	_entries[model] = nil
	_count -= 1

	local index = table.find(_order, model)
	if index then
		table.remove(_order, index)
		if _cursor > index then
			_cursor -= 1
		end
	end
	_unbindIfIdle()
end

--[[
	Tells the poser a stalk was rescaled or changed stage by the growth pass.
	@param model Model The stalk.
	@param stage number Its new stage.
	@param scale number Its new growth scale.
	@param rarityId string Rarity id, so the sway amplitude can follow the stage.
]]
function StalkPose.SyncGrowth(model: Model, stage: number, scale: number, rarityId: string)
	local entry = _entries[model]
	if not entry then
		return
	end
	entry.Stage = stage
	entry.Scale = scale
	entry.SwayAmplitude = _swayAmplitude(rarityId, stage, entry.AmplitudeMul)
	_syncPivot(entry)
end

-- ── effects ──────────────────────────────────────────────────────────────────

--[[
	Kicks a stalk away from an impact. Re-hitting mid-recoil adds to the running
	spring rather than restarting it, so a fast rotor reads as sustained rattling.
	@param model Model The stalk that was struck.
	@param from Vector3 Where the swing came from; the stalk bends away from it.
	@param force number Impact strength; scaled by damage and rarity weight.
	@param maxRadians number Peak bend at force 1.
]]
function StalkPose.Impulse(model: Model, from: Vector3, force: number, maxRadians: number)
	local entry = _entries[model]
	if not entry then
		return
	end

	local away = entry.Slot.Position - from
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude < 0.05 then
		away = Vector3.xAxis
	end
	away = away.Unit
	-- Bending *away* from the impact is a rotation about the perpendicular axis
	-- on the ground plane.
	entry.RecoilAxis = Vector3.new(-away.Z, 0, away.X)

	if not entry.Recoil then
		entry.Recoil = Spring.new(0, HIT.SmoothTime)
	end
	entry.Recoil:Impulse(maxRadians * math.clamp(force, 0.5, 2.2))
	_bindIfNeeded()
end

--[[
	Punches a stalk's scale when it crosses a growth stage, so arriving at Mature
	is something the eye catches in the periphery.
	@param model Model The stalk.
	@param stage number The stage just entered.
]]
function StalkPose.Pop(model: Model, stage: number)
	if not FeelConfig.Enabled.GrowthPop then
		return
	end
	local entry = _entries[model]
	if not entry then
		return
	end

	local overshoot = POP.MatureScale
	if stage == Bamboo.Field.Stage.Shoot then
		overshoot = POP.ShootScale
	elseif stage == Bamboo.Field.Stage.Young then
		overshoot = POP.YoungScale
	end

	local pop = entry.Pop
	if not pop then
		pop = { Spring = Spring.new(0, POP.SmoothTime) }
		entry.Pop = pop
	end
	(pop :: PopState).Spring:Impulse(overshoot)
	_bindIfNeeded()
end

--[[
	Fells a stalk: it twists and falls at its foot rather than fading upright.
	The pose is held once the fall finishes — the growth controller destroys the
	corpse shortly after, and snapping back upright first would undo the read.
	@param model Model The stalk being felled.
	@param from Vector3 Where the swing came from; the stalk falls away from it.
	@param rarityId string Rarity id, which sets fall weight and duration.
	@return number Seconds the fall will take.
]]
function StalkPose.Topple(model: Model, from: Vector3, rarityId: string): number
	local entry = _entries[model]
	if not entry or not FeelConfig.Enabled.Topple then
		return 0
	end

	local tuning = TOPPLE.Rarity[rarityId] or TOPPLE.Rarity.Normal

	local away = entry.Slot.Position - from
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude < 0.05 then
		away = Vector3.xAxis
	end
	away = away.Unit

	local duration = TOPPLE.Seconds * tuning.time
	entry.Topple = {
		StartedAt = os.clock(),
		Duration = duration,
		Axis = Vector3.new(-away.Z, 0, away.X),
		FallRadians = TOPPLE.FallRadians * tuning.bend,
		TwistRadians = TOPPLE.TwistRadians * (if _hash01(entry.Phase * 1000, 4) > 0.5 then 1 else -1),
		BounceRadians = TOPPLE.BounceRadians * tuning.bounce,
		BounceFraction = TOPPLE.BounceFraction,
	}
	-- A falling stalk has stopped being a swaying one.
	entry.Recoil = nil
	_bindIfNeeded()
	return duration
end

--[[
	Whether a stalk is currently mid-topple, so callers can avoid restarting it.
	@param model Model The stalk.
	@return boolean True while the fall animation is running.
]]
function StalkPose.IsToppling(model: Model): boolean
	local entry = _entries[model]
	return entry ~= nil and entry.Topple ~= nil
end

-- ── frame ────────────────────────────────────────────────────────────────────

-- Applies the pop's scale punch. Returns true while the pop is still running.
local function _updatePop(entry: Entry, dt: number): boolean
	local pop = entry.Pop
	if not pop then
		return false
	end

	local overshoot = pop.Spring:Update(dt)
	if math.abs(overshoot) < POP.RestEpsilon and math.abs(pop.Spring.Velocity) < POP.RestEpsilon then
		-- Land exactly on the growth scale so repeated pops never leave the stalk
		-- a fraction of a percent bigger than it should be.
		BambooModel.ApplyScale(entry.Model, entry.Scale, entry.Slot)
		entry.Pop = nil
		_syncPivot(entry)
		return false
	end

	BambooModel.ApplyScale(entry.Model, entry.Scale * (1 + overshoot), entry.Slot)
	-- ApplyScale relaid every part from the slot, so the rest pivot moved with it.
	_syncPivot(entry)
	return true
end

-- Rotation of the ground frame from the topple, or nil once the fall is done and
-- the final pose has been written.
local function _toppleRotation(entry: Entry, now: number): CFrame?
	local topple = entry.Topple
	if not topple then
		return nil
	end

	local t = math.clamp((now - topple.StartedAt) / topple.Duration, 0, 1)

	-- Accelerating fall: a stalk tips slowly then goes over, which is the whole
	-- difference between "felled" and "rotated 72 degrees".
	local fall = t * t
	local angle = topple.FallRadians * fall

	-- Ground impact: the last stretch of the fall overshoots and settles back,
	-- so the stalk lands rather than arriving.
	if t > 1 - topple.BounceFraction then
		local bounceT = (t - (1 - topple.BounceFraction)) / topple.BounceFraction
		angle += math.sin(bounceT * math.pi) * topple.BounceRadians
	end

	local twist = topple.TwistRadians * fall
	return CFrame.fromAxisAngle(topple.Axis, angle) * CFrame.Angles(0, twist, 0)
end

-- Full pose for one entry. `swayNow` is false for stalks the round-robin budget
-- skipped this frame, which keeps their existing sway pose rather than snapping
-- them upright.
local function _poseEntry(entry: Entry, now: number, dt: number, swayNow: boolean): boolean
	local model = entry.Model
	if not model.Parent then
		return false
	end

	local busy = false

	-- Scale first: ApplyScale rewrites parts from the slot frame and would wipe
	-- any rotation, so the pivot pass has to come after it.
	if _updatePop(entry, dt) then
		busy = true
	end

	local rotation = CFrame.identity

	local topple = _toppleRotation(entry, now)
	if topple then
		rotation *= topple
		if now - (entry.Topple :: ToppleState).StartedAt >= (entry.Topple :: ToppleState).Duration then
			-- Write the final fallen pose once, then stop spending frames on it.
			entry.Topple = nil
		else
			busy = true
		end
	else
		local recoil = entry.Recoil
		if recoil then
			local bend = recoil:Update(dt)
			if math.abs(bend) < HIT.RestEpsilon and math.abs(recoil.Velocity) < HIT.RestEpsilon then
				entry.Recoil = nil
			else
				rotation *= CFrame.fromAxisAngle(entry.RecoilAxis, bend)
				busy = true
			end
		end

		if swayNow and FeelConfig.Enabled.Sway and entry.SwayAmplitude > 0 then
			local t = now * SWAY.BaseFrequency * entry.FrequencyMul + entry.Phase
			-- Two incommensurate sines on perpendicular axes, so the stalk traces a
			-- slow figure-eight instead of a visible back-and-forth loop.
			local primary = math.sin(t)
			local secondary = math.sin(now * SWAY.SecondaryFrequency * entry.FrequencyMul + entry.Phase * 1.7)
			local amplitude = entry.SwayAmplitude
			rotation *= CFrame.Angles(primary * amplitude, 0, secondary * amplitude * SWAY.SecondaryRatio)
		end
	end

	model:PivotTo(entry.Slot * rotation * entry.PivotFromFoot)
	return busy
end

function _frameUpdate(dt: number)
	local now = os.clock()
	local observer = _observerPosition()
	local budget = SWAY.BudgetPerFrame
	local total = #_order

	if total == 0 then
		_unbindIfIdle()
		return
	end

	if _cursor > total then
		_cursor = 1
	end

	-- Walk the whole field once: every entry gets its non-sway effects resolved
	-- (those are rare and must run at full rate), but only `budget` of them get a
	-- fresh sway sample per frame.
	local index = 1
	local swayIssued = 0
	while index <= total do
		local model = _order[index]
		local entry = _entries[model]

		if not entry or not model.Parent then
			-- Dead entry: drop it here rather than leaving it for a separate sweep.
			if entry then
				_entries[model] = nil
				_count -= 1
			end
			table.remove(_order, index)
			total -= 1
			if _cursor > index then
				_cursor -= 1
			end
			continue
		end

		local active = entry.Recoil ~= nil or entry.Pop ~= nil or entry.Topple ~= nil

		local inRange = false
		if observer then
			local offset = entry.Slot.Position - observer
			inRange = offset.X * offset.X + offset.Y * offset.Y + offset.Z * offset.Z <= SWAY.RadiusSq
		end

		local wantsSway = inRange and swayIssued < budget and _cursor <= index
		if wantsSway then
			swayIssued += 1
		end

		if active or wantsSway then
			_poseEntry(entry, now, dt, wantsSway)
		end

		index += 1
	end

	_cursor += swayIssued
	if _cursor > total then
		_cursor = 1
	end

	_unbindIfIdle()
end

--[[
	Drops every registered stalk. Used when a field streams out, so a plot the
	player walked away from does not keep entries alive.
	@param predicate ((Model) -> boolean)? Optional filter; nil clears everything.
]]
function StalkPose.Clear(predicate: ((Model) -> boolean)?)
	for index = #_order, 1, -1 do
		local model = _order[index]
		if not predicate or predicate(model) then
			_entries[model] = nil
			_count -= 1
			table.remove(_order, index)
		end
	end
	_cursor = 1
	_unbindIfIdle()
end

--[[
	How many stalks are being posed, for the performance overlay.
	@return number Registered stalk count.
]]
function StalkPose.GetCount(): number
	return _count
end

return StalkPose
