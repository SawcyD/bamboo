--!strict

local definitions = {}

local Definitions = {}

function Definitions.Register(definition: any)
	assert(type(definition.id) == "string" and definition.id ~= "", "Collectible definition requires an id")
	assert(definitions[definition.id] == nil, "Duplicate collectible definition: " .. definition.id)
	definitions[definition.id] = table.freeze(definition)
end

function Definitions.Get(id: string): any
	return definitions[id]
end

function Definitions.List(): { any }
	local result = {}
	for _, definition in definitions do
		table.insert(result, definition)
	end
	return result
end

return Definitions
