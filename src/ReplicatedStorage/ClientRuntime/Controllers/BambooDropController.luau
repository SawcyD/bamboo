--!strict
-- Presentation for ground drops: bobbing, spinning piles with a count above
-- them, blinking once they are close to despawning, and the pickup burst when
-- they are vacuumed up.
--
-- The drops themselves are server-owned. This controller never decides what a
-- drop is worth or whether it was collected — it only animates what is there.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Audio = require(ReplicatedStorage:WaitForChild("Audio"))
local Bamboo = Core:GetDomain("Bamboo")
local Orbify = Core:Get("Orbify")
local Relay = Core:GetShared("Network")

local ClientModules = script.Parent.Parent:WaitForChild("Modules")
local FeelBurst = require(ClientModules:WaitForChild("FeelBurst"))
local FeelConfig = require(script.Parent.Parent:WaitForChild("Configs"):WaitForChild("FeelConfig"))

local BambooDropController = {}

local LOCAL_PLAYER = Players.LocalPlayer
local DROP_TAG = "BambooDrop"
local ANIMATE_BIND = "BambooDropAnimate"

local DROP = FeelConfig.Drop
local BOB_HEIGHT = DROP.BobHeight
local BOB_SPEED = DROP.BobSpeed
local SPIN_SPEED = DROP.SpinSpeed
-- Blinks per second once a drop enters its warning window.
local BLINK_RATE = 3

type DropView = {
	Part: BasePart,
	Label: TextLabel,
	BaseY: number,
	-- Randomised so a field of drops doesn't bob in lockstep.
	Phase: number,
	-- Local clock at attach, which drives the spawn pop. Deliberately not the
	-- server's SpawnedAt: a drop that streams in late should still pop when the
	-- player first sees it rather than appearing already settled.
	AttachedAt: number,
	BaseSize: Vector3,
	PopHeight: number,
}

local _views: { [BasePart]: DropView } = {}

-- ── attach ───────────────────────────────────────────────────────────────────

local function _attach(instance: Instance)
	if not instance:IsA("BasePart") or _views[instance] then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DropCount"
	billboard.Size = UDim2.fromScale(4, 1.4)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 90
	billboard.Parent = instance

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = Color3.fromRGB(235, 255, 220)
	label.TextStrokeTransparency = 0.3
	label.Text = ""
	label.Parent = billboard

	_views[instance] = {
		Part = instance,
		Label = label,
		BaseY = instance.Position.Y,
		Phase = math.random() * math.pi * 2,
		AttachedAt = os.clock(),
		BaseSize = instance.Size,
		-- Jittered so a pile of drops appearing together doesn't pop in lockstep.
		PopHeight = DROP.PopHeightStuds * (1 + (math.random() * 2 - 1) * DROP.PopHeightJitter),
	}
end

local function _detach(instance: Instance)
	if instance:IsA("BasePart") then
		_views[instance] = nil
	end
end

-- ── animation ────────────────────────────────────────────────────────────────

local function _animate()
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()

	for part, view in _views do
		if not part.Parent then
			_views[part] = nil
			continue
		end

		local amount = part:GetAttribute("Amount") or 0
		view.Label.Text = "+" .. tostring(amount)

		local bob = math.sin(now * BOB_SPEED + view.Phase) * BOB_HEIGHT

		-- Spawn pop: the pile punches up out of the ground and overshoots its
		-- size, then settles into the steady bob. Driven from the animate loop
		-- rather than a tween, because the loop owns CFrame every frame and a
		-- tween would just be overwritten.
		local popAge = now - view.AttachedAt
		if FeelConfig.Enabled.DropFeel and popAge < DROP.PopSeconds then
			local t = popAge / DROP.PopSeconds
			-- One arc up and back down, so it reads as landing rather than rising.
			local arc = math.sin(t * math.pi)
			bob += arc * view.PopHeight
			local overshoot = 1 + (DROP.PopScale - 1) * arc
			part.Size = view.BaseSize * overshoot
		elseif part.Size ~= view.BaseSize then
			part.Size = view.BaseSize
		end

		part.CFrame = CFrame.new(part.Position.X, view.BaseY + bob, part.Position.Z)
			* CFrame.Angles(0, now * SPIN_SPEED + view.Phase, math.rad(90))

		-- Blink out the last few seconds so an expiring pile is unmistakable.
		local spawnedAt = part:GetAttribute("SpawnedAt") or serverNow
		local alive = serverNow - spawnedAt
		if Bamboo.Drops.IsExpiring(alive) then
			local blink = (math.sin(now * math.pi * 2 * BLINK_RATE) + 1) * 0.5
			part.Transparency = blink * 0.75
			view.Label.TextTransparency = blink * 0.75
		elseif part.Transparency ~= 0 then
			part.Transparency = 0
			view.Label.TextTransparency = 0
		end
	end
end

-- ── pickup ───────────────────────────────────────────────────────────────────

local function _onDropsCollected(payload: any)
	local character = LOCAL_PLAYER.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	for _, entry in payload.drops :: { any } do
		local rarity = Bamboo.Rarity.Get(entry.rarity)
		-- A bigger pile sends a *fatter* orb, not more of them. Object count stays
		-- capped so running through a full field of drops can never scale into a
		-- screenful of parts.
		local heft = math.clamp(entry.amount / DROP.TrailMinAmount, 1, 2)

		Orbify.Burst({
			Origin = entry.position,
			Target = root,
			-- Bigger piles throw more orbs, up to a cap so a full field of drops
			-- doesn't bury the screen.
			Count = math.clamp(math.floor(entry.amount / 3), 1, DROP.MaxOrbs),
			Color = rarity.color,
			Size = Vector3.new(1.2, 0.45, 0.45) * heft,
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.Grass,
			-- Already on the ground, so they get pulled straight in.
			PopSpeed = 0,
			TumbleSeconds = 0,
			-- A touch longer on a wider arc than a straight pull, so collection
			-- reads as magnetic rather than as the orb being teleported.
			FlightSeconds = DROP.FlightSeconds,
			ArcHeight = DROP.ArcHeight,
			OnAbsorb = function(_index, _total, landed)
				Audio:Play("BambooPop", "SFX")
				-- Small flash exactly where the orb met the player, so every
				-- pickup lands visibly instead of just ending.
				if FeelConfig.Enabled.DropFeel then
					FeelBurst.Emit(landed, {
						Color = rarity.color,
						Count = 5,
						Size = 0.35,
						Speed = NumberRange.new(3, 7),
						Lifetime = NumberRange.new(0.12, DROP.CollectFlashSeconds),
						Gravity = 0,
						LightEmission = 1,
					})
				end
			end,
		})
	end
end

-- ── lifecycle ────────────────────────────────────────────────────────────────

function BambooDropController:Start(_fw: any)
	for _, instance in CollectionService:GetTagged(DROP_TAG) do
		_attach(instance)
	end
	CollectionService:GetInstanceAddedSignal(DROP_TAG):Connect(_attach)
	CollectionService:GetInstanceRemovedSignal(DROP_TAG):Connect(_detach)

	Relay.Bamboo.DropsCollected.listen(_onDropsCollected)

	RunService:BindToRenderStep(ANIMATE_BIND, Enum.RenderPriority.Last.Value, _animate)
end

return BambooDropController
