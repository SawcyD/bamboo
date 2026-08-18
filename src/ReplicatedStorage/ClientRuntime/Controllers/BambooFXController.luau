--!strict
-- Everything the player *feels* when bamboo is cut: impact reactions, severing
-- the stalk into anchored visual chunks, leaf bursts, combined camera shake, an FOV
-- punch, reward numbers, and the curved flight of collected pieces.
--
-- All of it is driven by a single SwingResult packet per swing. Breaks resolve
-- as a staggered cascade (nearest first, then chain hops), each one severing the
-- real model rather than popping a generic orb, so a wide sweep reads as
-- crack-crack-crack instead of one simultaneous thud.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Audio = require(ReplicatedStorage:WaitForChild("Audio"))
local Bamboo = Core:GetDomain("Bamboo")
local FlashPool = Core:Get("FlashPool")
local Orbify = Core:Get("Orbify")
local Spring = Core:GetPackage("Spring")
local Relay = Core:GetShared("Network")
local Shake = Core:GetPackage("Shake")
local AntiCheat = require(script.Parent:WaitForChild("AntiCheatController"))

local BambooFXController = {}
local Framework

local LOCAL_PLAYER = Players.LocalPlayer
local SHAKE_BIND = "BambooCameraShake"

local DEBRIS_SECTIONS = 3
local COLLECT_ARC_HEIGHT = 6
-- Whole-tone ladder for the collection pop, and how long a streak survives.
local COLLECT_LADDER_STEPS = 6
local COLLECT_STREAK_WINDOW = 1.2
local REWARD_LABEL_SECONDS = 0.9

-- ── severing ────────────────────────────────────────────────────────────────
-- A broken stalk is cut in half: the top portion detaches and flies off as
-- anchored visual chunks (reusing the real segments, so rarity colour and material
-- already match), while the stub lingers with a pale cut cap and fades before
-- the server corpse is destroyed.
local SEVER_CUT_FRACTION = 0.55
local SEVER_CHUNK_LIFETIME = 1.8
local SEVER_FADE_SECONDS = 0.35
local SEVER_MIN_SPEED = 9
local SEVER_MAX_SPEED = 15
local SEVER_UP_SPEED = 12
local SEVER_CAP_COLOR = Color3.fromRGB(224, 232, 188)
-- Gap between one break in a cascade and the next.
local BREAK_STAGGER_SECONDS = 0.055
-- FOV punch: a fast zoom-kick that reads as impact without stopping time.
local FOV_PUNCH_DECAY = 16
local FOV_PUNCH_MAX = 5

-- One shake instance is reused for every break. Sustained forever and driven by
-- Amplitude, so four stalks breaking together push one bigger shake instead of
-- stacking four separate ones.
local SHAKE_FREQUENCY = 12
local SHAKE_FADE_IN = 0.06
-- Amplitude decays toward zero at this rate per second.
local SHAKE_DECAY = 7
local MAX_SHAKE_AMPLITUDE = 0.9

local _shake = Shake.new()
local _shakeAmplitude = 0
local _fovPunch = 0
local _fovBase: number? = nil
local _effectsFolder: Folder

-- ── stalk recoil ─────────────────────────────────────────────────────────────
--
-- A struck stalk kicks away from the impact and springs back. One shared frame
-- loop drives every active recoil, so hitting eight stalks costs one loop and
-- eight table entries rather than eight threads and eight tweens.

local RECOIL_BIND = "BambooStalkRecoil"
-- Radians the stalk bends at full kick. Small: the read is "WHACK", not an
-- animation.
local RECOIL_MAX_RADIANS = math.rad(11)
local RECOIL_SMOOTH_TIME = 0.11
-- Below this the recoil is imperceptible and the entry is dropped.
local RECOIL_REST_EPSILON = 0.0015
-- Flash length, deliberately barely-there.
local HIT_FLASH_SECONDS = 0.1

type Recoil = {
	Model: Model,
	Base: CFrame,
	-- Bend axis in world space, perpendicular to the impact direction.
	Axis: Vector3,
	Spring: any,
}

local _recoils: { [Model]: Recoil } = {}
local _recoilCount = 0
local _recoilBound = false

-- ── camera shake ─────────────────────────────────────────────────────────────

-- Breaks add into the running amplitude rather than starting their own shake.
local function _addShake(amount: number)
	_shakeAmplitude = math.min(_shakeAmplitude + amount, MAX_SHAKE_AMPLITUDE)
end

local function _addFovPunch(amount: number)
	_fovPunch = math.min(_fovPunch + amount, FOV_PUNCH_MAX)
end

local function _startShake()
	_shake.FadeInTime = SHAKE_FADE_IN
	_shake.FadeOutTime = 0
	_shake.Frequency = SHAKE_FREQUENCY
	_shake.Amplitude = 0
	_shake.Sustain = true
	_shake.PositionInfluence = Vector3.new(0.35, 0.35, 0.1)
	_shake.RotationInfluence = Vector3.new(0.05, 0.05, 0.4)
	_shake:Start()

	local lastFrame = os.clock()
	_shake:BindToRenderStep(SHAKE_BIND, Enum.RenderPriority.Camera.Value + 1, function(position, rotation)
		local now = os.clock()
		local dt = now - lastFrame
		lastFrame = now

		local camera = workspace.CurrentCamera
		if not camera then
			return
		end

		-- FOV punch runs even while the shake is quiet. It zooms the camera in
		-- a hair and lets go, which reads as impact without stopping the game.
		-- Skipped while the UI zoom owns the camera, so the two never fight.
		local uiBlur = camera:FindFirstChild("UIBlurEffect") :: BlurEffect?
		local uiZooming = uiBlur ~= nil and uiBlur.Size > 0.5
		if _fovPunch > 0.001 and not uiZooming then
			if _fovBase == nil then
				_fovBase = camera.FieldOfView
			end
			camera.FieldOfView = _fovBase - _fovPunch
			_fovPunch *= math.exp(-FOV_PUNCH_DECAY * dt)
		else
			_fovPunch = 0
			if _fovBase ~= nil then
				camera.FieldOfView = _fovBase
				_fovBase = nil
			end
		end

		_shake.Amplitude = _shakeAmplitude
		if _shakeAmplitude <= 0.001 then
			_shakeAmplitude = 0
			return
		end

		camera.CFrame *= CFrame.new(position) * CFrame.Angles(rotation.X, rotation.Y, rotation.Z)
		_shakeAmplitude *= math.exp(-SHAKE_DECAY * dt)
	end)
end

-- ── impact flare ─────────────────────────────────────────────────────────────

-- Roblox has no time scale, so a true hit-stop is not available. A short
-- full-screen flare in the mutation's colour reads as the same beat: the break
-- lands, the screen answers, and the player never loses control.
local FLARE_SECONDS = 0.22
local _flare: Frame? = nil

local function _ensureFlare(): Frame
	local existing = _flare
	if existing and existing.Parent then
		return existing
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "BambooImpactFlare"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30
	gui.Parent = LOCAL_PLAYER:WaitForChild("PlayerGui")
	AntiCheat.Approve(gui)

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	-- Purely decorative and never blocks input, so it can sit over everything.
	frame.Active = false
	frame.Parent = gui

	local gradient = Instance.new("UIGradient")
	-- Bright at the edges, clear in the middle: a vignette flash rather than a
	-- white-out, so the bamboo stays visible through it.
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	gradient.Parent = frame

	_flare = frame
	return frame
end

--[[
	Flashes the screen edges for a headline break.
	@param color Color3 Mutation colour, so the flare matches what was found.
	@param strength number 0-1; scales how opaque the flare starts.
]]
local function _impactFlare(color: Color3, strength: number)
	local frame = _ensureFlare()
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 1 - math.clamp(strength, 0, 1) * 0.55

	TweenService:Create(frame, TweenInfo.new(FLARE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
end

-- ── particles ────────────────────────────────────────────────────────────────

local function _emitterPart(position: Vector3): Part
	local part = Instance.new("Part")
	part.Size = Vector3.one
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Position = position
	part.Parent = _effectsFolder
	Debris:AddItem(part, 3)
	return part
end

--[[
	Bursts leaf particles at a stalk.
	@param position Vector3 World position of the stalk being hit or broken.
	@param color Color3 Stalk colour, so leaves match the rarity.
	@param weight number Intensity multiplier (rarity weight x break-count weight).
]]
local function _burstLeaves(position: Vector3, color: Color3, weight: number)
	local part = _emitterPart(position + Vector3.new(0, 3, 0))

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new(0.35 * weight)
	emitter.Lifetime = NumberRange.new(0.5, 1.1)
	emitter.Speed = NumberRange.new(6 * weight, 12 * weight)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-220, 220)
	emitter.Acceleration = Vector3.new(0, -22, 0)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Enabled = false
	emitter.Parent = part
	emitter:Emit(math.floor(10 * weight))
end

-- ── collection ───────────────────────────────────────────────────────────────

-- Consecutive pieces absorbed; drives the rising collection chime. Resets
-- after a short gap so the ladder restarts instead of sitting at the top.
local _collectStreak = 0
local _collectStreakResetAt = 0

-- Rising musical ladder: each piece lands a step higher than the last.
local function _collectPitch(): number
	local now = os.clock()
	if now > _collectStreakResetAt then
		_collectStreak = 0
	end
	_collectStreakResetAt = now + COLLECT_STREAK_WINDOW

	local step = _collectStreak % COLLECT_LADDER_STEPS
	_collectStreak += 1
	-- Whole-tone steps, so the ladder is in tune rather than just "higher".
	return 2 ^ (step * 2 / 12)
end

-- Bright pop where a piece is absorbed, so every single unit lands visibly.
local function _absorbSparkle(position: Vector3, color: Color3)
	local part = _emitterPart(position)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color, Color3.fromRGB(255, 255, 220))
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Lifetime = NumberRange.new(0.2, 0.35)
	emitter.Speed = NumberRange.new(4, 9)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = 1
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Enabled = false
	emitter.Parent = part
	emitter:Emit(8)
end

-- ── breaking ─────────────────────────────────────────────────────────────────

--[[
	Severs a broken stalk in half. The top portion detaches and flies off as
	anchored visual chunks that reuse the real segment parts (so rarity colour and
	material already match), while the bottom stub fades in place behind a pale
	cut cap. The original top parts are hidden, not reparented, so the server's
	delayed corpse destroy never fights a client-side reparent.
	@param model Model The real stalk model (the server leaves it alive briefly).
	@param position Vector3 Where the stalk stood.
	@param origin Vector3 Where the swing came from; chunks fly away from it.
	@return number How many chunks were launched (0 if the model was missing).
]]
local function _severStalk(model: Model, position: Vector3, origin: Vector3): number
	local height = (model:GetAttribute("Height") :: number) or 0
	local diameter = (model:GetAttribute("Diameter") :: number) or 0.65
	local cutY = height * SEVER_CUT_FRACTION

	local away = Vector3.new(position.X - origin.X, 0, position.Z - origin.Z)
	if away.Magnitude < 0.05 then
		away = Vector3.xAxis
	end
	away = away.Unit

	-- The stalk's up direction, taken from its primary (bottom) segment, which
	-- is rotated so its local X points up the stalk. Carries the field's tilt.
	local primary = model.PrimaryPart
	local stalkUp = if primary then primary.CFrame.RightVector else Vector3.yAxis

	local chunkCount = 0
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end
		local offset = part:GetAttribute("BaseOffset") :: CFrame?
		if not offset then
			continue
		end

		if offset.Position.Y > cutY then
			-- Top half: clone first (so the copy keeps its colour), then hide the
			-- original in place and tween the copy. Anchored chunks avoid turning
			-- every break into a local physics assembly or a pile of collidable
			-- sideways parts on the ground.
			local chunk = part:Clone()
			part.Transparency = 1
			chunk.Anchored = true
			chunk.CanCollide = false
			chunk.CanQuery = false
			chunk.CanTouch = false
			chunk.CastShadow = false
			chunk.Parent = _effectsFolder

			local travel = SEVER_MIN_SPEED + math.random() * (SEVER_MAX_SPEED - SEVER_MIN_SPEED)
			local targetPosition = chunk.Position + away * travel * 0.22 + Vector3.new(0, SEVER_UP_SPEED * 0.12 - 3, 0)
			local targetCFrame = CFrame.new(targetPosition)
				* chunk.CFrame.Rotation
				* CFrame.Angles(math.random() * 5 - 2.5, math.random() * 5 - 2.5, math.random() * 5 - 2.5)
			TweenService:Create(
				chunk,
				TweenInfo.new(SEVER_CHUNK_LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ CFrame = targetCFrame, Transparency = 1 }
			):Play()
			Debris:AddItem(chunk, SEVER_CHUNK_LIFETIME)
			chunkCount += 1
		else
			-- Stub: fade it so the server corpse removal lands invisibly.
			TweenService
				:Create(part, TweenInfo.new(SEVER_FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Transparency = 1,
				})
				:Play()
		end
	end

	-- Pale cut cap at the cut line, tilted with the stalk. Maps world X onto the
	-- stalk's up axis so the cylinder disc sits flat across the cut face.
	local capPos = model:GetPivot().Position + stalkUp * cutY
	local capAxis = Vector3.new(1, 0, 0):Cross(stalkUp)
	local capAngle = math.acos(math.clamp(stalkUp.X, -1, 1))
	local capRotation = if capAxis.Magnitude < 1e-3
		then CFrame.identity
		else CFrame.fromAxisAngle(capAxis.Unit, capAngle)

	local cap = Instance.new("Part")
	cap.Name = "CutCap"
	cap.Shape = Enum.PartType.Cylinder
	cap.Size = Vector3.new(0.25, diameter * 1.05, diameter * 1.05)
	cap.Color = SEVER_CAP_COLOR
	cap.Material = Enum.Material.SmoothPlastic
	cap.Anchored = true
	cap.CanCollide = false
	cap.CanQuery = false
	cap.CanTouch = false
	cap.CastShadow = false
	cap.CFrame = CFrame.new(capPos) * capRotation
	cap.Parent = _effectsFolder
	Debris:AddItem(cap, SEVER_FADE_SECONDS + 0.15)
	TweenService:Create(cap, TweenInfo.new(SEVER_FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Transparency = 1,
	}):Play()

	return chunkCount
end

-- Streams the value of a broken stalk into the player as a run of orbs. Shared
-- by the sever path (real chunks fly off, a couple of orbs still fly home) and
-- the no-model fallback.
local function _collectIntoBag(position: Vector3, color: Color3, weight: number)
	local character = LOCAL_PLAYER.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	Orbify.Burst({
		Origin = position,
		Target = root,
		Count = DEBRIS_SECTIONS,
		Color = color,
		Size = Vector3.new(1.6, 0.6 * weight, 0.6 * weight),
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Grass,
		ArcHeight = COLLECT_ARC_HEIGHT,
		Parent = _effectsFolder,
		OnAbsorb = function(_index, _total, landed)
			_absorbSparkle(landed, color)
			-- The pop is the payoff; the ladder makes a group break a run of notes.
			Audio:Play("BambooPop", "SFX", { PlaybackSpeed = _collectPitch() })
		end,
	})
end

--[[
	Breaks a stalk into orbs that tumble, then stream into the player. Kept as the
	fallback for a packet that arrives after the server corpse is already gone.
	@param position Vector3 Where the stalk stood.
	@param color Color3 Stalk colour, so the orbs match the rarity.
	@param weight number Thickness scale, so a Thick stalk drops chunkier pieces.
	@param collected boolean False when the bag was full, so nothing flies home.
]]
local function _spawnDebris(position: Vector3, color: Color3, weight: number, collected: boolean)
	if not collected then
		-- Bag is full: the stalk still falls apart, it just isn't picked up.
		Orbify.Burst({
			Origin = position,
			Target = position,
			Count = DEBRIS_SECTIONS,
			Color = color,
			Size = Vector3.new(1.6, 0.6 * weight, 0.6 * weight),
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.Grass,
			Parent = _effectsFolder,
			FlightSeconds = 0,
			TumbleSeconds = 2.2,
		})
		return
	end

	_collectIntoBag(position, color, weight)
end

-- ── reward numbers ───────────────────────────────────────────────────────────

--[[
	Floats a reward number above the break.
	@param position Vector3 Centre of the stalks that broke.
	@param amount number Bamboo added to the bag.
	@param combo number Current combo, which tints and lifts the number.
	@param headline string? Rarity shout ("THICK!") appended for rare breaks.
]]
local function _floatReward(position: Vector3, amount: number, combo: number, headline: string?)
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Position = position + Vector3.new(0, 5, 0)
	anchor.Parent = _effectsFolder

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(1, 0.4)
	billboard.AlwaysOnTop = true
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = if headline then string.format("+%d  %s", amount, headline) else string.format("+%d Bamboo", amount)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextStrokeTransparency = 0.35
	-- Higher combo = hotter number, so the streak is readable at a glance.
	local heat = Bamboo.Combo.Heat(combo)
	label.TextColor3 = Color3.fromRGB(215, 255, 190):Lerp(Color3.fromRGB(255, 205, 90), heat)
	label.Parent = billboard

	-- Punch in from nothing so the number arrives with the break, not after it.
	local fullSize = UDim2.fromScale(6 + heat * 2, 2 + heat * 0.6)
	TweenService:Create(billboard, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = fullSize,
	}):Play()

	local rise = TweenService:Create(
		anchor,
		TweenInfo.new(REWARD_LABEL_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = anchor.Position + Vector3.new(0, 4 + heat * 2, 0) }
	)
	local fade = TweenService:Create(
		label,
		TweenInfo.new(REWARD_LABEL_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	)
	rise:Play()
	fade:Play()
	Debris:AddItem(anchor, REWARD_LABEL_SECONDS + 0.1)
end

-- ── swing result ─────────────────────────────────────────────────────────────

-- One frame loop for every active recoil. Only bound while something is
-- actually recoiling, so an idle field costs nothing.
local function _updateRecoils(dt: number)
	for model, recoil in _recoils do
		if not model.Parent then
			_recoils[model] = nil
			_recoilCount -= 1
			continue
		end

		local bend = recoil.Spring:Update(dt)
		if math.abs(bend) < RECOIL_REST_EPSILON and math.abs(recoil.Spring.Velocity) < RECOIL_REST_EPSILON then
			-- Snap exactly back to base, so repeated recoils never accumulate drift.
			model:PivotTo(recoil.Base)
			_recoils[model] = nil
			_recoilCount -= 1
			continue
		end

		model:PivotTo(recoil.Base * CFrame.fromAxisAngle(recoil.Axis, bend))
	end

	if _recoilCount <= 0 and _recoilBound then
		RunService:UnbindFromRenderStep(RECOIL_BIND)
		_recoilBound = false
	end
end

--[[
	Kicks a stalk away from an impact.
	Re-hitting a stalk mid-recoil adds to the existing spring rather than
	restarting it, so a fast rotor reads as sustained rattling.
	@param model Model The stalk that was struck.
	@param from Vector3 Where the hit came from; the stalk bends away from it.
	@param force number Impact strength, scaled by damage and rarity weight.
]]
local function _recoilStalk(model: Model, from: Vector3, force: number)
	local base = model:GetPivot()

	local away = model:GetPivot().Position - from
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude < 0.05 then
		away = Vector3.xAxis
	end
	away = away.Unit
	-- Bending *away* from the impact means rotating about the axis perpendicular
	-- to it, on the ground plane.
	local axis = Vector3.new(-away.Z, 0, away.X)

	local recoil = _recoils[model]
	if not recoil then
		recoil = {
			Model = model,
			-- Captured before the first kick, so it is always the upright pose.
			Base = base,
			Axis = axis,
			Spring = Spring.new(0, RECOIL_SMOOTH_TIME),
		}
		_recoils[model] = recoil
		_recoilCount += 1
	else
		recoil.Axis = axis
	end

	recoil.Spring:Impulse(RECOIL_MAX_RADIANS * math.clamp(force, 0.5, 2.2))

	if not _recoilBound then
		_recoilBound = true
		RunService:BindToRenderStep(RECOIL_BIND, Enum.RenderPriority.Character.Value + 1, _updateRecoils)
	end
end

-- Stalks in the local player's field, looked up once per swing rather than once
-- per hit.
local function _ownedStalkFolder(): Folder?
	local plots = workspace:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("OwnerUserId") == LOCAL_PLAYER.UserId then
			return plot:FindFirstChild("Bamboo") :: Folder?
		end
	end
	return nil
end

-- Finds a stalk model, tolerating the server's rename of a cut stalk to
-- "StalkCut<id>" before it destroys the corpse.
local function _findStalkModel(folder: Folder?, stalkId: number): Model?
	if not folder then
		return nil
	end
	return folder:FindFirstChild("Stalk" .. stalkId) :: Model? or folder:FindFirstChild("StalkCut" .. stalkId) :: Model?
end

--[[
	Full non-lethal hit reaction: flash, recoil, leaf puff.
	A stalk that survives still has to feel like the sickle connected with
	something, or a three-health stalk reads as two whiffs and a break.
	@param folder Folder? The local player's stalk folder, or nil if unavailable.
	@param stalkId number Which stalk was struck.
	@param origin Vector3 Where the swing came from.
	@param rarity table The stalk's rarity definition.
	@param damageFrac number 0-1; how much of its health is already gone. A
		stalk on its last legs whips harder and cracks deeper.
]]
local function _reactStalk(folder: Folder?, stalkId: number, origin: Vector3, rarity: any, damageFrac: number)
	if not folder then
		return
	end
	local model = _findStalkModel(folder, stalkId)
	if not model then
		return
	end

	-- Flash reads as impact first and rarity second: the stalk's colour is
	-- blended most of the way to white so a Thick hit still looks like a hit.
	-- The more beaten it is, the hotter the flash, so "almost down" shows.
	FlashPool.Flash(model, rarity.color:Lerp(Color3.new(1, 1, 1), 0.72 + damageFrac * 0.2), HIT_FLASH_SECONDS)
	_recoilStalk(model, origin, rarity.impactWeight * (1 + damageFrac * 0.6))
end

local function _onSwingResult(payload: any)
	local hits = payload.hits :: { any }
	local breaks = payload.breaks :: number
	local combo = payload.combo :: number
	local collected = payload.collected :: number

	-- One combined weight for the whole swing: more breaks reads as one bigger
	-- hit rather than several separate ones.
	local groupWeight = 1 + math.min(breaks, 6) * 0.28
	local comboPitch = Bamboo.Combo.Pitch(combo)

	local character = LOCAL_PLAYER.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local origin = if root then root.Position else Vector3.zero

	local peakRarityWeight = 1
	local peakRarityId = "Normal"
	-- Mutation is tracked separately from type: a Golden Normal deserves the
	-- headline even though its type is the commonest one.
	local peakMutationId = "None"
	local peakMutationWeight = 1
	local breakCentre = Vector3.zero
	local survivors = 0
	local survivorWeight = 0
	local maxDamageFrac = 0

	-- Resolved once per swing rather than once per hit.
	local folder = _ownedStalkFolder()

	local breakSlot = 0
	for _, hit in hits do
		local rarity = Bamboo.Rarity.Get(hit.rarity)
		local position = hit.position :: Vector3

		local mutation = Bamboo.Mutations.Get(hit.mutation)
		-- Mutated stalks shatter in their own colour, not bamboo green.
		local breakColor = if mutation.id == "None" then rarity.color else mutation.color

		if hit.broke then
			if rarity.impactWeight > peakRarityWeight then
				peakRarityWeight = rarity.impactWeight
				peakRarityId = rarity.id
			end
			if mutation.revealWeight > peakMutationWeight then
				peakMutationWeight = mutation.revealWeight
				peakMutationId = mutation.id
			end
			breakCentre += position
			breakSlot += 1

			-- Cascade: each break lands a beat after the last, so a multi-break
			-- sweep reads as a run of cracks rather than one simultaneous pop.
			task.delay((breakSlot - 1) * BREAK_STAGGER_SECONDS, function()
				_burstLeaves(position, breakColor, rarity.impactWeight * mutation.revealWeight * 1.4)
				local model = _findStalkModel(folder, hit.id)
				if model and _severStalk(model, position, origin) > 0 then
					-- The severed chunks carry the break; a short run of orbs
					-- still flies home to carry the reward.
					if collected > 0 then
						_collectIntoBag(position, breakColor, rarity.thicknessScale)
					end
				else
					_spawnDebris(position, breakColor, rarity.thicknessScale, collected > 0)
				end
			end)
		else
			survivors += 1
			survivorWeight = math.max(survivorWeight, rarity.impactWeight)
			local health = hit.health :: number
			local damageFrac = 1 - math.clamp(health / math.max(rarity.health, 1), 0, 1)
			maxDamageFrac = math.max(maxDamageFrac, damageFrac)
			-- Smaller puff than a break, so the two never get confused.
			_burstLeaves(position, breakColor, rarity.impactWeight * 0.5)
			_reactStalk(folder, hit.id, origin, rarity, damageFrac)
		end
	end

	-- Hits and breaks get separate sounds. Pitch rises with combo on both, and
	-- a hit that lands on several stalks is pitched down slightly so a wide
	-- sweep reads as heavier than a single tap. A beaten stalk cracks deeper.
	if survivors > 0 then
		Audio:Play("BambooHit", "SFX", {
			PlaybackSpeed = comboPitch * (1 - math.min(survivors, 5) * 0.02 - maxDamageFrac * 0.06),
		})
		-- A whisper of shake, so contact registers in the hand even when nothing
		-- breaks. Well below the smallest break.
		_addShake(0.02 * survivorWeight * math.min(survivors, 4))
	end

	if breaks > 0 then
		breakCentre /= breaks
		local isEvent = Bamboo.Mutations.IsEvent(peakMutationId)
		local soundName = if breaks >= 3 or peakRarityWeight >= 2 or isEvent then "BambooBreakBig" else "BambooBreak"
		Audio:PlayAt(soundName, breakCentre, "SFX", {
			-- A big mutation drops the pitch, so it reads as heavier rather than
			-- just louder.
			PlaybackSpeed = comboPitch / peakMutationWeight ^ 0.25,
		})
		_addShake(0.16 * groupWeight * peakRarityWeight * math.min(peakMutationWeight, 3))
		-- The zoom-kick is the hit-stop substitute; a bigger break punches harder.
		_addFovPunch(1.2 + math.min(breaks, 4) * 0.5 + (peakRarityWeight - 1) * 0.8)

		-- Crystal and above answer with a screen flare in their own colour, so a
		-- big find registers even if the stalk was off to the side.
		if isEvent then
			local mutation = Bamboo.Mutations.Get(peakMutationId)
			_impactFlare(mutation.color, math.min(peakMutationWeight / 6, 1))
		end

		if collected > 0 then
			-- The mutation shouts over the type, because it is the rarer find.
			local headline: string? = nil
			if peakMutationId ~= "None" then
				headline = string.upper(Bamboo.Mutations.Get(peakMutationId).name) .. "!"
			elseif peakRarityId ~= "Normal" then
				headline = string.upper(peakRarityId) .. "!"
			end
			_floatReward(breakCentre, collected, combo, headline)
		end
	end
end

-- Selling fires a handful of coin orbs from the player's feet up into the HUD
-- money counter, so the payout is something that arrives rather than a number
-- that changes.
local function _onSold(payload: any)
	if payload.amount <= 0 then
		return
	end

	Audio:Play("BambooSell", "SFX")
	_addShake(0.1)

	local HUD = Framework:GetController("BambooHUDController")
	local moneyLabel = HUD and HUD.GetMoneyLabel()
	local camera = workspace.CurrentCamera
	local character = LOCAL_PLAYER.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not moneyLabel or not camera or not root then
		return
	end

	local screenPoint, onScreen = camera:WorldToViewportPoint(root.Position)
	if not onScreen then
		return
	end

	Orbify.UIBurst({
		From = Vector2.new(screenPoint.X, screenPoint.Y),
		Target = moneyLabel,
		-- Cap the count so a big sale doesn't bury the screen in coins.
		Count = math.clamp(math.floor(payload.amount / 6), 4, 12),
		Color = Color3.fromRGB(255, 226, 130),
		OnAbsorb = function()
			Audio:Play("BambooCollect", "SFX", { PlaybackSpeed = _collectPitch() })
		end,
	})
end

-- ── lifecycle ────────────────────────────────────────────────────────────────

function BambooFXController:Start(fw: any)
	Framework = fw

	_effectsFolder = Instance.new("Folder")
	_effectsFolder.Name = "BambooEffects"
	_effectsFolder.Parent = workspace

	Relay.Bamboo.SwingResult.listen(_onSwingResult)
	Relay.Bamboo.Sold.listen(_onSold)

	_startShake()
end

return BambooFXController
