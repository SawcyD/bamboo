--!strict
-- Ownership and equipping of sickles, and the one place swing stats are
-- resolved from a player.
--
-- The client renders whatever it likes; every stat that decides an outcome is
-- read here from saved data, never from a request.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Bamboo = Core:GetDomain("Bamboo")
local Sickles = Core:GetDomain("Sickles")
local Relay = Core:GetShared("Network")

-- Types can't be reached through the runtime domain table, so the module that
-- exports them is required directly.
local SicklesFolder =
	ReplicatedStorage:WaitForChild("Core"):WaitForChild("Shared"):WaitForChild("Domains"):WaitForChild("Sickles")
local SickleTypes = require(SicklesFolder:WaitForChild("Types"))

local SickleService = {}
local Framework

-- Tiers at or above this are announced to the whole server.
local BROADCAST_TIER_RANK = Sickles.Tiers.Rank("Legendary")

-- ── ownership ────────────────────────────────────────────────────────────────

local function _onEquip(payload: any, player: Player)
	local DataService = Framework:GetService("DataService")

	local sickleId = payload.sickleId :: string
	if not Sickles.Definitions.Exists(sickleId) then
		return
	end

	-- Owning it is the gate. A client asking to equip something it never won is
	-- simply ignored.
	local owned = DataService.Get(player, { "OwnedSickles", sickleId })
	if type(owned) ~= "number" or owned <= 0 then
		return
	end

	DataService.Set(player, "EquippedSickle", sickleId)
end

function SickleService:Start(fw: any)
	Framework = fw
	Relay.Crates.EquipSickle.listen(_onEquip)
end

-- ── public API ───────────────────────────────────────────────────────────────

--[[
	Grants a sickle, equipping it when it is a straight upgrade on what the
	player is holding.
	@param player Player Who won it.
	@param sickleId string Sickle to grant; ignored when unknown.
	@return boolean True when this is the player's first copy.
]]
function SickleService.Grant(player: Player, sickleId: string): boolean
	local DataService = Framework:GetService("DataService")

	local definition = Sickles.Definitions.Get(sickleId)
	if not definition then
		return false
	end

	local owned = DataService.Get(player, { "OwnedSickles", sickleId })
	local isNew = type(owned) ~= "number" or owned <= 0
	DataService.Set(player, { "OwnedSickles", sickleId }, (if isNew then 0 else owned) + 1)

	-- Auto-equip a better tier, so a big pull is felt immediately instead of
	-- sitting unnoticed in an inventory.
	local equipped = DataService.Get(player, "EquippedSickle")
	local current = Sickles.Stats.Resolve(equipped)
	if Sickles.Tiers.Rank(definition.tier) > Sickles.Tiers.Rank(current.tier) then
		DataService.Set(player, "EquippedSickle", sickleId)
	end

	if Sickles.Tiers.Rank(definition.tier) >= BROADCAST_TIER_RANK then
		Relay.Crates.RareUnbox.sendToAll({
			playerName = player.DisplayName,
			sickleId = sickleId,
			tier = definition.tier,
		})
	end

	return isNew
end

--[[
	Whether a player owns at least one of a sickle.
	@param player Player Player to check.
	@param sickleId string Sickle id.
	@return boolean True when they own it.
]]
function SickleService.Owns(player: Player, sickleId: string): boolean
	local DataService = Framework:GetService("DataService")
	local owned = DataService.Get(player, { "OwnedSickles", sickleId })
	return type(owned) == "number" and owned > 0
end

--[[
	The stats a player's swing resolves with right now: equipped sickle plus
	upgrade levels. This is the only place the two are combined server-side.
	@param player Player Player swinging.
	@return EffectiveStats Damage, range, multi-hit, swing time, ability.
]]
function SickleService.GetStats(player: Player): SickleTypes.EffectiveStats
	local DataService = Framework:GetService("DataService")

	return Sickles.Stats.Compute(
		DataService.Get(player, "EquippedSickle"),
		DataService.Get(player, "SwingSpeedLevel") or 0,
		DataService.Get(player, "MultiHitLevel") or 0,
		Bamboo.Tool.BaseSwingTime
	)
end

--[[
	The definition a player is currently swinging.
	@param player Player Player to read.
	@return SickleDefinition Their sickle, or the starter as a fallback.
]]
function SickleService.GetEquipped(player: Player): SickleTypes.SickleDefinition
	local DataService = Framework:GetService("DataService")
	return Sickles.Stats.Resolve(DataService.Get(player, "EquippedSickle"))
end

return SickleService
