--!strict
--[[ Human-readable time, numbers, and byte sizes for HUD and stats. ]]

export type TimeFormat = "relative" | "absolute" | "duration" | "precise"

export type NumberFormat = "standard" | "scientific" | "compact" | "currency" | "percentage"

export type LocaleOptions = {
	locale: string?,
	timeZone: string?,
	currencyCode: string?,
	currencySymbol: string?,
}

export type FormatOptions = {
	precision: number?,
	showZeros: boolean?,
	useShortUnits: boolean?,
	locale: LocaleOptions?,
}

-- Default locale settings
local _defaultLocale: LocaleOptions = {
	locale = "en-US",
	timeZone = "UTC",
	currencyCode = "USD",
	currencySymbol = "$",
}

-- Time unit definitions
local _timeUnits = {
	{ name = "year", seconds = 31536000, short = "y" },
	{ name = "month", seconds = 2592000, short = "mo" },
	{ name = "week", seconds = 604800, short = "w" },
	{ name = "day", seconds = 86400, short = "d" },
	{ name = "hour", seconds = 3600, short = "h" },
	{ name = "minute", seconds = 60, short = "m" },
	{ name = "second", seconds = 1, short = "s" },
}

-- Data size units
local _dataSizeUnits = {
	{ name = "byte", size = 1, short = "B", plural = "bytes" },
	{ name = "kilobyte", size = 1024, short = "KB", plural = "KB" },
	{ name = "megabyte", size = 1048576, short = "MB", plural = "MB" },
	{ name = "gigabyte", size = 1073741824, short = "GB", plural = "GB" },
	{ name = "terabyte", size = 1099511627776, short = "TB", plural = "TB" },
	{ name = "petabyte", size = 1125899906842624, short = "PB", plural = "PB" },
}

-- Number suffix for compact formatting
local _numberSuffixes = {
	{ value = 1000000000000, suffix = "T" },
	{ value = 1000000000, suffix = "B" },
	{ value = 1000000, suffix = "M" },
	{ value = 1000, suffix = "K" },
}

-- Format cache for performance
local _formatCache: { [string]: string } = {}
local _cacheSize = 0
local _maxCacheSize = 1000

-- Statistics
local _stats = {
	formatsCalculated = 0,
	cacheHits = 0,
	cacheMisses = 0,
}

local function _getTimestamp(): number
	return tick()
end

local function _createCacheKey(value: any, formatType: string, options: FormatOptions?): string
	local key = formatType .. ":" .. tostring(value)

	if options then
		if options.precision then
			key = key .. ":p" .. options.precision
		end
		if options.showZeros then
			key = key .. ":z" .. tostring(options.showZeros)
		end
		if options.useShortUnits then
			key = key .. ":s" .. tostring(options.useShortUnits)
		end
	end

	return key
end

local function _getCachedOrCalculate(cacheKey: string, calculator: () -> string): string
	-- Check cache first
	if _formatCache[cacheKey] then
		_stats.cacheHits += 1
		return _formatCache[cacheKey]
	end

	_stats.cacheMisses += 1

	-- Calculate new result
	local result = calculator()

	-- Store in cache if not full
	if _cacheSize < _maxCacheSize then
		_formatCache[cacheKey] = result
		_cacheSize += 1
	end

	_stats.formatsCalculated += 1
	return result
end

local function _addCommas(numberStr: string): string
	local result = numberStr
	local sign = ""

	-- Handle negative numbers
	if string.sub(result, 1, 1) == "-" then
		sign = "-"
		result = string.sub(result, 2)
	end

	-- Find decimal point
	local decimalPos = string.find(result, "%.")
	local integerPart = if decimalPos then string.sub(result, 1, decimalPos - 1) else result
	local decimalPart = if decimalPos then string.sub(result, decimalPos) else ""

	-- Add commas to integer part
	local formatted = ""
	local len = string.len(integerPart)

	for i = 1, len do
		formatted = formatted .. string.sub(integerPart, i, i)

		if (len - i) % 3 == 0 and i < len then
			formatted = formatted .. ","
		end
	end

	return sign .. formatted .. decimalPart
end

local function _round(num: number, decimals: number): number
	local mult = 10 ^ decimals
	return math.floor(num * mult + 0.5) / mult
end

local function _pluralize(count: number, singular: string, plural: string?): string
	if count == 1 then
		return singular
	else
		return plural or (singular .. "s")
	end
end

local FormatUtil = {}

function FormatUtil.Number(num: number, options: FormatOptions?): string
	assert(typeof(num) == "number", "[FormatUtil.Number] Input must be a number")

	options = options or {}
	local precision = options.precision or nil

	local cacheKey = _createCacheKey(num, "number", options)

	return _getCachedOrCalculate(cacheKey, function()
		local result = num

		-- Apply precision if specified
		if precision then
			result = _round(result, precision)
		end

		local numberStr = tostring(result)

		-- Handle scientific notation
		if string.find(numberStr, "e") then
			return numberStr -- Return as-is for very large/small numbers
		end

		return _addCommas(numberStr)
	end)
end

-- Expanded number abbreviations table (about 50+ common ones)
local _expandedNumberSuffixes = {
	{ value = 1e303, suffix = "Ce" },
	{ value = 1e300, suffix = "Nc" },
	{ value = 1e273, suffix = "Qo" },
	{ value = 1e270, suffix = "No" },
	{ value = 1e243, suffix = "Qv" },
	{ value = 1e240, suffix = "Nv" },
	{ value = 1e213, suffix = "Tt" },
	{ value = 1e210, suffix = "Nd" },
	{ value = 1e183, suffix = "Oc" },
	{ value = 1e180, suffix = "No" },
	{ value = 1e153, suffix = "Sp" },
	{ value = 1e150, suffix = "Nn" },
	{ value = 1e123, suffix = "Sx" },
	{ value = 1e120, suffix = "Ns" },
	{ value = 1e93, suffix = "Qd" },
	{ value = 1e90, suffix = "Nq" },
	{ value = 1e63, suffix = "Vg" },
	{ value = 1e60, suffix = "Nvg" },
	{ value = 1e57, suffix = "U" },
	{ value = 1e54, suffix = "Sp" },
	{ value = 1e51, suffix = "Sd" },
	{ value = 1e48, suffix = "Oc" },
	{ value = 1e45, suffix = "No" },
	{ value = 1e42, suffix = "Td" },
	{ value = 1e39, suffix = "D" },
	{ value = 1e36, suffix = "Ud" },
	{ value = 1e33, suffix = "Dc" },
	{ value = 1e30, suffix = "Nn" },
	{ value = 1e27, suffix = "Oc" },
	{ value = 1e24, suffix = "Y" }, -- Yotta
	{ value = 1e21, suffix = "Z" }, -- Zetta
	{ value = 1e18, suffix = "E" }, -- Exa
	{ value = 1e15, suffix = "P" }, -- Peta
	{ value = 1e12, suffix = "T" }, -- Tera
	{ value = 1e9, suffix = "B" }, -- Billion
	{ value = 1e6, suffix = "M" }, -- Million
	{ value = 1e3, suffix = "K" }, -- Thousand

	-- American system
	{ value = 1e27, suffix = "Oc" },
	{ value = 1e24, suffix = "Sp" },
	{ value = 1e21, suffix = "Sx" },
	{ value = 1e18, suffix = "Qi" },
	{ value = 1e15, suffix = "Qa" },
	{ value = 1e12, suffix = "T" },
	{ value = 1e9, suffix = "B" },
	{ value = 1e6, suffix = "M" },
	{ value = 1e3, suffix = "K" },

	-- index-variant (never hurts to have a bunch)
	{ value = 1e33, suffix = "Dc" },
	{ value = 1e30, suffix = "Nn" },
	{ value = 1e27, suffix = "Oc" },
	{ value = 1e24, suffix = "Y" },
	{ value = 1e21, suffix = "Z" },
	{ value = 1e18, suffix = "E" },
	{ value = 1e15, suffix = "P" },
	{ value = 1e12, suffix = "T" },
	{ value = 1e9, suffix = "B" },
	{ value = 1e6, suffix = "M" },
	{ value = 1e3, suffix = "K" },

	-- Short scale unofficial fun
	{ value = 1e48, suffix = "Qn" },
	{ value = 1e45, suffix = "Qd" },
	{ value = 1e42, suffix = "Td" },
	{ value = 1e39, suffix = "Dd" },
	{ value = 1e36, suffix = "Ud" },
	{ value = 1e33, suffix = "Dc" },
	{ value = 1e30, suffix = "Nn" },
	{ value = 1e27, suffix = "Oc" },
	{ value = 1e24, suffix = "Y" },
	{ value = 1e21, suffix = "Z" },
	{ value = 1e18, suffix = "E" },
	{ value = 1e15, suffix = "P" },
	{ value = 1e12, suffix = "T" },
	{ value = 1e9, suffix = "B" },
	{ value = 1e6, suffix = "M" },
	{ value = 1e3, suffix = "K" },
}
-- There are purposely duplicates for overlapping values so the coverage is broad.

function FormatUtil.Compact(num: number, options: FormatOptions?): string
	assert(typeof(num) == "number", "[FormatUtil.Compact] Input must be a number")

	options = options or {}
	local precision = options.precision or 1

	local cacheKey = _createCacheKey(num, "compact", options)

	return _getCachedOrCalculate(cacheKey, function()
		local absNum = math.abs(num)
		local sign = if num < 0 then "-" else ""

		if absNum < 1000 then
			return tostring(num)
		end

		for _, suffix in ipairs(_expandedNumberSuffixes) do
			if absNum >= suffix.value then
				local value = absNum / suffix.value
				local rounded = _round(value, precision)
				return sign .. tostring(rounded) .. suffix.suffix
			end
		end

		-- If for some reason it's not large enough for any abbreviation, just return the string
		return tostring(num)
	end)
end

function FormatUtil.Currency(num: number, options: FormatOptions?): string
	assert(typeof(num) == "number", "[FormatUtil.Currency] Input must be a number")

	options = options or {}
	local locale = options.locale or _defaultLocale
	local precision = options.precision or 2
	local currencySymbol = locale.currencySymbol or _defaultLocale.currencySymbol

	local cacheKey = _createCacheKey(num, "currency:" .. (currencySymbol or ""), options)

	return _getCachedOrCalculate(cacheKey, function()
		local rounded = _round(num, precision)
		local formatted = _addCommas(string.format("%.2f", rounded))
		return currencySymbol .. formatted
	end)
end

function FormatUtil.FormatMoney(num: number, options: FormatOptions?): string
	assert(typeof(num) == "number", "[FormatUtil.FormatMoney] Input must be a number")

	options = options or {}
	local precision = options.precision or 0 -- Default to 0 decimals for whole money
	local symbol = (options.locale and options.locale.currencySymbol) or "$"

	local cacheKey = _createCacheKey(num, "money:" .. symbol, options)

	return _getCachedOrCalculate(cacheKey, function()
		local formatted = FormatUtil.Number(num, { precision = precision })
		return symbol .. formatted
	end)
end

function FormatUtil.Percentage(num: number, options: FormatOptions?): string
	assert(typeof(num) == "number", "[FormatUtil.Percentage] Input must be a number")

	options = options or {}
	local precision = options.precision or 1

	local cacheKey = _createCacheKey(num, "percentage", options)

	return _getCachedOrCalculate(cacheKey, function()
		local percentage = num * 100
		local rounded = _round(percentage, precision)
		return tostring(rounded) .. "%"
	end)
end

function FormatUtil.Duration(seconds: number, options: FormatOptions?): string
	assert(typeof(seconds) == "number", "[FormatUtil.Duration] Input must be a number")

	options = options or {}
	local useShortUnits = options.useShortUnits ~= false -- Default to true
	local showZeros = options.showZeros or false

	local cacheKey = _createCacheKey(seconds, "duration", options)

	return _getCachedOrCalculate(cacheKey, function()
		if seconds < 1 then
			return "0s"
		end

		local remaining = math.abs(seconds)
		local parts = {}
		local sign = if seconds < 0 then "-" else ""

		for _, unit in ipairs(_timeUnits) do
			local count = math.floor(remaining / unit.seconds)

			if count > 0 or (showZeros and #parts > 0) then
				local unitName = if useShortUnits then unit.short else _pluralize(count, unit.name)
				table.insert(parts, tostring(count) .. (if useShortUnits then unitName else " " .. unitName))
				remaining = remaining % unit.seconds
			end

			-- Stop at minutes for most cases unless very precise
			if #parts >= 3 or (not showZeros and remaining < 1) then
				break
			end
		end

		if #parts == 0 then
			return "0s"
		end

		return sign .. table.concat(parts, " ")
	end)
end

function FormatUtil.TimeAgo(timestamp: number, options: FormatOptions?): string
	assert(typeof(timestamp) == "number", "[FormatUtil.TimeAgo] Input must be a number")

	options = options or {}
	local useShortUnits = options.useShortUnits or false

	local now = _getTimestamp()
	local diff = now - timestamp
	local absoDiff = math.abs(diff)

	local cacheKey = _createCacheKey(timestamp, "timeago:" .. tostring(now), options)

	return _getCachedOrCalculate(cacheKey, function()
		if absoDiff < 5 then
			return "just now"
		end

		local prefix = if diff > 0 then "" else "in "
		local suffix = if diff > 0 then " ago" else ""

		for _, unit in ipairs(_timeUnits) do
			local count = math.floor(absoDiff / unit.seconds)

			if count >= 1 then
				local unitName = if useShortUnits then unit.short else _pluralize(count, unit.name)
				return prefix .. tostring(count) .. " " .. unitName .. suffix
			end
		end

		return "just now"
	end)
end

function FormatUtil.DateTime(timestamp: number, format: string?): string
	assert(typeof(timestamp) == "number", "[FormatUtil.DateTime] Input must be a number")

	format = format or "datetime"

	local cacheKey = _createCacheKey(timestamp, "datetime:" .. format, nil)

	return _getCachedOrCalculate(cacheKey, function()
		local date = os.date("*t", timestamp)

		if format == "date" then
			return string.format("%s %d, %d", os.date("%b", timestamp), date.day, date.year)
		elseif format == "time" then
			local hour = date.hour
			local ampm = "AM"

			if hour >= 12 then
				ampm = "PM"
				if hour > 12 then
					hour = hour - 12
				end
			elseif hour == 0 then
				hour = 12
			end

			return string.format("%d:%02d %s", hour, date.min, ampm)
		elseif format == "datetime" then
			return FormatUtil.DateTime(timestamp, "date") .. " " .. FormatUtil.DateTime(timestamp, "time")
		elseif format == "full" then
			return os.date("%A, %B %d, %Y at %I:%M %p", timestamp)
		else
			return os.date("%c", timestamp)
		end
	end)
end

function FormatUtil.DataSize(bytes: number, options: FormatOptions?): string
	assert(typeof(bytes) == "number", "[FormatUtil.DataSize] Input must be a number")

	options = options or {}
	local precision = options.precision or 1
	local useShortUnits = options.useShortUnits or false

	local cacheKey = _createCacheKey(bytes, "datasize", options)

	return _getCachedOrCalculate(cacheKey, function()
		local absBytes = math.abs(bytes)
		local sign = if bytes < 0 then "-" else ""

		if absBytes == 0 then
			return "0 " .. (if useShortUnits then "B" else "bytes")
		end

		for i = #_dataSizeUnits, 1, -1 do
			local unit = _dataSizeUnits[i]

			if absBytes >= unit.size then
				local value = absBytes / unit.size
				local rounded = _round(value, precision)
				local unitName = if useShortUnits then unit.short else (if rounded == 1 then unit.name else unit.plural)

				local separator = if useShortUnits then "" else " "
				return sign .. tostring(rounded) .. separator .. unitName
			end
		end

		-- Less than 1 byte
		return tostring(bytes) .. " " .. (if useShortUnits then "B" else "bytes")
	end)
end

function FormatUtil.Ordinal(num: number): string
	assert(typeof(num) == "number", "[FormatUtil.Ordinal] Input must be a number")

	local cacheKey = _createCacheKey(num, "ordinal", nil)

	return _getCachedOrCalculate(cacheKey, function()
		local absNum = math.abs(num)
		local lastDigit = absNum % 10
		local lastTwoDigits = absNum % 100

		local suffix = "th"

		if lastTwoDigits < 11 or lastTwoDigits > 13 then
			if lastDigit == 1 then
				suffix = "st"
			elseif lastDigit == 2 then
				suffix = "nd"
			elseif lastDigit == 3 then
				suffix = "rd"
			end
		end

		return tostring(num) .. suffix
	end)
end

function FormatUtil.GetStats(): {
	formatsCalculated: number,
	cacheHits: number,
	cacheMisses: number,
	cacheHitRate: number,
	cacheSize: number,
}
	local totalRequests = _stats.cacheHits + _stats.cacheMisses
	local hitRate = if totalRequests > 0 then (_stats.cacheHits / totalRequests) * 100 else 0

	return {
		formatsCalculated = _stats.formatsCalculated,
		cacheHits = _stats.cacheHits,
		cacheMisses = _stats.cacheMisses,
		cacheHitRate = math.floor(hitRate * 100) / 100,
		cacheSize = _cacheSize,
	}
end

function FormatUtil.ClearCache(resetStats: boolean?): ()
	_formatCache = {}
	_cacheSize = 0

	if resetStats then
		_stats = {
			formatsCalculated = 0,
			cacheHits = 0,
			cacheMisses = 0,
		}
	end

	print("[FormatUtil] Format cache cleared" .. (resetStats and " and stats reset" or ""))
end

function FormatUtil.SetDefaultLocale(locale: LocaleOptions): ()
	assert(typeof(locale) == "table", "[FormatUtil.SetDefaultLocale] Locale must be a table")

	for key, value in pairs(locale) do
		_defaultLocale[key] = value
	end

	-- Clear cache since locale affects formatting
	FormatUtil.ClearCache(false)

	print("[FormatUtil] Default locale updated")
end

return FormatUtil
