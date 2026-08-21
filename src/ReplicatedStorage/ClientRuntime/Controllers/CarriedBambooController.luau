--!strict
-- Physical carry state: a simple bamboo bundle attached to the character while
-- CarriedBamboo > 0, plus a billboard above the head showing exactly how much.
--
-- Carrying has no capacity limit, so the bundle's size is a soft log curve on
-- the raw amount rather than a fraction of a capacity that no longer exists —
-- it keeps growing, just more slowly, so a huge carry still reads as "a lot"
-- without the part becoming absurd.
--
-- Deliberately minimal — one part welded to the back, one billboard, not an
-- animation rig. CarriedBamboo is the authoritative, replicated number; this
-- only ever reacts to it. If the model fails to attach (character not loaded,
-- part destroyed mid-tween) nothing here can affect whether the deposit/take
-- requests work — gameplay never depends on this visual succeeding.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local FormatUtil = Core:GetUtil("FormatUtil")
local Replica = Core:Get("Replica")

local CarriedBambooController = {}

local LOCAL_PLAYER = Players.LocalPlayer
local BASE_SIZE = Vector3.new(2.4, 0.8, 0.8)
local MIN_SCALE = 0.7
local MAX_SCALE = 2.2
-- log-scaled so a huge carry keeps growing the bundle, just with diminishing
-- returns rather than an unbounded part.
local SCALE_LOG_BASE = 10

local _bundle: BasePart? = nil
local _billboard: BillboardGui? = nil
local _amountLabel: TextLabel? = nil

-- ── bundle model ─────────────────────────────────────────────────────────────

local function _destroyBundle()
	if _bundle then
		_bundle:Destroy()
	end
	_bundle = nil
	_billboard = nil
	_amountLabel = nil
end

local function _attachBundle(character: Model)
	local torso = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart?
	if not torso then
		return
	end

	local part = Instance.new("Part")
	part.Name = "CarriedBambooBundle"
	part.Shape = Enum.PartType.Cylinder
	part.Size = BASE_SIZE
	part.Color = Color3.fromRGB(112, 172, 84)
	part.Material = Enum.Material.Grass
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Parent = character

	local weld = Instance.new("Motor6D")
	weld.Name = "CarriedBambooWeld"
	weld.Part0 = torso
	weld.Part1 = part
	weld.C0 = CFrame.new(0, 0.3, 0.6) * CFrame.Angles(0, 0, math.rad(90))
	weld.Parent = torso

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CarriedBambooLabel"
	billboard.Size = UDim2.fromOffset(140, 36)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Amount"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.3
	label.Text = ""
	label.Parent = billboard

	_bundle = part
	_billboard = billboard
	_amountLabel = label
end

-- ── reactions ────────────────────────────────────────────────────────────────

local function _refresh(carried: number)
	if carried <= 0 then
		if _bundle then
			TweenService:Create(_bundle, TweenInfo.new(0.15), { Transparency = 1 }):Play()
			task.delay(0.2, _destroyBundle)
		end
		return
	end

	local character = LOCAL_PLAYER.Character
	if not character then
		return
	end

	if not _bundle or not _bundle.Parent then
		_attachBundle(character)
	end

	local bundle = _bundle
	if not bundle then
		return
	end

	local fraction = math.log(carried + 1, SCALE_LOG_BASE)
	local scale = math.clamp(MIN_SCALE + (MAX_SCALE - MIN_SCALE) * fraction, MIN_SCALE, MAX_SCALE)
	bundle.Size = BASE_SIZE * scale
	bundle.Transparency = 0

	local label = _amountLabel
	if label then
		label.Text = string.format("Carrying %s", FormatUtil.Number(carried))
	end
end

-- ── lifecycle ────────────────────────────────────────────────────────────────

function CarriedBambooController:Start(_fw: any)
	local carried = 0

	Replica:WaitForData("Player"):andThen(function(replica: any)
		carried = replica.Data.CarriedBamboo or 0
		_refresh(carried)

		replica:ListenToChange({ "CarriedBamboo" }, function()
			carried = replica.Data.CarriedBamboo or 0
			_refresh(carried)
		end)
	end)

	LOCAL_PLAYER.CharacterAdded:Connect(function()
		_destroyBundle()
		if carried > 0 then
			task.defer(_refresh, carried)
		end
	end)
	LOCAL_PLAYER.CharacterRemoving:Connect(_destroyBundle)
end

return CarriedBambooController
