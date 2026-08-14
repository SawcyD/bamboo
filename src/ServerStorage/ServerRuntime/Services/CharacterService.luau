--!strict
--[[
	CharacterService: centralized character lifecycle.

		local Characters = Framework:GetService("CharacterService")

		Characters.CharacterSpawned:Connect(function(player, character) ... end)
		Characters.CharacterDied:Connect(function(player, character, killer) ... end)
		-- killer is the Player credited with the kill, or nil

	Kill credit: anything that deals a killing blow should tag the victim first —

		Characters.TagKiller(victimHumanoid, attackerPlayer)

	(uses the standard "creator" ObjectValue convention, so Roblox weapons that
	already set creator tags get credited automatically).

	Config (set before/at Start):
		CharacterService.SpawnInvulnerabilityTime = 3  -- ForceField seconds, 0 = off
		CharacterService.RagdollOnDeath = false        -- loose-joint death instead of the default break
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Relay = Core:GetShared("Network")

local CharacterService = {}

CharacterService.SpawnInvulnerabilityTime = 3
CharacterService.RagdollOnDeath = false

CharacterService.CharacterSpawned = Relay.Signal.new()
CharacterService.CharacterDied = Relay.Signal.new()

local KILL_CREDIT_WINDOW = 10 -- seconds a creator tag stays valid

--- Credits `attacker` with the next death of `victimHumanoid` (within the window).
function CharacterService.TagKiller(victimHumanoid: Humanoid, attacker: Player)
	local existing = victimHumanoid:FindFirstChild("creator")
	if existing then
		existing:Destroy()
	end
	local tag = Instance.new("ObjectValue")
	tag.Name = "creator"
	tag.Value = attacker
	tag.Parent = victimHumanoid
	Debris:AddItem(tag, KILL_CREDIT_WINDOW)
end

local function killerFrom(humanoid: Humanoid): Player?
	local tag = humanoid:FindFirstChild("creator")
	if tag and tag:IsA("ObjectValue") and tag.Value and tag.Value:IsA("Player") then
		return tag.Value :: Player
	end
	return nil
end

local function ragdoll(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.BreakJointsOnDeath = false
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Motor6D") then
			local socket = Instance.new("BallSocketConstraint")
			local a0 = Instance.new("Attachment")
			local a1 = Instance.new("Attachment")
			a0.CFrame = descendant.C0
			a1.CFrame = descendant.C1
			a0.Parent = descendant.Part0
			a1.Parent = descendant.Part1
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.TwistLimitsEnabled = true
			socket.Parent = descendant.Parent
			descendant:Destroy()
		end
	end
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end

	if CharacterService.SpawnInvulnerabilityTime > 0 then
		local field = Instance.new("ForceField")
		field.Visible = true
		field.Parent = character
		Debris:AddItem(field, CharacterService.SpawnInvulnerabilityTime)
	end

	if CharacterService.RagdollOnDeath then
		humanoid.BreakJointsOnDeath = false
	end

	humanoid.Died:Connect(function()
		local killer = killerFrom(humanoid)
		if CharacterService.RagdollOnDeath then
			ragdoll(character)
		end
		CharacterService.CharacterDied:Fire(player, character, killer)
	end)

	CharacterService.CharacterSpawned:Fire(player, character)
end

function CharacterService:Start(_fw: any)
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterAdded:Connect(function(character: Model)
			onCharacterAdded(player, character)
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function(character: Model)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end
end

return CharacterService
