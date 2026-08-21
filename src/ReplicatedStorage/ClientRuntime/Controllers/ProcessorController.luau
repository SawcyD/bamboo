--!strict
-- Presentation for the Raw Bamboo -> Straw processor: idle/active machine feel,
-- the deposit ProximityPrompt, deposit flight, and product pops.
--
-- Deposits are no longer automatic: the player carries bamboo from the
-- stockpile and triggers the processor's ProximityPrompt, which the server
-- resolves (CarriedBamboo -> ProcessorInput) and replicates back.
-- ProcessorInput is an ordinary top-level PlayerData key, exactly like
-- BambooStock and Money, so DataService pushes it to the owner automatically —
-- this controller only watches the replica and reacts, plus wires the prompt
-- itself. The prompt is a trust signal only; ProcessingService still validates
-- ownership and distance server-side.
--
-- Straw is sold the instant a batch completes (ProcessingService), straight
-- into PendingEarnings, so there is no output buffer or product stock to
-- represent here — only one pop per completed batch, timed off ProcessorInput
-- dropping by a full batch's worth.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Bamboo = Core:GetDomain("Bamboo")
local FlashPool = Core:Get("FlashPool")
local Orbify = Core:Get("Orbify")
local Spring = Core:GetPackage("Spring")
local Scheduler = Core:Get("Scheduler")
local Replica = Core:Get("Replica")
local Relay = Core:GetShared("Network")

local ClientModules = script.Parent.Parent:WaitForChild("Modules")
local FeelBurst = require(ClientModules:WaitForChild("FeelBurst"))
local FeelConfig = require(script.Parent.Parent:WaitForChild("Configs"):WaitForChild("FeelConfig"))

local ProcessorController = {}

local LOCAL_PLAYER = Players.LocalPlayer
local PROC = FeelConfig.Processor
local RENDER_BIND = "BambooProcessorFeel"

local _processor: BasePart? = nil
local _roller: BasePart? = nil
local _light: PointLight? = nil
local _inputPoint: Attachment? = nil
local _outputPoint: Attachment? = nil
local _statusLabel: TextLabel? = nil
local _prompt: ProximityPrompt? = nil

local _rollSpring = Spring.new(0, PROC.RollSmoothTime)
local _rollAngle = 0
local _active = false
local _particleHandle: any = nil

local _lastInput = 0
local _lastCarried = 0
local _productStack: { BasePart } = {}

-- ── resolve ──────────────────────────────────────────────────────────────────

-- Re-resolved whenever the owned plot changes, the same guard the rest of the
-- plot controllers use: PlotService reassigns plots as players come and go, so
-- a cached part reference can go stale without this.
local function _resolveProcessor(): BasePart?
	local existing = _processor
	if existing and existing.Parent then
		local plot = existing.Parent
		if plot and plot:GetAttribute("OwnerUserId") == LOCAL_PLAYER.UserId then
			return existing
		end
	end

	_processor = nil
	_roller = nil
	_light = nil
	_inputPoint = nil
	_outputPoint = nil
	_statusLabel = nil
	_prompt = nil

	local plots = workspace:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("OwnerUserId") ~= LOCAL_PLAYER.UserId then
			continue
		end
		local body = plot:FindFirstChild("Processor") :: BasePart?
		if not body then
			return nil
		end

		_processor = body
		_roller = body:FindFirstChild("Roller") :: BasePart?
		_light = body:FindFirstChild("ProcessorLight") :: PointLight?
		_inputPoint = body:FindFirstChild("ProcessorInputPoint") :: Attachment?
		_outputPoint = body:FindFirstChild("ProcessorOutputPoint") :: Attachment?
		local label = body:FindFirstChild("ProcessorLabel")
		_statusLabel = label and (label:FindFirstChild("Status") :: TextLabel?)

		local prompt = body:FindFirstChild("DepositPrompt") :: ProximityPrompt?
		if prompt then
			_prompt = prompt
			prompt.Triggered:Connect(function(player: Player)
				if player == LOCAL_PLAYER and _lastCarried > 0 then
					Relay.Bamboo.DepositToProcessor.send({})
				end
			end)
		end
		return body
	end
	return nil
end

-- ── idle / active ────────────────────────────────────────────────────────────

local function _setActive(active: boolean)
	if _active == active then
		return
	end
	_active = active
	_rollSpring.Target = if active then PROC.ActiveRollSpeed else PROC.IdleRollSpeed

	if active then
		if not _particleHandle then
			_particleHandle = Scheduler.Interval(PROC.ParticleIntervalSeconds, function()
				local point = _inputPoint
				if not point or not point.Parent then
					return
				end
				FeelBurst.Emit(point.WorldPosition, {
					Color = Color3.fromRGB(186, 172, 138),
					Count = PROC.ParticleCount,
					Size = 0.4,
					Speed = NumberRange.new(1.5, 3.5),
					Lifetime = NumberRange.new(0.3, 0.6),
					Gravity = -6,
				})
			end)
		else
			_particleHandle:Resume()
		end
	elseif _particleHandle then
		_particleHandle:Pause()
	end
end

local function _updateRoll(dt: number)
	local roller = _roller
	local body = _processor
	if not roller or not body then
		return
	end

	local speed = _rollSpring:Update(dt)
	_rollAngle = (_rollAngle + speed * dt) % (math.pi * 2)
	-- Cylinders spin about their own long axis (local X). PlotService already
	-- laid the roller flat with a 90-degree Z rotation; applying the spin after
	-- that (rightmost in the chain) rotates it about that same long axis rather
	-- than tumbling it end over end.
	roller.CFrame = body.CFrame * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(_rollAngle, 0, 0)

	local light = _light
	if light then
		if _active then
			local pulse = (math.sin(os.clock() * math.pi * 2 / PROC.ActiveLightPulseSeconds) + 1) * 0.5
			light.Brightness = PROC.ActiveLightBrightness + pulse * PROC.ActiveLightPulseAmplitude
		else
			light.Brightness = 0
		end
	end
end

-- ── deposit / product visuals ───────────────────────────────────────────────

-- Bamboo bundles arcing from the player into the input point. Reuses Orbify —
-- the exact same shape as a drop flying into the stockpile, just aimed the
-- other way.
local function _playDeposit(amount: number)
	local point = _inputPoint
	local character = LOCAL_PLAYER.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not point or not root then
		return
	end

	local bundles = math.clamp(
		PROC.MinDepositBundles + math.floor(amount / PROC.DepositBundleThreshold),
		PROC.MinDepositBundles,
		PROC.MaxDepositBundles
	)

	Orbify.Burst({
		Origin = root.Position,
		Target = point.WorldPosition,
		Count = bundles,
		Color = Color3.fromRGB(112, 172, 84),
		Size = Vector3.new(1.4, 0.5, 0.5),
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Grass,
		FlightSeconds = PROC.DepositFlightSeconds,
		ArcHeight = PROC.DepositArcHeight,
		TumbleSeconds = 0,
		OnAbsorb = function()
			local body = _processor
			if body then
				FlashPool.Flash(body, Color3.fromRGB(200, 220, 255), 0.12)
			end
		end,
	})
end

-- One capped product pop per completed batch — Straw is sold the instant it's
-- produced, so this is purely a "a batch just finished" beat, not a growing
-- stock of objects.
local function _playProductPop()
	local point = _outputPoint
	if not point or not point.Parent then
		return
	end

	if #_productStack >= PROC.MaxVisibleProducts then
		local oldest = table.remove(_productStack, 1)
		if oldest then
			TweenService:Create(oldest, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { Transparency = 1 }):Play()
			Debris:AddItem(oldest, 0.25)
		end
	end

	local index = #_productStack
	local part = Instance.new("Part")
	part.Name = "StrawBundle"
	part.Size = Vector3.new(1.2, 0.6, 1.2)
	part.Color = Color3.fromRGB(214, 188, 120)
	part.Material = Enum.Material.Fabric
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	local restPosition = point.WorldPosition + Vector3.new(0, 0.35 + index * 0.55, 0)
	part.CFrame = CFrame.new(point.WorldPosition + Vector3.new(0, PROC.ProductBounceHeight, 0))
	part.Parent = workspace

	TweenService:Create(
		part,
		TweenInfo.new(PROC.ProductBounceSeconds, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
		{ CFrame = CFrame.new(restPosition) }
	):Play()

	table.insert(_productStack, part)

	-- Sold instantly: the product doesn't linger like a growing Straw stockpile
	-- did, it just marks the beat and clears itself shortly after.
	task.delay(1.4, function()
		if part.Parent then
			TweenService:Create(part, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Transparency = 1 }):Play()
			Debris:AddItem(part, 0.35)
		end
		for i, stacked in _productStack do
			if stacked == part then
				table.remove(_productStack, i)
				break
			end
		end
	end)
end

-- ── status / prompt ──────────────────────────────────────────────────────────

local function _updateStatus()
	local label = _statusLabel
	if not label then
		return
	end
	if _lastCarried > 0 then
		label.Text = string.format("Carrying %d  •  %d in processor", _lastCarried, _lastInput)
	else
		label.Text = string.format("%d in processor", _lastInput)
	end

	local prompt = _prompt
	if prompt then
		prompt.Enabled = _lastCarried > 0
		prompt.ObjectText = string.format("%d in processor", _lastInput)
	end
end

-- ── frame ────────────────────────────────────────────────────────────────────

local function _onFrame(dt: number)
	if not _resolveProcessor() then
		return
	end
	_updateRoll(dt)
end

-- ── replica reactions ────────────────────────────────────────────────────────

local function _onInputChanged(input: number)
	local delta = input - _lastInput
	_lastInput = input
	-- "Active" reads as "has fuel", not "mid-batch" — a machine with 3 raw
	-- bamboo waiting is still visibly alive even though it needs InputPerBatch
	-- (10) to actually convert.
	_setActive(input > 0)
	_updateStatus()

	if delta > 0 then
		_playDeposit(delta)
	elseif delta <= -Bamboo.Processing.InputPerBatch then
		-- A batch consumed input without a deposit growing it: that's a
		-- completed batch, so pop the product beat.
		_playProductPop()
	end
end

local function _onCarriedChanged(carried: number)
	_lastCarried = carried
	_updateStatus()
end

-- ── lifecycle ────────────────────────────────────────────────────────────────

function ProcessorController:Start(_fw: any)
	Replica:WaitForData("Player"):andThen(function(replica: any)
		_lastInput = replica.Data.ProcessorInput or 0
		_lastCarried = replica.Data.CarriedBamboo or 0
		_updateStatus()
		_setActive(_lastInput > 0)

		replica:ListenToChange({ "ProcessorInput" }, function()
			_onInputChanged(replica.Data.ProcessorInput or 0)
		end)
		replica:ListenToChange({ "CarriedBamboo" }, function()
			_onCarriedChanged(replica.Data.CarriedBamboo or 0)
		end)
	end)

	RunService:BindToRenderStep(RENDER_BIND, Enum.RenderPriority.Last.Value, _onFrame)

	-- The visible product pop is purely decorative client state; dropping it on
	-- respawn avoids reaching for stale Parts under a plot that may have been
	-- reassigned while the character was gone.
	LOCAL_PLAYER.CharacterRemoving:Connect(function()
		for _, part in _productStack do
			part:Destroy()
		end
		table.clear(_productStack)
	end)
end

return ProcessorController
