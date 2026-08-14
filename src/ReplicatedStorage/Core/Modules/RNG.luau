--!strict
--[[
	RNG: shared weighted random module (client + server).

	Plain helpers (shared global stream):
		RNG.Chance(25)                         -- true ~25% of the time
		RNG.Range(5, 10)                       -- random integer 5..10
		RNG.Number(0.5, 1.5)                   -- random float
		RNG.Pick(array)                        -- uniform pick
		RNG.Shuffle(array)                     -- returns a shuffled copy
		RNG.Sample(array, 3)                   -- 3 distinct random elements

	Weighted rolls with optional luck:
		local drops = {
			{ name = "Common",    weight = 80, rarity = "Common" },
			{ name = "Rare",      weight = 15, rarity = "Rare" },
			{ name = "Legendary", weight = 5,  rarity = "Legendary" },
		}
		RNG.Roll(drops)            -- plain weighted roll
		RNG.Roll(drops, 2)         -- luck = 2: rarer rows get boosted (never guaranteed)
		RNG.GetChance(drops, "Legendary", 2)  -- effective % with luck applied
		RNG.GetOddsLabel(drops, "Legendary")  -- "1 in 20" style label for UI

	Luck model: entries are ranked by base weight (smallest = rarest). Each entry's
	weight is multiplied by `1 + luck * rarityFactor`, where rarityFactor is 1 for
	the rarest row and 0 for the most common. Luck shifts odds toward rare rows but
	every row stays possible.

	Pity (optional, e.g. gacha-style "guaranteed rare after N rolls"):
		local roller = RNG.NewPityRoller({
			isRare = function(entry) return entry.rarity == "Legendary" or entry.rarity == "Mythic" end,
			softStart = 40,  -- rolls before rare weights begin ramping
			hardCap = 80,    -- roll count at which a rare drop is forced (if any exist)
			softBoost = 9,   -- max extra weight multiplier across the soft band
		})
		local result, wasRare = roller:Roll(drops, luck, pityCount)
		-- caller stores pityCount per player/pool; reset to 0 when wasRare is true

	Seeded streams (reproducible rolls, useful for tests and client prediction):
		local stream = RNG.NewStream(seed)
		stream:Roll(drops, luck)
		stream:Range(1, 6)
]]

local RNG = {}

export type DropEntry = {
	name: string,
	weight: number,
	rarity: string?,
	[any]: any, -- extra fields pass through untouched
}

export type RollResult = {
	name: string,
	rarity: string?,
	weight: number,
	entry: DropEntry,
}

export type PityConfig = {
	isRare: (entry: DropEntry) -> boolean,
	softStart: number?,
	hardCap: number?,
	softBoost: number?,
}

local _globalRandom = Random.new()

-- ── internal: luck-weighted effective weights ───────────────────────────────

-- Per-entry multipliers: rarest (smallest base weight) gets the highest boost when luck > 0.
local function getEffectiveWeights(drops: { DropEntry }, luck: number): { number }
	local n = #drops
	if n == 0 then
		return {}
	end

	if luck == 0 or n == 1 then
		local out: { number } = {}
		for i = 1, n do
			out[i] = math.max(drops[i].weight, 1e-9)
		end
		return out
	end

	local indices: { number } = {}
	for i = 1, n do
		indices[i] = i
	end
	table.sort(indices, function(a, b)
		local wa, wb = drops[a].weight, drops[b].weight
		if wa ~= wb then
			return wa < wb
		end
		return a < b
	end)

	local rankOf: { [number]: number } = {}
	for rank, origIdx in ipairs(indices) do
		rankOf[origIdx] = rank - 1
	end

	local denom = math.max(1, n - 1)
	local out: { number } = {}
	for i = 1, n do
		local r = rankOf[i]
		local mult = 1 + luck * ((n - 1 - r) / denom)
		out[i] = math.max(drops[i].weight, 1e-9) * mult
	end
	return out
end

local function getTotalWeight(effective: { number }): number
	local sum = 0
	for _, w in effective do
		sum += w
	end
	return sum
end

local function rollWeighted(random: Random, drops: { DropEntry }, luck: number): RollResult
	local n = #drops
	assert(n > 0, "RNG.Roll: empty drops table")

	local effective = getEffectiveWeights(drops, luck)
	local total = getTotalWeight(effective)
	assert(total > 0, "RNG.Roll: total weight is zero")

	local pick = random:NextNumber() * total
	local cum = 0
	for i = 1, n do
		cum += effective[i]
		if pick <= cum then
			local d = drops[i]
			return { name = d.name, rarity = d.rarity, weight = d.weight, entry = d }
		end
	end

	local d = drops[n]
	return { name = d.name, rarity = d.rarity, weight = d.weight, entry = d }
end

-- ── plain helpers ────────────────────────────────────────────────────────────

--- True `percent`% of the time (0–100).
function RNG.Chance(percent: number): boolean
	return _globalRandom:NextNumber() * 100 < percent
end

--- Random integer in [min, max] (inclusive).
function RNG.Range(min: number, max: number): number
	return _globalRandom:NextInteger(min, max)
end

--- Random float in [min, max).
function RNG.Number(min: number, max: number): number
	return min + _globalRandom:NextNumber() * (max - min)
end

--- Uniform random element of a non-empty array.
function RNG.Pick<T>(array: { T }): T
	assert(#array > 0, "RNG.Pick: empty array")
	return array[_globalRandom:NextInteger(1, #array)]
end

--- Returns a shuffled copy (Fisher–Yates); the input array is untouched.
function RNG.Shuffle<T>(array: { T }): { T }
	local copy = table.clone(array)
	for i = #copy, 2, -1 do
		local j = _globalRandom:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

--- `count` distinct random elements (order randomized). Clamps to #array.
function RNG.Sample<T>(array: { T }, count: number): { T }
	local shuffled = RNG.Shuffle(array)
	local n = math.min(count, #shuffled)
	local out: { T } = table.create(n)
	table.move(shuffled, 1, n, 1, out)
	return out
end

-- ── weighted rolls ───────────────────────────────────────────────────────────

--- Weighted roll. `luck` (default 0) boosts rarer rows; see luck model in header.
function RNG.Roll(drops: { DropEntry }, luck: number?): RollResult
	return rollWeighted(_globalRandom, drops, luck or 0)
end

function RNG.RollMany(drops: { DropEntry }, count: number, luck: number?): { RollResult }
	local results: { RollResult } = table.create(count)
	for i = 1, count do
		results[i] = rollWeighted(_globalRandom, drops, luck or 0)
	end
	return results
end

--- Effective chance (0–100) of rolling any row named `name`, with luck applied.
function RNG.GetChance(drops: { DropEntry }, name: string, luck: number?): number
	local effective = getEffectiveWeights(drops, luck or 0)
	local total = getTotalWeight(effective)
	if total <= 0 then
		return 0
	end
	local share = 0
	for i, d in drops do
		if d.name == name then
			share += effective[i]
		end
	end
	return (share / total) * 100
end

-- ── odds labels (for drop-table UI) ──────────────────────────────────────────

local function formatOddsN(n: number): string
	if n < 100 then
		return string.format("%.1f%%", (1 / n) * 100)
	end
	if n < 1_000_000 then
		return `1 in {math.floor(n + 0.5)}`
	end
	local scaled: number
	local suffix: string
	if n >= 1_000_000_000_000 then
		scaled = n / 1_000_000_000_000
		suffix = "T"
	elseif n >= 1_000_000_000 then
		scaled = n / 1_000_000_000
		suffix = "B"
	else
		scaled = n / 1_000_000
		suffix = "M"
	end
	return `1 in {string.format("%.1f", scaled)}{suffix}`
end

--- Human-readable odds ("3.2%", "1 in 250", "1 in 1.5M") for `name`, with luck applied.
function RNG.GetOddsLabel(drops: { DropEntry }, name: string, luck: number?): string
	local effective = getEffectiveWeights(drops, luck or 0)
	local total = getTotalWeight(effective)
	if total <= 0 then
		return "—"
	end
	local share = 0
	for i, d in drops do
		if d.name == name then
			share += effective[i]
		end
	end
	if share <= 0 then
		return "—"
	end
	return formatOddsN(total / share)
end

--- Unique name -> odds label map (batch for drop-table UI).
function RNG.GetAllOddsLabels(drops: { DropEntry }, luck: number?): { [string]: string }
	local out: { [string]: string } = {}
	local seen: { [string]: boolean } = {}
	for _, d in drops do
		if not seen[d.name] then
			seen[d.name] = true
			out[d.name] = RNG.GetOddsLabel(drops, d.name, luck)
		end
	end
	return out
end

--- Copy of drops sorted most → least common (stable by name).
function RNG.GetSortedDrops(drops: { DropEntry }): { DropEntry }
	local copy = table.clone(drops)
	table.sort(copy, function(a, b)
		if a.weight ~= b.weight then
			return a.weight > b.weight
		end
		return a.name < b.name
	end)
	return copy
end

-- ── pity roller ──────────────────────────────────────────────────────────────

local PityRoller = {}
PityRoller.__index = PityRoller

export type PityRollerType = typeof(setmetatable(
	{} :: {
		_isRare: (entry: DropEntry) -> boolean,
		_softStart: number,
		_hardCap: number,
		_softBoost: number,
		_random: Random,
	},
	PityRoller
))

--- Rolls with soft/hard pity. Returns (result, wasRare). The caller owns the pity
--- counter: increment it each roll and reset to 0 when wasRare is true.
function PityRoller.Roll(
	self: PityRollerType,
	drops: { DropEntry },
	luck: number?,
	pityCount: number?
): (RollResult, boolean)
	local p = pityCount or 0

	-- Hard cap: force a rare-only roll if any rare rows exist.
	if p >= self._hardCap then
		local rareDrops: { DropEntry } = {}
		for _, d in drops do
			if self._isRare(d) then
				table.insert(rareDrops, d)
			end
		end
		if #rareDrops > 0 then
			return rollWeighted(self._random, rareDrops, luck or 0), true
		end
		local r = rollWeighted(self._random, drops, luck or 0)
		return r, self._isRare(r.entry)
	end

	if p < self._softStart then
		local r = rollWeighted(self._random, drops, luck or 0)
		return r, self._isRare(r.entry)
	end

	-- Soft pity band: clone drops and ramp rare row weights toward the hard cap.
	local ramp = (p - self._softStart) / math.max(1, self._hardCap - self._softStart)
	local mult = 1 + ramp * self._softBoost
	local modified: { DropEntry } = table.create(#drops)
	for i, d in drops do
		if self._isRare(d) then
			local boosted = table.clone(d)
			boosted.weight = d.weight * mult
			modified[i] = boosted
		else
			modified[i] = d
		end
	end
	local r = rollWeighted(self._random, modified, luck or 0)
	return r, self._isRare(r.entry)
end

function RNG.NewPityRoller(config: PityConfig): PityRollerType
	assert(
		type(config) == "table" and type(config.isRare) == "function",
		"RNG.NewPityRoller: config.isRare is required"
	)
	return setmetatable({
		_isRare = config.isRare,
		_softStart = config.softStart or 40,
		_hardCap = config.hardCap or 80,
		_softBoost = config.softBoost or 9,
		_random = _globalRandom,
	}, PityRoller)
end

-- ── seeded stream ────────────────────────────────────────────────────────────

local Stream = {}
Stream.__index = Stream

export type StreamType = typeof(setmetatable({} :: { _random: Random }, Stream))

function Stream.Chance(self: StreamType, percent: number): boolean
	return self._random:NextNumber() * 100 < percent
end

function Stream.Range(self: StreamType, min: number, max: number): number
	return self._random:NextInteger(min, max)
end

function Stream.Number(self: StreamType, min: number, max: number): number
	return min + self._random:NextNumber() * (max - min)
end

function Stream.Pick<T>(self: StreamType, array: { T }): T
	assert(#array > 0, "RNG.Stream:Pick: empty array")
	return array[self._random:NextInteger(1, #array)]
end

function Stream.Roll(self: StreamType, drops: { DropEntry }, luck: number?): RollResult
	return rollWeighted(self._random, drops, luck or 0)
end

--- Independent random stream; same seed → same sequence (tests, client prediction).
function RNG.NewStream(seed: number?): StreamType
	return setmetatable({
		_random = if seed ~= nil then Random.new(seed) else Random.new(),
	}, Stream)
end

return RNG
