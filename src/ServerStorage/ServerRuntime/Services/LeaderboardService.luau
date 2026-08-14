--!strict
--[[
	LeaderboardService: global leaderboards on OrderedDataStores (all-time + weekly).

	Register a board pointing at a path in player data:

		local Leaderboards = Framework:GetService("LeaderboardService")
		Leaderboards.RegisterBoard("Coins", { dataPath = "Coins" })
		-- or computed values:
		Leaderboards.RegisterBoard("Power", { getValue = function(player, data)
			return data.Coins + data.Rebirths * 1000
		end })

	Player values flush every FLUSH_INTERVAL seconds and on leave. Read with:

		Leaderboards.GetTopAsync("Coins", 50, "AllTime")  -- { { userId, value } }
		Leaderboards.GetTopAsync("Coins", 50, "Weekly")

	Results are cached for CACHE_SECONDS; wire them to LeaderboardUI however the
	game presents them. Weekly boards roll over by ISO week index automatically.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LeaderboardService = {}
local Framework: any

local FLUSH_INTERVAL = 120
local CACHE_SECONDS = 30
local WEEK_SECONDS = 7 * 24 * 60 * 60

export type Scope = "AllTime" | "Weekly"

type BoardDef = {
	dataPath: string?,
	getValue: ((player: Player, data: any) -> number)?,
}

local _boards: { [string]: BoardDef } = {}
local _topCache: { [string]: { expiresAt: number, rows: { { userId: number, value: number } } } } = {}
local _datastoresAvailable = true

local function weekIndex(): number
	return math.floor(os.time() / WEEK_SECONDS)
end

local function storeFor(boardName: string, scope: Scope): OrderedDataStore?
	local key = if scope == "Weekly" then `LB_{boardName}_W{weekIndex()}` else `LB_{boardName}_AllTime`
	local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, key)
	if not ok then
		if _datastoresAvailable then
			_datastoresAvailable = false
			warn("LeaderboardService: OrderedDataStore unavailable (Studio API access off?)", store)
		end
		return nil
	end
	return store
end

local function valueFor(board: BoardDef, player: Player, data: any): number?
	if board.getValue then
		local ok, value = pcall(board.getValue, player, data)
		if ok and type(value) == "number" then
			return value
		end
		return nil
	end
	if board.dataPath then
		local node: any = data
		for _, segment in string.split(board.dataPath, ".") do
			if type(node) ~= "table" then
				return nil
			end
			node = node[segment]
		end
		return if type(node) == "number" then node else nil
	end
	return nil
end

function LeaderboardService.RegisterBoard(boardName: string, def: BoardDef)
	assert(type(boardName) == "string" and #boardName > 0, "RegisterBoard: boardName required")
	assert(def.dataPath or def.getValue, "RegisterBoard: dataPath or getValue required")
	_boards[boardName] = def
end

local function flushPlayer(player: Player)
	local DataService = Framework:GetService("DataService")
	local data = DataService.GetData(player)
	if not data then
		return
	end
	for boardName, board in _boards do
		local value = valueFor(board, player, data)
		if value == nil then
			continue
		end
		-- OrderedDataStores only take non-negative integers
		local intValue = math.max(0, math.floor(value))
		for _, scope in { "AllTime" :: Scope, "Weekly" :: Scope } do
			local store = storeFor(boardName, scope)
			if store then
				local ok, err = pcall(store.SetAsync, store, tostring(player.UserId), intValue)
				if not ok then
					warn("LeaderboardService: flush failed for", boardName, scope, err)
				end
			end
		end
	end
end

--- Top `count` rows (max 100), cached for a short window. Yields on cache miss.
function LeaderboardService.GetTopAsync(
	boardName: string,
	count: number,
	scope: Scope
): { { userId: number, value: number } }
	local cacheKey = `{boardName}_{scope}`
	local cached = _topCache[cacheKey]
	if cached and cached.expiresAt > os.clock() then
		return cached.rows
	end

	local store = storeFor(boardName, scope)
	if not store then
		return {}
	end

	local rows: { { userId: number, value: number } } = {}
	local ok, pages = pcall(store.GetSortedAsync, store, false, math.clamp(count, 1, 100))
	if ok then
		for _, entry in pages:GetCurrentPage() do
			table.insert(rows, { userId = tonumber(entry.key) :: number, value = entry.value })
		end
	else
		warn("LeaderboardService: GetSortedAsync failed for", boardName, scope, pages)
	end

	_topCache[cacheKey] = { expiresAt = os.clock() + CACHE_SECONDS, rows = rows }
	return rows
end

function LeaderboardService:Start(fw: any)
	Framework = fw

	-- final flush while the profile is still loaded
	local DataService = Framework:GetService("DataService")
	DataService.RegisterBeforePlayerRemove(function(player: Player)
		if next(_boards) ~= nil then
			flushPlayer(player)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(FLUSH_INTERVAL)
			if next(_boards) == nil then
				continue
			end
			-- skip flushing in Studio test sessions without API access
			if RunService:IsStudio() and not _datastoresAvailable then
				continue
			end
			for _, player in Players:GetPlayers() do
				task.spawn(flushPlayer, player)
			end
		end
	end)
end

return LeaderboardService
