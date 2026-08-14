--!strict

local PlayerProfile = {}
PlayerProfile.__index = PlayerProfile

export type PlayerProfileType = typeof(setmetatable(
	{} :: {
		Player: Player,
		_record: any,
		_framework: any,
		_syncReplica: (syncKeys: { string } | nil) -> (),
	},
	PlayerProfile
))

function PlayerProfile.new(
	player: Player,
	record: any,
	fw: any,
	syncReplica: (syncKeys: { string }?) -> ()
): PlayerProfileType
	local self = setmetatable({
		Player = player,
		_record = record,
		_framework = fw,
		_syncReplica = syncReplica,
	}, PlayerProfile) :: PlayerProfileType
	return self
end

function PlayerProfile:GetData()
	return self._record.Profile.Data
end

-- If syncKeys is set, only those top-level Data keys are pushed to the client replica (saves bandwidth).
function PlayerProfile:Update(fn: (any) -> (), syncKeys: { string } | nil)
	local data = self._record.Profile.Data
	local ok, err = pcall(fn, data)
	if not ok then
		error(err)
	end
	self._record.Queue:MarkDirty()
	self._syncReplica(syncKeys)
end

-- Mixins live as child ModuleScripts (Rojo: PlayerProfile folder + init + one module per domain,
-- e.g. Inventory.luau). Each must return function(PlayerProfile) and is applied automatically.
-- Names starting with "_" are skipped (templates).
for _, child in script:GetChildren() do
	if child:IsA("ModuleScript") and child.Name:sub(1, 1) ~= "_" then
		local mod = require(child)
		if type(mod) ~= "function" then
			error(`[PlayerProfile] mixin "{child.Name}" must return function(PlayerProfile), got {type(mod)}`)
		end
		mod(PlayerProfile)
	end
end

return PlayerProfile
