--!strict

local StringUtil = {}

-- splits a string by a delimiter pattern
function StringUtil.split(s: string, delimiter: string): { string }
	local parts = {}
	for part in s:gmatch("[^" .. delimiter .. "]+") do
		table.insert(parts, part)
	end
	return parts
end

-- trims leading and trailing whitespace
function StringUtil.trim(s: string): string
	return s:match("^%s*(.-)%s*$") or s
end

-- returns true if s starts with prefix
function StringUtil.startsWith(s: string, prefix: string): boolean
	return s:sub(1, #prefix) == prefix
end

-- returns true if s ends with suffix
function StringUtil.endsWith(s: string, suffix: string): boolean
	return suffix == "" or s:sub(-#suffix) == suffix
end

-- returns true if s contains substring
function StringUtil.contains(s: string, substring: string): boolean
	return s:find(substring, 1, true) ~= nil
end

-- pads a string on the left to length with pad character
function StringUtil.padLeft(s: string, length: number, pad: string?): string
	pad = pad or " "
	while #s < length do
		s = (pad :: string) .. s
	end
	return s
end

-- pads a string on the right to length with pad character
function StringUtil.padRight(s: string, length: number, pad: string?): string
	pad = pad or " "
	while #s < length do
		s = s .. (pad :: string)
	end
	return s
end

-- capitalizes the first character
function StringUtil.capitalize(s: string): string
	return s:sub(1, 1):upper() .. s:sub(2)
end

-- converts camelCase to snake_case
function StringUtil.camelToSnake(s: string): string
	return s:gsub("(%u)", function(c: string)
		return "_" .. c:lower()
	end):gsub("^_", "")
end

return StringUtil
