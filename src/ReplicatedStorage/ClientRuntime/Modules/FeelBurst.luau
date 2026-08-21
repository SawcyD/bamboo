--!strict
-- Short-lived world bursts: wood chips, ground dust, mutation shards, and the
-- expanding rings used by reveals and combo milestones.
--
-- Two rules hold throughout:
--
--   * Nothing here is ever parented to a live stalk. A stalk can be destroyed by
--     the growth controller at any moment, and a burst that lived on it would be
--     cut off mid-emit. Bursts are anchored at a world position instead.
--   * Emitter parts come from a pool and go back on a timer, so a sustained
--     harvest reuses a dozen parts rather than churning Instance.new/Destroy at
--     the swing rate.
--
-- Particle counts are capped per swing by the caller via `Budget`, so a 20-target
-- multi-hit costs roughly what a 4-target one does.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local ObjectPool = Core:Get("ObjectPool")

local FeelConfig = require(script.Parent.Parent:WaitForChild("Configs"):WaitForChild("FeelConfig"))

local FeelBurst = {}

local BURST = FeelConfig.Burst
local REVEAL = FeelConfig.Reveal

local _folder: Folder? = nil
local _emitterPool: any = nil
local _ringPool: any = nil

-- ── infrastructure ───────────────────────────────────────────────────────────

local function _effectsFolder(): Folder
	local existing = _folder
	if existing and existing.Parent then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "BambooFeelBursts"
	folder.Parent = workspace
	_folder = folder
	return folder
end

-- One reusable anchored host per burst. The ParticleEmitter is created fresh on
-- each use and destroyed on return: emitter properties differ wildly between a
-- chip burst and an Ancient reveal, and resetting ten sequence properties costs
-- more than making one emitter.
local function _emitterPart(): Part
	local pool = _emitterPool
	if not pool then
		pool = ObjectPool.new(function()
			local part = Instance.new("Part")
			part.Name = "BurstHost"
			part.Size = Vector3.one
			part.Transparency = 1
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			return part
		end, {
			initial = BURST.PoolInitial,
			max = BURST.PoolMax,
			parent = _effectsFolder(),
			onReturn = function(part: Part)
				-- Clear the previous burst's emitter so a reused host never
				-- inherits the last effect's particles.
				for _, child in part:GetChildren() do
					child:Destroy()
				end
			end,
		})
		_emitterPool = pool
	end
	return pool:GetFor(BURST.PartLifetime)
end

local function _ringPart(): Part
	local pool = _ringPool
	if not pool then
		pool = ObjectPool.new(function()
			local part = Instance.new("Part")
			part.Name = "BurstRing"
			part.Shape = Enum.PartType.Cylinder
			part.Material = Enum.Material.Neon
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			return part
		end, { initial = 2, max = 8, parent = _effectsFolder() })
		_ringPool = pool
	end
	return pool:Get()
end

local function _returnRing(part: Part)
	if _ringPool then
		_ringPool:Return(part)
	end
end

-- ── bursts ───────────────────────────────────────────────────────────────────

export type BurstStyle = {
	Color: Color3,
	Count: number,
	Size: number,
	Speed: NumberRange,
	Lifetime: NumberRange,
	Gravity: number,
	LightEmission: number?,
}

--[[
	Emits one short burst at a world position.
	@param position Vector3 Where the burst happens.
	@param style BurstStyle Colour, count, and physics of the particles.
]]
function FeelBurst.Emit(position: Vector3, style: BurstStyle)
	if style.Count <= 0 then
		return
	end

	local part = _emitterPart()
	part.Position = position

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(style.Color)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, style.Size),
		-- Shrinking out is what stops a burst leaving a lingering haze.
		NumberSequenceKeypoint.new(1, style.Size * 0.15),
	})
	emitter.Lifetime = style.Lifetime
	emitter.Speed = style.Speed
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-260, 260)
	emitter.Acceleration = Vector3.new(0, style.Gravity, 0)
	emitter.LightEmission = style.LightEmission or 0
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Enabled = false
	emitter.Parent = part
	emitter:Emit(style.Count)
end

--[[
	Wood chips flying off a struck stalk.
	@param position Vector3 Impact point.
	@param color Color3 Stalk colour, so chips match the bamboo they came from.
	@param intensity number Multiplier on count and speed (rarity/damage weight).
	@param budget number? Hard cap on particles for this call.
]]
function FeelBurst.Chips(position: Vector3, color: Color3, intensity: number, budget: number?)
	local chip = BURST.Chip
	local count = math.floor(chip.Count * intensity)
	if budget then
		count = math.min(count, budget)
	end

	FeelBurst.Emit(position, {
		Color = color,
		Count = count,
		Size = chip.Size * math.min(intensity, 2),
		Speed = NumberRange.new(chip.Speed.Min * intensity, chip.Speed.Max * intensity),
		Lifetime = chip.Lifetime,
		Gravity = chip.Gravity,
	})
end

--[[
	Ground dust where a felled stalk lands.
	@param position Vector3 Foot of the stalk.
	@param intensity number Multiplier on count and size (rarity weight).
	@param budget number? Hard cap on particles for this call.
]]
function FeelBurst.Dust(position: Vector3, intensity: number, budget: number?)
	local dust = BURST.Dust
	local count = math.floor(dust.Count * intensity)
	if budget then
		count = math.min(count, budget)
	end

	FeelBurst.Emit(position + Vector3.new(0, 0.4, 0), {
		Color = dust.Color,
		Count = count,
		Size = dust.Size * math.min(intensity, 2.5),
		Speed = dust.Speed,
		Lifetime = dust.Lifetime,
		Gravity = dust.Gravity,
	})
end

--[[
	An expanding ground ring. One part rather than an emitter, which makes it the
	cheapest "something happened here" read available and keeps it legible on a
	phone at distance.
	@param position Vector3 Centre of the ring, at ground level.
	@param color Color3 Ring colour.
	@param seconds number How long the ring takes to expand and fade.
	@param startDiameter number Diameter at t=0.
	@param endDiameter number Diameter at t=1.
	@param thickness number Ring thickness in studs.
]]
function FeelBurst.Ring(
	position: Vector3,
	color: Color3,
	seconds: number,
	startDiameter: number,
	endDiameter: number,
	thickness: number
)
	local ring = _ringPart()
	ring.Color = color
	ring.Transparency = 0.15
	-- Cylinders extend along their X axis, so the disc is laid flat by rotating
	-- 90 degrees about Z.
	ring.CFrame = CFrame.new(position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Size = Vector3.new(thickness, startDiameter, startDiameter)

	-- A ring is nothing but Size and Transparency over time, so it is a pure
	-- tween: no per-frame callback, and easing out makes it leap then coast,
	-- which is what reads as a shockwave rather than a growing circle.
	local tween = TweenService:Create(ring, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(thickness, endDiameter, endDiameter),
		Transparency = 1,
	})
	tween.Completed:Once(function()
		_returnRing(ring)
	end)
	tween:Play()
end

--[[
	The break burst for a rare mutation. Quiet mutations get nothing; Crystal and
	above get shards, and the rarest also get a ring.
	@param position Vector3 Where the stalk stood.
	@param mutation table A Bamboo.Mutations definition.
	@param budget number? Hard cap on particles for this call.
	@return boolean True when a reveal was actually played.
]]
function FeelBurst.Reveal(position: Vector3, mutation: any, budget: number?): boolean
	if not FeelConfig.Enabled.RarityBurst then
		return false
	end
	local weight = mutation.revealWeight or 1
	if weight < REVEAL.MinRevealWeight then
		return false
	end

	local count = math.floor(REVEAL.BaseCount * (weight / REVEAL.MinRevealWeight))
	if budget then
		count = math.min(count, budget)
	end

	FeelBurst.Emit(position + Vector3.new(0, 2.5, 0), {
		Color = mutation.color,
		Count = count,
		Size = REVEAL.Size * math.min(weight / REVEAL.MinRevealWeight, 2),
		Speed = REVEAL.Speed,
		Lifetime = REVEAL.Lifetime,
		-- Shards hang rather than fall: the find should read as light, not debris.
		Gravity = -6,
		LightEmission = 1,
	})

	if weight >= REVEAL.RingMinRevealWeight then
		local ringCfg = REVEAL.Ring
		FeelBurst.Ring(
			position,
			mutation.color,
			ringCfg.Seconds,
			ringCfg.StartDiameter,
			ringCfg.EndDiameter,
			ringCfg.Thickness
		)
	end

	return true
end

return FeelBurst
