--!strict
-- The starter sickle, carried as a rotor: it orbits the player like a
-- helicopter blade and never stops turning. Near mature bamboo it winds up to
-- full speed; away from it the rotor idles slowly rather than parking, so
-- walking into a patch never costs a spin-up before the first cut.
--
-- One full revolution is one swing. The client decides *when* a revolution
-- completes and tells the server; the server decides what that swing hit.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Bamboo = Core:GetDomain("Bamboo")
local Sickles = Core:GetDomain("Sickles")
local Spring = Core:GetPackage("Spring")

-- Types can't be reached through the runtime domain table, so the module that
-- exports them is required directly.
local SicklesFolder =
	ReplicatedStorage:WaitForChild("Core"):WaitForChild("Shared"):WaitForChild("Domains"):WaitForChild("Sickles")
local SickleTypes = require(SicklesFolder:WaitForChild("Types"))
local Relay = Core:GetShared("Network")
local Replica = Core:Get("Replica")

local SickleController = {}
local Framework: any

local LOCAL_PLAYER = Players.LocalPlayer
local SWING_BIND = "BambooSickleSwing"

-- Idle rotor: still turning, just lazily and tucked in closer to the player.
local IDLE_SPIN = Bamboo.Tool.IdleSpinFraction
local IDLE_RADIUS = 3.2
local IDLE_HEIGHT = 0.9
-- How sharply the rotor tips outward as it reaches full speed.
local MAX_BLADE_PITCH = math.rad(18)
-- Ceiling the combo can lift the visual spin to, on top of full cutting speed.
local MAX_COMBO_SPIN_BONUS = 0.45
-- A break kicks the rotor by this much, decaying at BREAK_ENERGY_DECAY per sec.
local BREAK_ENERGY_PER_BREAK = 0.12
local MAX_BREAK_ENERGY = 0.35
local BREAK_ENERGY_DECAY = 2.4

local _model: Model? = nil
local _handle: BasePart? = nil
local _trail: Trail? = nil
-- IDLE_SPIN = coasting, 1 = full cutting speed. A critically damped spring, so
-- winding up reads as momentum rather than a linear ramp.
local _spinSpring = Spring.new(IDLE_SPIN, Bamboo.Tool.SpinSmoothTime)
local _spin = IDLE_SPIN
local _angle = 0
-- Revolutions completed since the last swing was sent.
local _sweepProgress = 0
-- Authoritative combo, from the server. Only ever raises how energetic the
-- rotor *looks* — the swing cadence itself stays on the server's clock.
local _combo = 0
-- Extra spin from recent breaks, decaying back to zero. Visual only.
local _breakEnergy = 0
-- Which definition the visuals are currently built for, so the blade is only
-- rebuilt when the player actually swaps sickles.
local _visualSickleId: string? = nil
local _targetScanAt = -math.huge
local _targetInReach = false
local TARGET_SCAN_SECONDS = 0.12

-- ── tool construction ────────────────────────────────────────────────────────

local function _newPiece(name: string, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Metal
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

local function _attachTrail(blade: BasePart): Trail
	local top = Instance.new("Attachment")
	top.Name = "TrailTop"
	top.Position = Vector3.new(0, 0, -blade.Size.Z * 0.5)
	top.Parent = blade

	local bottom = Instance.new("Attachment")
	bottom.Name = "TrailBottom"
	bottom.Position = Vector3.new(0, 0, blade.Size.Z * 0.5)
	bottom.Parent = blade

	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.28
	trail.MinLength = 0.05
	trail.FaceCamera = true
	trail.LightEmission = 0.6
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(190, 255, 170)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 210, 130)),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	trail.Parent = blade
	return trail
end

local function _buildSickle(): Model
	local model = Instance.new("Model")
	model.Name = "Sickle"

	local handle = _newPiece("Handle", Vector3.new(0.24, 0.24, 2.4), Color3.fromRGB(96, 68, 44))
	handle.Material = Enum.Material.Wood
	handle.Parent = model
	model.PrimaryPart = handle

	local blade = _newPiece("Blade", Vector3.new(0.14, 0.7, 2.6), Color3.fromRGB(214, 220, 228))
	blade.Reflectance = 0.25
	blade.Parent = model

	_trail = _attachTrail(blade)
	model.Parent = workspace.CurrentCamera
	return model
end

-- ── rotor motion ─────────────────────────────────────────────────────────────

-- Places handle and blade for this frame's rotor angle.
local function _poseRotor(root: BasePart)
	local model = _model
	local handle = _handle
	if not model or not handle then
		return
	end

	local sickle = Bamboo.Tool
	-- Remap spin from [IDLE_SPIN, 1] to [0, 1] for the pose blend.
	local wind = math.clamp((_spin - IDLE_SPIN) / (1 - IDLE_SPIN), 0, 1)
	local radius = IDLE_RADIUS + (sickle.OrbitRadius - IDLE_RADIUS) * wind
	local height = IDLE_HEIGHT + (sickle.OrbitHeight - IDLE_HEIGHT) * wind
	local angle = _angle

	local centre = root.Position + Vector3.new(0, height, 0)
	local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius
	-- Blade leads the orbit and tips outward with speed, so the rotor reads as
	-- one continuous arc rather than a part being dragged in a circle.
	local facing = CFrame.lookAt(centre + offset, centre + offset + Vector3.new(-math.sin(angle), 0, math.cos(angle)))
	handle.CFrame = facing * CFrame.Angles(MAX_BLADE_PITCH * wind, 0, 0)

	local blade = model:FindFirstChild("Blade") :: BasePart?
	if blade then
		blade.CFrame = handle.CFrame * CFrame.new(0, 0.5, -1.4) * CFrame.Angles(0, 0, math.rad(-20))
	end

	if _trail then
		-- Always on, but only reads as a blur once the rotor is at cutting speed.
		_trail.Lifetime = 0.10 + 0.20 * wind
	end
end

-- The equipped sickle, straight from replicated data. The server resolves this
-- independently for anything that matters; this copy only drives presentation
-- and the local swing cadence.
local function _equipped(): SickleTypes.SickleDefinition
	local replica = Replica.Player
	local id = replica and replica.Data and replica.Data.EquippedSickle
	return Sickles.Stats.Resolve(id)
end

local function _currentSwingTime(): number
	local replica = Replica.Player
	local level = replica and replica.Data and replica.Data.SwingSpeedLevel or 0
	return Bamboo.Value.SwingTime(level)
end

-- Repaints the blade and trail to match the equipped sickle. Cheap enough to
-- check every frame; only touches instances when the sickle actually changed.
local function _syncSickleVisuals()
	local model = _model
	if not model then
		return
	end

	local definition = _equipped()
	if _visualSickleId == definition.id then
		return
	end
	_visualSickleId = definition.id

	local blade = model:FindFirstChild("Blade") :: BasePart?
	if blade then
		blade.Color = definition.bladeColor
		local tier = Sickles.Tiers.Get(definition.tier)
		-- Higher tiers glow; Common stays plain metal so rarity reads at a glance.
		blade.Material = if tier.glow > 0 then Enum.Material.Neon else Enum.Material.Metal
		blade.Reflectance = 0.25 * (1 - tier.glow)
	end

	if _trail then
		_trail.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, definition.trailColor),
			ColorSequenceKeypoint.new(1, Sickles.Tiers.Get(definition.tier).color),
		})
	end
end

-- ── target sensing ───────────────────────────────────────────────────────────

local function _ownedBambooFolder(): Folder?
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

-- True when a mature stalk is inside the rotor's reach, in any direction.
local function _hasTargetInReach(root: BasePart): boolean
	local now = os.clock()
	if now - _targetScanAt < TARGET_SCAN_SECONDS then
		return _targetInReach
	end
	_targetScanAt = now

	if Framework then
		local growth = Framework:GetController("BambooGrowthController")
		if growth and type(growth.HasMatureInRange) == "function" then
			_targetInReach = growth:HasMatureInRange(root.Position, _equipped().range)
			return _targetInReach
		end
	end

	local folder = _ownedBambooFolder()
	if not folder then
		_targetInReach = false
		return _targetInReach
	end

	local origin = root.Position
	local rangeSq = _equipped().range ^ 2

	for _, stalk in folder:GetChildren() do
		if stalk:GetAttribute("Stage") ~= Bamboo.Field.Stage.Mature then
			continue
		end
		local primary = (stalk :: Model).PrimaryPart
		if not primary then
			continue
		end
		local flat = primary.Position - origin
		if flat.X * flat.X + flat.Z * flat.Z <= rangeSq then
			_targetInReach = true
			return _targetInReach
		end
	end

	_targetInReach = false
	return _targetInReach
end

-- ── frame ────────────────────────────────────────────────────────────────────

local function _onRenderStep(dt: number)
	local character = LOCAL_PLAYER.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 or not _model then
		return
	end

	_syncSickleVisuals()

	-- The rotor never stops; being near bamboo only changes how fast it turns.
	-- A hot combo lifts the ceiling and recent breaks add a decaying kick, so
	-- sustained harvesting visibly escalates.
	_breakEnergy = math.max(_breakEnergy - BREAK_ENERGY_DECAY * dt, 0)
	local comboBonus = Bamboo.Combo.Heat(_combo) * MAX_COMBO_SPIN_BONUS

	_spinSpring.Target = if _hasTargetInReach(root) then 1 + comboBonus + _breakEnergy else IDLE_SPIN
	_spin = _spinSpring:Update(dt)

	local swingTime = _currentSwingTime()
	-- Visual rotation may exceed 1.0 when the combo is hot, but the swing clock
	-- must not: an extra-fast rotor would otherwise manufacture swings the
	-- server is going to reject anyway.
	local visualSpin = _spin
	local swingSpin = math.min(_spin, 1)

	_angle = (_angle + (dt / swingTime) * visualSpin * math.pi * 2) % (math.pi * 2)
	local revolutions = (dt / swingTime) * swingSpin

	_poseRotor(root)

	-- Swings fire off the rotation itself, so a stalk that drifts into reach
	-- mid-revolution is caught by the sweep already in progress. The server
	-- silently drops swings that connect with nothing.
	_sweepProgress += revolutions
	if _sweepProgress < 1 then
		return
	end
	_sweepProgress -= 1

	Relay.Bamboo.Swing.send({
		origin = root.Position,
		look = root.CFrame.LookVector,
	})
end

-- ── lifecycle ────────────────────────────────────────────────────────────────

local function _onCharacter(character: Model)
	character:WaitForChild("HumanoidRootPart", 10)
	if not _model then
		_model = _buildSickle()
		_handle = _model.PrimaryPart
	end
	_spinSpring:Reset(IDLE_SPIN)
	_spin = IDLE_SPIN
	_sweepProgress = 0
	_breakEnergy = 0
	_visualSickleId = nil
end

function SickleController:Start(fw: any)
	Framework = fw
	if LOCAL_PLAYER.Character then
		task.spawn(_onCharacter, LOCAL_PLAYER.Character)
	end
	LOCAL_PLAYER.CharacterAdded:Connect(_onCharacter)

	Relay.Bamboo.ComboState.listen(function(payload: any)
		_combo = payload.combo
	end)

	-- Each break gives the rotor a small kick, so a big swing is felt in the
	-- tool as well as on screen.
	Relay.Bamboo.SwingResult.listen(function(payload: any)
		if payload.breaks > 0 then
			_breakEnergy = math.min(_breakEnergy + payload.breaks * BREAK_ENERGY_PER_BREAK, MAX_BREAK_ENERGY)
		end
	end)

	RunService:BindToRenderStep(SWING_BIND, Enum.RenderPriority.Character.Value, _onRenderStep)
end

--[[
	Seconds the local player's swing currently takes, for HUD/upgrade previews.
	@return number Swing time in seconds at the player's Swing Speed level.
]]
function SickleController.GetSwingTime(): number
	return _currentSwingTime()
end

--[[
	How wound up the rotor is right now, for effects that scale with it.
	@return number IDLE_SPIN while coasting, 1 at full cutting speed.
]]
function SickleController.GetSpin(): number
	return _spin
end

return SickleController
