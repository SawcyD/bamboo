--!strict
-- Owns every player's luck: how far their crate odds bend toward the rare end.
--
-- Luck is recomputed server-side and written to replicated data, so the
-- LuckBoost chip and the odds grid read the same number the roll will use.
-- The client is never asked what its luck is.
--
-- Sources today:
--   * a timed boost (LuckBoost / LuckBoostExpiresAt), granted via GrantBoost
--   * friends in the server
--
-- Adding a gamepass or potion later means calling GrantBoost; nothing else has
-- to change.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Crates = Core:GetDomain("Crates")

local LuckService = {}
local Framework

-- Boosts expire on a wall clock, so luck is re-evaluated on a slow tick rather
-- than only when something happens to touch it.
local RECOMPUTE_TICK_SECONDS = 2

-- Friend counts change rarely and IsFriendsWith yields, so results are cached
-- per player rather than queried on every recompute.
local _friendLuck: { [Player]: number } = {}

-- ── friends ──────────────────────────────────────────────────────────────────

-- Counts how many other players in this server are friends. Yields, so it runs
-- on its own thread and writes into the cache when it finishes.
local function _refreshFriendLuck(player: Player)
	local count = 0
	for _, other in Players:GetPlayers() do
		if other == player then
			continue
		end
		local ok, isFriend = pcall(function()
			return player:IsFriendsWith(other.UserId)
		end)
		if ok and isFriend then
			count += 1
		end
	end

	if player.Parent then
		_friendLuck[player] = Crates.Luck.FromFriends(count)
	end
end

local function _refreshEveryone()
	for _, player in Players:GetPlayers() do
		task.spawn(_refreshFriendLuck, player)
	end
end

-- ── recompute ────────────────────────────────────────────────────────────────

local function _recompute(player: Player)
	local DataService = Framework:GetService("DataService")

	-- A player who has joined but whose profile hasn't loaded yet has nothing to
	-- write to; the recompute tick will pick them up a moment later.
	if DataService.GetData(player) == nil then
		return
	end

	local boost = DataService.Get(player, "LuckBoost") or 0
	local expiresAt = DataService.Get(player, "LuckBoostExpiresAt") or 0

	-- An expired boost is cleared rather than just ignored, so the saved profile
	-- doesn't carry a stale multiplier around forever.
	if boost > 0 and os.time() >= expiresAt then
		boost = 0
		DataService.Set(player, "LuckBoost", 0)
		DataService.Set(player, "LuckBoostExpiresAt", 0)
	end

	local total = Crates.Luck.Total(boost, _friendLuck[player] or 0)
	if DataService.Get(player, "Luck") ~= total then
		DataService.Set(player, "Luck", total)
	end
end

local function _recomputeEveryone()
	for _, player in Players:GetPlayers() do
		_recompute(player)
	end
end

-- ── lifecycle ────────────────────────────────────────────────────────────────

function LuckService:Start(fw: any)
	Framework = fw

	local function onPlayer(player: Player)
		_friendLuck[player] = 0
		-- Everyone's friend count changes when anyone joins or leaves.
		_refreshEveryone()
		task.defer(_recompute, player)
	end

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player: Player)
		_friendLuck[player] = nil
		_refreshEveryone()
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < RECOMPUTE_TICK_SECONDS then
			return
		end
		accumulator = 0
		_recomputeEveryone()
	end)
end

-- ── public API ───────────────────────────────────────────────────────────────

--[[
	The luck a roll should use for a player, read fresh rather than from the
	replicated copy so a boost that just expired can't be exploited.
	@param player Player Player rolling.
	@return number Internal luck, where 0 is base odds.
]]
function LuckService.GetLuck(player: Player): number
	_recompute(player)
	local DataService = Framework:GetService("DataService")
	return DataService.Get(player, "Luck") or 0
end

--[[
	Grants a timed luck boost. A stronger boost replaces a weaker one; an equal
	or weaker one only ever extends the timer, so a player can never be
	downgraded by claiming a lesser boost.
	@param player Player Who gets it.
	@param luck number Internal luck to grant, e.g. 1 for a "x2" boost.
	@param seconds number How long it lasts.
]]
function LuckService.GrantBoost(player: Player, luck: number, seconds: number)
	local DataService = Framework:GetService("DataService")

	local current = DataService.Get(player, "LuckBoost") or 0
	local expiresAt = DataService.Get(player, "LuckBoostExpiresAt") or 0
	local now = os.time()
	local remaining = math.max(expiresAt - now, 0)

	if luck > current then
		DataService.Set(player, "LuckBoost", luck)
		DataService.Set(player, "LuckBoostExpiresAt", now + seconds)
	else
		DataService.Set(player, "LuckBoostExpiresAt", now + math.max(remaining, seconds))
	end

	_recompute(player)
end

--[[
	Clears any active boost immediately.
	@param player Player Whose boost to end.
]]
function LuckService.ClearBoost(player: Player)
	local DataService = Framework:GetService("DataService")
	DataService.Set(player, "LuckBoost", 0)
	DataService.Set(player, "LuckBoostExpiresAt", 0)
	_recompute(player)
end

return LuckService
