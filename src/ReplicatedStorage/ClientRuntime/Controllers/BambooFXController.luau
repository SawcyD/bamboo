--!strict
-- Everything the player *feels* when bamboo is cut: impact reactions, leaf
-- bursts, combined camera shake, an FOV punch, and reward numbers.
--
-- All of it is driven by a single SwingResult packet per swing. Breaks resolve
-- as a staggered run (nearest first, then chain hops) so a wide sweep reads as
-- crack-crack-crack instead of one simultaneous thud.
--
-- The break itself is not handled here. A confirmed break hands the stalk to
-- SegmentCascade, which takes it apart joint by joint and owns the whole payoff
-- from that point: dust, the rare-mutation reveal, the finale sting, and the
-- reward fragments. This controller keeps only the screen-level reactions —
-- shake, flare, FOV, and the floating number — plus the fallback for a packet
-- that arrives after the stalk model is already gone.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Audio = require(ReplicatedStorage:WaitForChild("Audio"))
local Bamboo = Core:GetDomain("Bamboo")
local FlashPool = Core:Get("FlashPool")
local Orbify = Core:Get("Orbify")
local Relay = Core:GetShared("Network")
local Shake = Core:GetPackage("Shake")
local AntiCheat = require(script.Parent:WaitForChild("AntiCheatController"))

local ClientModules = script.Parent.Parent:WaitForChild("Modules")
local StalkPose = require(ClientModules:WaitForChild("StalkPose"))
local FeelBurst = require(ClientModules:WaitForChild("FeelBurst"))
local SegmentCascade = require(ClientModules:WaitForChild("SegmentCascade"))
local FeelConfig = require(script.Parent.Parent:WaitForChild("Configs"):WaitForChild("FeelConfig"))

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

-- ── stalk pose ───────────────────────────────────────────────────────────────
--
-- Stalk recoil used to live here, with its own frame loop and its own rest pose
-- sampled via `model:GetPivot()`. It moved to the shared StalkPose module when
-- idle sway landed: sway and recoil both want to write a stalk's transform, and
-- a recoil that samples its rest pose from a *swaying* stalk adopts the swayed
-- pose as upright and drifts a little further on every hit. StalkPose owns the
-- transform instead, and rotates the plot's slot frame, which cannot drift.

local HIT = FeelConfig.StalkHit

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
	FlashPool.Flash(model, rarity.color:Lerp(Color3.new(1, 1, 1), 0.72 + damageFrac * 0.2), HIT.FlashSeconds)
	StalkPose.Impulse(model, origin, rarity.impactWeight * (1 + damageFrac * 0.6), HIT.MaxRadians)
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

	-- Shared particle allowance for this entire swing packet. A 20-target
	-- multi-hit has to cost about what a 4-target one does, so the budget is
	-- spent down across every stalk rather than reset per stalk.
	local particleBudget = FeelConfig.Burst.MaxParticlesPerSwing
	local function spend(amount: number): number
		local granted = math.max(math.min(amount, particleBudget), 0)
		particleBudget -= granted
		return granted
	end

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
			-- Stalks felled by the same swing start their cascades a beat apart, so
			-- a wide sweep reads as a run of stalks coming down rather than one
			-- wall of noise.
			local stalkStagger = (breakSlot - 1) * FeelConfig.Cascade.StalkStagger

			task.delay((breakSlot - 1) * BREAK_STAGGER_SECONDS, function()
				_burstLeaves(position, breakColor, rarity.impactWeight * mutation.revealWeight * 1.4)

				local model = _findStalkModel(folder, hit.id)
				local ran = false
				if model then
					-- The stalk breaks upward through its joints. The cascade owns
					-- the whole payoff from here: dust, the rare reveal, the finale
					-- sting, and the reward fragments.
					ran = SegmentCascade.Run({
						Model = model,
						Position = position,
						Origin = origin,
						Rarity = rarity,
						Mutation = mutation,
						-- nil when the bag was full: the stalk still breaks, it
						-- just has nothing to send home.
						Target = if collected > 0 then root else nil,
						StartDelay = stalkStagger,
					})
				end

				if not ran and not model then
					-- No model to break — the packet arrived after the corpse was
					-- already destroyed. Fall back to loose debris so the break is
					-- never silent.
					FeelBurst.Dust(position, rarity.impactWeight, spend(FeelConfig.Burst.Dust.Count))
					FeelBurst.Reveal(position, mutation, spend(FeelConfig.Reveal.BaseCount))
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
			-- Wood chips off the cut face. Scaled by how beaten the stalk already
			-- is, so the last hit before a break throws the most.
			FeelBurst.Chips(
				position + Vector3.new(0, 3, 0),
				breakColor,
				rarity.impactWeight * (0.6 + damageFrac),
				spend(FeelConfig.Burst.Chip.Count)
			)
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
