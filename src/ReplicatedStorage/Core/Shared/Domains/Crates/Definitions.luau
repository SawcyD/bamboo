--!strict
-- Registry of crate definitions. Content lives in Catalog; this is the store.

local Definitions = {}

export type Definition = {
	id: string,
	name: string,
	cost: number,
	-- Sickle id → roll weight, relative within this crate.
	contents: { [string]: number },
	color: Color3,
}

local definitions: { [string]: Definition } = {}
local order: { string } = {}

--[[
	Registers a crate. Rejects duplicates and empty content tables, so a crate
	can never be opened for nothing.
	@param definition Definition The crate to register; frozen on the way in.
]]
function Definitions.Register(definition: Definition)
	assert(type(definition.id) == "string" and definition.id ~= "", "Crate id is required")
	assert(definitions[definition.id] == nil, "Duplicate crate: " .. definition.id)
	assert(next(definition.contents) ~= nil, "Crate has no contents: " .. definition.id)
	definitions[definition.id] = table.freeze(definition)
	table.insert(order, definition.id)
end

--[[
	Looks up a crate by id.
	@param id string Crate id such as "jade_crate".
	@return Definition? The definition, or nil for an unknown id.
]]
function Definitions.Get(id: string): Definition?
	return definitions[id]
end

--[[
	Every registered crate, cheapest first.
	@return { Definition } All definitions in catalog order.
]]
function Definitions.List(): { Definition }
	local list: { Definition } = {}
	for _, id in order do
		table.insert(list, definitions[id])
	end
	return list
end

--[[
	Whether an id refers to a real crate, for validating client requests.
	@param id any Value to check.
	@return boolean True only for a registered id.
]]
function Definitions.Exists(id: any): boolean
	return type(id) == "string" and definitions[id] ~= nil
end

return Definitions
