--!strict
-- Factory for immutable, string-backed custom enums.

local EnumFactory = {}

local RESERVED_KEYS = {
	Values = true,
	Is = true,
	Get = true,
	Assert = true,
	List = true,
	Metadata = true,
}

local function _copyMetadata(metadata: any): any
	if type(metadata) ~= "table" then
		return nil
	end
	local copy = table.clone(metadata)
	return table.freeze(copy)
end

function EnumFactory.Create(names: { string }, metadata: { [string]: any }?): any
	assert(#names > 0, "Enums: enum requires at least one value")

	local values: { [string]: string } = {}
	local metadataByName: { [string]: any } = {}
	local order = {}
	for _, name in names do
		assert(type(name) == "string" and #name > 0, "Enums: enum names must be non-empty strings")
		assert(not RESERVED_KEYS[name], "Enums: reserved enum name " .. name)
		assert(values[name] == nil, "Enums: duplicate enum value " .. name)
		values[name] = name
		table.insert(order, name)
		metadataByName[name] = _copyMetadata(metadata and metadata[name]) or table.freeze({ Name = name })
	end

	local enum = {
		Values = table.freeze(table.clone(values)),
		Metadata = function(name: string): any?
			return metadataByName[name]
		end,
		Is = function(value: any): boolean
			return type(value) == "string" and values[value] ~= nil
		end,
		Get = function(value: string): string?
			return values[value]
		end,
		Assert = function(value: any): string
			assert(type(value) == "string" and values[value] ~= nil, "Invalid enum value: " .. tostring(value))
			return value
		end,
		List = function(): { string }
			return table.clone(order)
		end,
	}

	for name, value in values do
		enum[name] = value
	end
	return table.freeze(enum)
end

return EnumFactory
