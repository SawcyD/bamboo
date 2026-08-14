--!strict
-- DataService: manages player data loading, replication, and saving

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Relay = Core:GetShared("Network")

local PlayerProfileModule = require(script:WaitForChild("PlayerProfile"))

local DataService = {}

local ProfileStoreAdapter = require(script:WaitForChild("ProfileStoreAdapter"))
local ReplicaAdapter = require(script:WaitForChild("ReplicaAdapter"))
local SaveQueue = require(script:WaitForChild("SaveQueue"))
local Schema = require(script:WaitForChild("Schema"))

-- ── public/private key split ─────────────────────────────────────────────────
-- Private top-level keys are saved but never replicated to the client.
local _privateKeys: { [string]: boolean } = {}
for _, key in Schema.PrivateKeys do
	_privateKeys[key] = true
end

local function isPrivateKey(key: string): boolean
	return _privateKeys[key] == true or string.sub(key, 1, 1) == "_"
end

-- shallow copy of data without private keys (replica creation + full syncs)
local function publicSnapshot(data: { [string]: any }): { [string]: any }
	local snapshot: { [string]: any } = {}
	for key, value in data do
		if not isPrivateKey(key) then
			snapshot[key] = value
		end
	end
	return snapshot
end

type PlayerRecord = {
	Profile: any,
	Replica: any,
	Queue: SaveQueue.SaveQueueType,
	PlayerProfile: any?,
}

local playerProfiles: { [Player]: PlayerRecord } = {}
local loadingProfiles: { [Player]: boolean } = {}

local _beforePlayerRemoveListeners: { (Player) -> () } = {}
local _dataNormalizers: { (data: any) -> () } = {}

local _profileLoadedSignal = Relay.Signal.new()
local _framework: any
DataService.ProfileLoaded = _profileLoadedSignal

local function syncReplica(record: PlayerRecord)
	local data = record.Profile.Data :: { [string]: any }
	ReplicaAdapter.SetRootValues(record.Replica, publicSnapshot(data))
end

local function syncReplicaPartial(record: PlayerRecord, keys: { string })
	local data = record.Profile.Data :: { [string]: any }
	local patch: { [string]: any } = {}
	for _, key in keys do
		if not isPrivateKey(key) then
			patch[key] = data[key]
		end
	end
	if next(patch) ~= nil then
		ReplicaAdapter.SetRootValues(record.Replica, patch)
	end
end

function DataService.SyncReplicaForRecord(record: PlayerRecord)
	syncReplica(record)
end

local function _playerAdded(player: Player)
	if loadingProfiles[player] then
		return
	end
	loadingProfiles[player] = true

	ProfileStoreAdapter.StartSessionAsync(player.UserId)
		:andThen(function(profile: any)
			-- player may have left during load
			if not player:IsDescendantOf(Players) then
				ProfileStoreAdapter.EndSession(profile)
				loadingProfiles[player] = nil
				return
			end
			-- duplicate guard
			if playerProfiles[player] then
				ProfileStoreAdapter.EndSession(profile)
				loadingProfiles[player] = nil
				return
			end

			-- run game-registered normalizers (defaults, derived caches) before replication
			for _, normalize in _dataNormalizers do
				local ok, err = pcall(normalize, profile.Data)
				if not ok then
					warn("DataService: data normalizer error for", player.Name, err)
				end
			end

			local replica = ReplicaAdapter.New(player, publicSnapshot(profile.Data))
			local queue = SaveQueue.new(profile, ProfileStoreAdapter.Save)

			local record: PlayerRecord = {
				Profile = profile,
				Replica = replica,
				Queue = queue,
				PlayerProfile = nil,
			}

			local function syncThisRecord(syncKeys: { string } | nil)
				-- `{}` is truthy in Lua; treat "no keys" as full sync (e.g. avoid silent no-op replication).
				if syncKeys and #syncKeys > 0 then
					syncReplicaPartial(record, syncKeys)
				else
					syncReplica(record)
				end
			end

			record.PlayerProfile = PlayerProfileModule.new(player, record, _framework, syncThisRecord)

			playerProfiles[player] = record

			_profileLoadedSignal:Fire(player)
			loadingProfiles[player] = nil
		end)
		:catch(function(err: any)
			warn("DataService: failed to load data for", player.Name, err)
			loadingProfiles[player] = nil
		end)
end

local function _playerRemoving(player: Player)
	for _, fn in _beforePlayerRemoveListeners do
		local pack = table.pack(pcall(fn, player))
		if not pack[1] then
			warn("DataService: BeforePlayerRemove listener error:", pack[2])
		end
	end

	local record = playerProfiles[player]
	if not record then
		return
	end
	-- Do not call SaveQueue:ForceSave() here: ProfileStore Profile:EndSession() already runs a final
	-- SaveProfileAsync with session release. ForceSave + EndSession queued two writes for the same key
	-- and spiked the DataStore request queue (Studio warning: "request was added to queue").
	record.Queue:Destroy()
	ProfileStoreAdapter.EndSession(record.Profile)
	ReplicaAdapter.Destroy(record.Replica)
	playerProfiles[player] = nil
end

--- Runs while the profile is still loaded (before save/end session). Use for flushing derived stats (e.g. session time).
function DataService.RegisterBeforePlayerRemove(listener: (Player) -> ())
	table.insert(_beforePlayerRemoveListeners, listener)
end

--- Runs on profile.Data after load, before the replica is created. Use for per-game
--- defaults and derived caches (register from your game's services before players join).
function DataService.RegisterDataNormalizer(normalize: (data: any) -> ())
	table.insert(_dataNormalizers, normalize)
end

-- ── profiler telemetry publisher ─────────────────────────────────────────────
-- Clients running the PerformanceDebug profiler opt in via Debug.SetTelemetry;
-- we then ship 1 Hz replica-write bandwidth rows (traffic Channel can't see).
local _telemetryPlayers: { [Player]: boolean } = {}
local _telemetryLoop: thread? = nil

local function startTelemetryLoopIfNeeded()
	if _telemetryLoop then
		return
	end
	_telemetryLoop = task.spawn(function()
		while next(_telemetryPlayers) ~= nil do
			task.wait(1)
			for player in _telemetryPlayers do
				local row = ReplicaAdapter.FlushTelemetry(player)
				if row then
					Relay.Debug.ReplicaTelemetry.sendTo({
						rows = {
							{ name = "Replica_PlayerData", count = row.count, bytes = row.bytes },
						},
					}, player)
				end
			end
		end
		_telemetryLoop = nil
	end)
end

function DataService:Start(fw: any)
	_framework = fw
	Players.PlayerAdded:Connect(_playerAdded)
	Players.PlayerRemoving:Connect(_playerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(_playerAdded, player)
	end

	Relay.Debug.SetTelemetry.listen(function(payload: any, player: Player)
		local enabled = payload.enabled == true
		ReplicaAdapter.SetTelemetryEnabled(player, enabled)
		if enabled then
			_telemetryPlayers[player] = true
			startTelemetryLoopIfNeeded()
		else
			_telemetryPlayers[player] = nil
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		_telemetryPlayers[player] = nil
	end)

	game:BindToClose(function()
		local snapshot: { PlayerRecord } = {}
		for _, rec in playerProfiles do
			table.insert(snapshot, rec)
		end
		for _, record in snapshot do
			record.Queue:Destroy()
			ProfileStoreAdapter.EndSession(record.Profile)
		end
		table.clear(playerProfiles)
		-- Give ProfileStore time to flush final saves on live servers; skipping in
		-- Studio keeps stop-play fast (ProfileStore mocks/saves synchronously there).
		if not RunService:IsStudio() then
			task.wait(4)
		end
	end)
end

-- returns profile.Data or nil if not loaded
function DataService.GetData(player: Player): any?
	local record = playerProfiles[player]
	return record and record.Profile.Data or nil
end

-- returns the player's Replica or nil
function DataService.GetReplica(player: Player): any?
	local record = playerProfiles[player]
	return record and record.Replica or nil
end

-- returns the full profile object or nil
function DataService.GetProfile(player: Player): any?
	local record = playerProfiles[player]
	return record and record.Profile or nil
end

-- mutates data via fn, marks dirty, syncs replica (full table unless syncKeys lists top-level keys only).
function DataService.UpdateData(player: Player, fn: (any) -> (), syncKeys: { string } | nil)
	local record = playerProfiles[player]
	if not record then
		warn("DataService.UpdateData: no profile for", player.Name)
		return
	end
	fn(record.Profile.Data)
	record.Queue:MarkDirty()
	if syncKeys and #syncKeys > 0 then
		syncReplicaPartial(record, syncKeys)
	else
		syncReplica(record)
	end
end

function DataService:GetPlayerProfile(player: Player): any?
	local record = playerProfiles[player]
	return record and record.PlayerProfile or nil
end

-- ── path-based data API ──────────────────────────────────────────────────────
-- One call = mutate profile.Data + mark dirty + replicate. No manual replica
-- bookkeeping. Paths are "Coins" / "Inventory.Items" strings or {"Inventory", id}
-- arrays (use arrays when a segment isn't a valid identifier, e.g. UUID keys).
-- Replication granularity is the top-level key: only that key is re-sent, never
-- the whole profile. Private keys save without replicating.

type DataPath = string | { string }

local function resolvePath(path: DataPath): { string }
	if type(path) == "string" then
		return string.split(path, ".")
	end
	assert(type(path) == "table" and #path > 0, "DataService: path must be a string or non-empty array")
	return path
end

-- walks to the parent of the final segment, creating intermediate tables
local function walkToParent(data: any, parts: { string }): any
	local node = data
	for i = 1, #parts - 1 do
		local segment = parts[i]
		if type(node[segment]) ~= "table" then
			node[segment] = {}
		end
		node = node[segment]
	end
	return node
end

local function replicateTopLevelKey(record: PlayerRecord, key: string)
	if isPrivateKey(key) then
		return
	end
	ReplicaAdapter.SetPath(record.Replica, { key }, (record.Profile.Data :: any)[key])
end

--- Reads the value at `path` (or all of Data when path is nil). Nil-safe on missing segments.
function DataService.Get(player: Player, path: DataPath?): any?
	local record = playerProfiles[player]
	if not record then
		return nil
	end
	if path == nil then
		return record.Profile.Data
	end
	local node: any = record.Profile.Data
	for _, segment in resolvePath(path) do
		if type(node) ~= "table" then
			return nil
		end
		node = node[segment]
	end
	return node
end

--- Sets `path` to `value`, marks the profile dirty, and replicates the affected
--- top-level key. Returns true on success.
function DataService.Set(player: Player, path: DataPath, value: any): boolean
	local record = playerProfiles[player]
	if not record then
		warn("DataService.Set: no profile for", player.Name)
		return false
	end
	local parts = resolvePath(path)
	local parent = walkToParent(record.Profile.Data, parts)
	parent[parts[#parts]] = value
	record.Queue:MarkDirty()
	replicateTopLevelKey(record, parts[1])
	return true
end

--- Transforms the value at `path` via `fn(current) -> new`, then saves + replicates.
--- Returns the new value (or nil if no profile).
function DataService.Update(player: Player, path: DataPath, fn: (current: any) -> any): any?
	local record = playerProfiles[player]
	if not record then
		warn("DataService.Update: no profile for", player.Name)
		return nil
	end
	local parts = resolvePath(path)
	local parent = walkToParent(record.Profile.Data, parts)
	local key = parts[#parts]
	local newValue = fn(parent[key])
	parent[key] = newValue
	record.Queue:MarkDirty()
	replicateTopLevelKey(record, parts[1])
	return newValue
end

--- Adds `amount` to the number at `path` (missing/non-number treated as 0).
--- Returns the new value (or nil if no profile).
function DataService.Increment(player: Player, path: DataPath, amount: number): number?
	return DataService.Update(player, path, function(current)
		local base = if type(current) == "number" then current else 0
		return base + amount
	end) :: number?
end

--- Removes the value at `path` (sets it to nil), then saves + replicates.
function DataService.Remove(player: Player, path: DataPath): boolean
	return DataService.Set(player, path, nil)
end

return DataService
