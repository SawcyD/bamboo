--!strict

local sets = {}
local CollectionSets = {}

function CollectionSets.Register(setDefinition: any)
	assert(type(setDefinition.id) == "string", "Collection set requires an id")
	sets[setDefinition.id] = table.freeze(setDefinition)
end

function CollectionSets.Get(id: string): any
	return sets[id]
end

function CollectionSets.List(): { any }
	local result = {}
	for _, setDefinition in sets do
		table.insert(result, setDefinition)
	end
	return result
end

return CollectionSets
