--!strict
-- Everything the player *feels* when bamboo is cut: impact reactions, breaking
-- debris, leaf bursts, combined camera shake, reward numbers, and the curved
-- flight of collected pieces.
--
-- All of it is driven by a single SwingResult packet per swing, so a swing that
-- breaks four stalks produces one combined shake and one combined sound weight
-- instead of four stacked ones.

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

		_shake.Amplitude = _shakeAmplitude
		if _shakeAmplitude <= 0.001 then
			_shakeAmplitude = 0
			return
		end

		camera.CFrame *= CFrame.new(position) * CFrame.Angles(rotation.X, rotation.Y, rotation.Z)
		_shakeAmplitude *= math.exp(-SHAKE_DECAY * dt)
	end)
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
	Breaks a stalk into orbs that tumble, then stream into the player.
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

--[[
	Full non-lethal hit reaction: flash, recoil, leaf puff.
	A stalk that survives still has to feel like the sickle connected with
	something, or a three-health stalk reads as two whiffs and a break.
	@param folder Folder? The local player's stalk folder, or nil if unavailable.
	@param stalkId number Which stalk was struck.
	@param origin Vector3 Where the swing came from.
	@param rarity table The stalk's rarity definition.
]]
local function _reactStalk(folder: Folder?, stalkId: number, origin: Vector3, rarity: any)
	if not folder then
		return
	end
	local model = folder:FindFirstChild("Stalk" .. stalkId) :: Model?
	if not model then
		return
	end

	-- Flash reads as impact first and rarity second: the stalk's colour is
	-- blended most of the way to white so a Thick hit still looks like a hit.
	FlashPool.Flash(model, rarity.color:Lerp(Color3.new(1, 1, 1), 0.72), HIT_FLASH_SECONDS)
	_recoilStalk(model, origin, rarity.impactWeight)
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
	local breakCentre = Vector3.zero
	local survivors = 0
	local survivorWeight = 0

	-- Resolved once per swing rather than once per hit.
	local folder = _ownedStalkFolder()

	for _, hit in hits do
		local rarity = Bamboo.Rarity.Get(hit.rarity)
		local position = hit.position :: Vector3

		if hit.broke then
			if rarity.impactWeight > peakRarityWeight then
				peakRarityWeight = rarity.impactWeight
				peakRarityId = rarity.id
			end
			breakCentre += position
			_burstLeaves(position, rarity.color, rarity.impactWeight * 1.4)
			_spawnDebris(position, rarity.color, rarity.thicknessScale, collected > 0)
		else
			survivors += 1
			survivorWeight = math.max(survivorWeight, rarity.impactWeight)
			-- Smaller puff than a break, so the two never get confused.
			_burstLeaves(position, rarity.color, rarity.impactWeight * 0.5)
			_reactStalk(folder, hit.id, origin, rarity)
		end
	end

	-- Hits and breaks get separate sounds. Pitch rises with combo on both, and
	-- a hit that lands on several stalks is pitched down slightly so a wide
	-- sweep reads as heavier than a single tap.
	if survivors > 0 then
		Audio:Play("BambooHit", "SFX", {
			PlaybackSpeed = comboPitch * (1 - math.min(survivors, 5) * 0.02),
		})
		-- A whisper of shake, so contact registers in the hand even when nothing
		-- breaks. Well below the smallest break.
		_addShake(0.02 * survivorWeight * math.min(survivors, 4))
	end

	if breaks > 0 then
		breakCentre /= breaks
		local soundName = if breaks >= 3 or peakRarityWeight >= 2 then "BambooBreakBig" else "BambooBreak"
		Audio:PlayAt(soundName, breakCentre, "SFX", { PlaybackSpeed = comboPitch })
		_addShake(0.16 * groupWeight * peakRarityWeight)

		if collected > 0 then
			-- Rare breaks shout their name; Normal ones stay quiet so the rare
			-- ones keep landing as events.
			local headline = if peakRarityId ~= "Normal" then string.upper(peakRarityId) .. "!" else nil
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
