--!strict
--[[ Legacy `GenerateID` options plus `IdUtil` helpers (UUID, short, prefixed, sequential). ]]

local HttpService = game:GetService("HttpService")

local alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

local function generateShortID(length: number)
	local id = {}
	for _ = 1, length do
		local rand = math.random(1, #alphabet)
		table.insert(id, alphabet:sub(rand, rand))
	end
	return table.concat(id)
end

type LegacyGenerateIdOptions = {
	wrapInBraces: boolean?,
	uppercase: boolean?,
	prefix: string?,
	suffix: string?,
	timestamp: boolean?,
	short: boolean?,
	base64: boolean?,
	length: number?,
}

local originalGenerateID = function(options: LegacyGenerateIdOptions?): string
	options = options or {}
	local wrapInBraces = options.wrapInBraces or false
	local uppercase = options.uppercase or false
	local prefix = options.prefix or ""
	local suffix = options.suffix or ""
	local includeTimestamp = options.timestamp or false
	local short = options.short or false
	local base64 = options.base64 or false
	local length = options.length or 12

	local id

	if short then
		id = generateShortID(length)
	elseif base64 then
		local rawGUID = HttpService:GenerateGUID(false)
		id = HttpService:Base64Encode(rawGUID)
	else
		id = HttpService:GenerateGUID(wrapInBraces)
	end

	if includeTimestamp then
		local timestamp = os.time()
		id = string.format("%s-%d", id, timestamp)
	end

	if uppercase then
		id = string.upper(id)
	end

	id = prefix .. id .. suffix

	return id
end

export type IdFormat = "uuid" | "short" | "numeric" | "alphanumeric" | "hex"

export type IdOptions = {
	length: number?,
	prefix: string?,
	suffix: string?,
	separator: string?,
	uppercase: boolean?,
	excludeAmbiguous: boolean?,
}

-- Character sets for ID generation
local _hexChars = "0123456789abcdef"
local _alphaChars = "abcdefghijklmnopqrstuvwxyz"
local _numericChars = "0123456789"
local _alphanumericChars = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
local _safeChars = "23456789abcdefghijkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ" -- Excludes ambiguous chars

-- Sequential counters for different prefixes
local _sequentialCounters: { [string]: number } = {}

-- Generated IDs cache for collision detection
local _generatedIds: { [string]: boolean } = {}

-- Statistics
local _stats = {
	generated = 0,
	collisions = 0,
	byFormat = {} :: { [string]: number },
}

local function _getTimestamp(): number
	return math.floor(tick() * 1000)
end

local function _randomChar(charSet: string): string
	local index = math.random(1, string.len(charSet))
	return string.sub(charSet, index, index)
end

local function _randomString(length: number, charSet: string): string
	local result = {}

	for _ = 1, length do
		table.insert(result, _randomChar(charSet))
	end

	return table.concat(result)
end

local function _ensureUnique(id: string, maxRetries: number, generator: () -> string): string
	local attempts = 0
	local currentId = id

	while _generatedIds[currentId] and attempts < maxRetries do
		_stats.collisions += 1
		currentId = generator()
		attempts += 1
	end

	if attempts >= maxRetries then
		-- Add timestamp to ensure uniqueness
		currentId = currentId .. "_" .. _getTimestamp()
	end

	_generatedIds[currentId] = true
	return currentId
end

local function _formatId(id: string, options: IdOptions?): string
	if not options then
		return id
	end

	local result = id

	-- Apply case transformation
	if options.uppercase then
		result = string.upper(result)
	end

	-- Add prefix
	if options.prefix then
		local separator = options.separator or "_"
		result = options.prefix .. separator .. result
	end

	-- Add suffix
	if options.suffix then
		local separator = options.separator or "_"
		result = result .. separator .. options.suffix
	end

	return result
end

local function _incrementStats(format: string): ()
	_stats.generated += 1
	_stats.byFormat[format] = (_stats.byFormat[format] or 0) + 1
end

local IdUtil = {}

function IdUtil.UUID(options: IdOptions?): string
	local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
	local uuid = string.gsub(template, "[xy]", function(char)
		local value = (char == "x") and math.random(0, 15) or math.random(8, 11)
		return string.format("%x", value)
	end)

	_incrementStats("uuid")
	return _formatId(uuid, options)
end

function IdUtil.ShortId(length: number?, options: IdOptions?): string
	length = length or 8
	local opts: IdOptions = if options ~= nil then options else {}

	local charSet = if opts.excludeAmbiguous then _safeChars else _alphanumericChars

	local generator = function()
		return _randomString(length :: number, charSet)
	end

	local id = generator()
	id = _ensureUnique(id, 10, generator)

	_incrementStats("short")
	return _formatId(id, opts)
end

function IdUtil.Numeric(length: number?, options: IdOptions?): string
	length = length or 10

	local generator = function()
		-- Ensure first digit is not 0
		local firstChar = _randomChar("123456789")
		local restChars = _randomString((length :: number) - 1, _numericChars)
		return firstChar .. restChars
	end

	local id = generator()
	id = _ensureUnique(id, 10, generator)

	_incrementStats("numeric")
	return _formatId(id, options)
end

function IdUtil.Hex(length: number?, options: IdOptions?): string
	length = length or 16

	local generator = function()
		return _randomString(length :: number, _hexChars)
	end

	local id = generator()
	id = _ensureUnique(id, 10, generator)

	_incrementStats("hex")
	return _formatId(id, options)
end

function IdUtil.Prefixed(prefix: string, idType: IdFormat?, length: number?): string
	assert(typeof(prefix) == "string", "[IdUtil.Prefixed] Prefix must be a string")

	idType = idType or "short"

	local id: string
	if idType == "uuid" then
		id = IdUtil.UUID()
	elseif idType == "numeric" then
		id = IdUtil.Numeric(length)
	elseif idType == "hex" then
		id = IdUtil.Hex(length)
	else
		id = IdUtil.ShortId(length)
	end

	return prefix .. "_" .. id
end

function IdUtil.Sequential(prefix: string, padding: number?): string
	assert(typeof(prefix) == "string", "[IdUtil.Sequential] Prefix must be a string")

	padding = padding or 3

	if not _sequentialCounters[prefix] then
		_sequentialCounters[prefix] = 0
	end

	_sequentialCounters[prefix] += 1
	local number = _sequentialCounters[prefix]
	local paddedNumber = string.format("%0" .. (padding :: number) .. "d", number)

	_incrementStats("sequential")
	return prefix .. "_" .. paddedNumber
end

function IdUtil.Pattern(pattern: string): string
	assert(typeof(pattern) == "string", "[IdUtil.Pattern] Pattern must be a string")

	local result = string.gsub(pattern, "[#@?]", function(char)
		if char == "#" then
			return _randomChar(_numericChars)
		elseif char == "@" then
			return _randomChar(_alphaChars)
		elseif char == "?" then
			return _randomChar(_alphanumericChars)
		end
		return char
	end)

	_incrementStats("pattern")
	return result
end

function IdUtil.Timestamp(includeRandom: boolean?, format: string?): string
	format = format or "unix"

	local timestamp: string
	local now = _getTimestamp()

	if format == "unix" then
		timestamp = tostring(math.floor(now / 1000))
	elseif format == "compact" then
		local date = os.date("*t", math.floor(now / 1000))
		timestamp =
			string.format("%04d%02d%02d%02d%02d%02d", date.year, date.month, date.day, date.hour, date.min, date.sec)
	else
		timestamp = tostring(now)
	end

	if includeRandom then
		local randomSuffix = _randomString(4, _alphanumericChars)
		timestamp = timestamp .. "_" .. randomSuffix
	end

	_incrementStats("timestamp")
	return timestamp
end

function IdUtil.IsValid(id: string, format: IdFormat): boolean
	assert(typeof(id) == "string", "[IdUtil.IsValid] ID must be a string")
	assert(typeof(format) == "string", "[IdUtil.IsValid] Format must be a string")

	if format == "uuid" then
		return string.match(id, "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
	elseif format == "short" then
		return string.match(id, "^[a-zA-Z0-9]+$") ~= nil
	elseif format == "numeric" then
		return string.match(id, "^%d+$") ~= nil
	elseif format == "hex" then
		return string.match(id, "^%x+$") ~= nil
	end

	return false
end

function IdUtil.GetStats(): {
	generated: number,
	collisions: number,
	cached: number,
	byFormat: { [string]: number },
}
	local cachedCount = 0
	for _ in pairs(_generatedIds) do
		cachedCount += 1
	end

	return {
		generated = _stats.generated,
		collisions = _stats.collisions,
		cached = cachedCount,
		byFormat = _stats.byFormat,
	}
end

function IdUtil.ClearCache(resetStats: boolean?): ()
	_generatedIds = {}
	_sequentialCounters = {}

	if resetStats then
		_stats = {
			generated = 0,
			collisions = 0,
			byFormat = {},
		}
	end
end

function IdUtil.Batch(count: number, generator: () -> string): { string }
	assert(typeof(count) == "number" and count > 0, "[IdUtil.Batch] Count must be a positive number")
	assert(typeof(generator) == "function", "[IdUtil.Batch] Generator must be a function")

	local ids = {}

	for _ = 1, count do
		table.insert(ids, generator())
	end

	return ids
end

return {
	GenerateID = originalGenerateID,
	IdUtil = IdUtil,
}
