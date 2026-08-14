--!strict
-- Client-only visual component for stationary NPCs.
-- Tag an NPC with "Animate" and set AnimationProfile to a stable animation ID,
-- such as "shopkeeper" or "gym_teacher".

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Component = Core:Get("Component")
local Motion = Core:Get("Motion")
local Animations = Core:GetShared("Animations")

local AnimatedNPC = Component.new({
	tag = "Animate",
})

local function getProfileName(instance: Instance): string?
	local value = instance:GetAttribute("AnimationProfile")
	if type(value) ~= "string" or value == "" then
		return nil
	end
	return value
end

function AnimatedNPC:_playIdle()
	if not self.Controller or not self.Profile then
		return
	end

	local locomotion = self.Profile.Locomotion
	if locomotion and locomotion.Idle then
		self.Controller:Play(locomotion.Idle, {
			Layer = "Base",
			FadeTime = 0,
		})
	end
end

function AnimatedNPC:_applyProfile()
	local profileName = getProfileName(self.Instance)
	if not profileName then
		warn(`AnimatedNPC: {self.Instance:GetFullName()} is missing the AnimationProfile attribute`)
		self.Profile = nil
		self.Controller:SetProfile({ Animations = {} })
		return
	end

	local profile = Animations.Registry.Get(profileName)
	if not profile then
		warn(`AnimatedNPC: unknown animation profile "{profileName}" on {self.Instance:GetFullName()}`)
		self.Profile = nil
		self.Controller:SetProfile({ Animations = {} })
		return
	end

	self.Profile = profile
	self.Controller:SetProfile(profile)
	self:_playIdle()
end

function AnimatedNPC:Construct()
	if not self.Instance:IsA("Model") then
		warn(`AnimatedNPC: tagged instance must be a Model: {self.Instance:GetFullName()}`)
		return
	end

	self.Controller = Motion.Controller.new(self.Instance)
	self.Janitor:Add(self.Instance:GetAttributeChangedSignal("AnimationProfile"):Connect(function()
		self:_applyProfile()
	end))
end

function AnimatedNPC:Start()
	if self.Controller then
		self:_applyProfile()
	end
end

function AnimatedNPC:Stop()
	if self.Controller then
		self.Controller:Destroy()
		self.Controller = nil
	end
	self.Profile = nil
end

return AnimatedNPC
