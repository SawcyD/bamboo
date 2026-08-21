--!strict
-- World-space punctuation for the harvesting combo.
--
-- The HUD already owns the number, the tier colour, and the decay bar. This adds
-- only what the HUD cannot: a physical response around the player, at the
-- moments that matter. Deliberately sparse — a permanent aura would sit between
-- the player and the field they are trying to read, which is the one thing a
-- harvesting game cannot afford.
--
-- Everything here is driven by the server's ComboState packet. The client never
-- decides what the combo is, only how it looks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Bamboo = Core:GetDomain("Bamboo")
local Relay = Core:GetShared("Network")

local ClientModules = script.Parent.Parent:WaitForChild("Modules")
local FeelBurst = require(ClientModules:WaitForChild("FeelBurst"))
local FeelConfig = require(script.Parent.Parent:WaitForChild("Configs"):WaitForChild("FeelConfig"))

local ComboFXController = {}

local LOCAL_PLAYER = Players.LocalPlayer
local COMBO = FeelConfig.Combo

-- Cancels a pending decay warning when a new packet restarts the window. Without
-- this, a streak that keeps going would still fire the warning scheduled by the
-- previous packet.
local _warningToken = 0

local function _rootPosition(): Vector3?
	local character = LOCAL_PLAYER.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	-- Feet, not centre: a ring at the waist reads as an effect on the avatar,
	-- while a ring on the ground reads as an effect on the world.
	return root.Position - Vector3.new(0, root.Size.Y * 0.5 + 1.5, 0)
end

-- The burst at a milestone: a ground ring plus a short swirl of leaves in the
-- combo's own tier colour.
local function _milestoneBurst(combo: number)
	local position = _rootPosition()
	if not position then
		return
	end

	local color = Bamboo.Combo.Color(combo)
	local ring = COMBO.Ring
	FeelBurst.Ring(position, color, ring.Seconds, ring.StartDiameter, ring.EndDiameter, ring.Thickness)

	FeelBurst.Emit(position + Vector3.new(0, 1.5, 0), {
		Color = color,
		Count = COMBO.SwirlCount,
		Size = 0.45,
		Speed = NumberRange.new(COMBO.SwirlRadius * 1.5, COMBO.SwirlRadius * 3),
		Lifetime = NumberRange.new(COMBO.SwirlSeconds * 0.5, COMBO.SwirlSeconds),
		-- Slight lift rather than a fall, so the swirl rises past the player
		-- instead of pooling at their feet.
		Gravity = 4,
		LightEmission = 0.6,
	})
end

-- A single quiet ring as the streak is about to lapse. One pulse, not a
-- throbbing warning: the player needs to know, not to be nagged.
local function _decayWarning(combo: number)
	local position = _rootPosition()
	if not position then
		return
	end

	local ring = COMBO.Ring
	FeelBurst.Ring(
		position,
		Bamboo.Combo.Color(combo),
		ring.Seconds * 0.7,
		-- Collapsing inward rather than expanding, so it reads as "running out"
		-- and can never be confused with the milestone ring.
		ring.EndDiameter * 0.6,
		ring.StartDiameter,
		ring.Thickness * 0.7
	)
end

local function _onComboState(payload: any)
	if not FeelConfig.Enabled.ComboFeel then
		return
	end

	local combo = payload.combo :: number
	local milestone = payload.milestone :: number
	local windowSeconds = payload.windowSeconds :: number

	if milestone > 0 then
		_milestoneBurst(combo)
	end

	-- Every packet restarts the grace period, so any warning scheduled by an
	-- earlier packet is now stale.
	_warningToken += 1
	local token = _warningToken

	if combo < COMBO.WarnMinCombo or windowSeconds <= 0 then
		return
	end

	local delay = windowSeconds * (1 - COMBO.WarnBelowFraction)
	task.delay(delay, function()
		-- Only fire if no newer packet has arrived: a continuing streak must not
		-- be warned about.
		if token ~= _warningToken then
			return
		end
		_decayWarning(combo)
	end)
end

function ComboFXController:Start(_fw: any)
	Relay.Bamboo.ComboState.listen(_onComboState)
end

return ComboFXController
