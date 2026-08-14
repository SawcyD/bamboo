--!strict
-- Wraps ReplicaService to create and manage player replicas

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local ReplicaAdapter = {}

-- ── replica write telemetry (powers the PerformanceDebug profiler) ───────────
-- Replica traffic bypasses Channel, so the client can't attribute it. When a
-- player's profiler opts in, we estimate bytes for every replica write to them
-- and ship 1 Hz summaries. Zero cost while no one is profiling.
local _telemetryPlayers: { [Player]: { count: number, bytes: number } } = {}

function ReplicaAdapter.SetTelemetryEnabled(player: Player, enabled: boolean)
	_telemetryPlayers[player] = if enabled then { count = 0, bytes = 0 } else nil
end

--- Returns and resets the accumulated row for `player`, or nil if not opted in.
function ReplicaAdapter.FlushTelemetry(player: Player): { count: number, bytes: number }?
	local entry = _telemetryPlayers[player]
	if not entry then
		return nil
	end
	_telemetryPlayers[player] = { count = 0, bytes = 0 }
	return entry
end

Players.PlayerRemoving:Connect(function(player: Player)
	_telemetryPlayers[player] = nil
end)

local function playerFromReplica(replica: any): Player?
	local ok, userId = pcall(function()
		return replica.Tags.UserId
	end)
	if not ok or type(userId) ~= "number" then
		return nil
	end
	return Players:GetPlayerByUserId(userId)
end

local function trackWrite(replica: any, payload: any)
	if next(_telemetryPlayers) == nil then
		return
	end
	local player = playerFromReplica(replica)
	local entry = player and _telemetryPlayers[player]
	if not entry then
		return
	end
	entry.count += 1
	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, payload)
	entry.bytes += if ok and encoded then #encoded else 40
end

-- Lazily resolved so that requiring ReplicaAdapter at module-load time does NOT
-- trigger a GetPackage call while ServerRuntime is still building its dependency
-- graph (which would cause "Circular dependency detected: ReplicaService").
local _replicaService: any = nil
local _token: any = nil

local function getReplicaService(): any
	if _replicaService then
		return _replicaService
	end
	local ServerRuntime = require(game:GetService("ServerStorage"):WaitForChild("ServerRuntime"))
	local okPrimary, primary = pcall(function()
		return ServerRuntime:GetPackage("ReplicaService")
	end)
	if okPrimary then
		_replicaService = primary
	else
		local okFallback, fallback = pcall(function()
			return ServerRuntime:GetPackage("ReplicasService")
		end)
		assert(okFallback, "ReplicaService package not found in ServerRuntime.Packages")
		_replicaService = fallback
	end
	return _replicaService
end

local function getToken(): any
	if _token then
		return _token
	end
	_token = getReplicaService().NewClassToken("Player")
	return _token
end

-- creates a new replica replicated to the given player
function ReplicaAdapter.New(player: Player, data: any): any
	local replica = getReplicaService().NewReplica({
		ClassToken = getToken(),
		Tags = { UserId = player.UserId },
		Data = data,
		Replication = player,
	})
	return replica
end

-- sets a top-level key on the replica
function ReplicaAdapter.Set(replica: any, key: string, value: any)
	trackWrite(replica, value)
	local ok, err = pcall(function()
		replica:SetValue({ key }, value)
	end)
	if not ok then
		warn("ReplicaAdapter.Set error:", err)
	end
end

--- One ReplicaService round-trip: set multiple top-level Data keys (path = {}).
function ReplicaAdapter.SetRootValues(replica: any, values: { [string]: any })
	trackWrite(replica, values)
	local ok, err = pcall(function()
		(replica :: any):SetValues({}, values)
	end)
	if not ok then
		warn("ReplicaAdapter.SetRootValues error:", err)
	end
end

-- sets a nested path on the replica
function ReplicaAdapter.SetPath(replica: any, pathArray: { string }, value: any)
	trackWrite(replica, value)
	local ok, err = pcall(function()
		replica:SetValue(pathArray, value)
	end)
	if not ok then
		warn("ReplicaAdapter.SetPath error:", err)
	end
end

function ReplicaAdapter.Destroy(replica: any)
	local ok, err = pcall(function()
		replica:Destroy()
	end)
	if not ok then
		warn("ReplicaAdapter.Destroy error:", err)
	end
end

return ReplicaAdapter
