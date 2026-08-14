--!strict
-- Registry of sickle definitions. Content lives in Catalog; this is the store.

local Types = require(script.Parent:WaitForChild("Types"))

local Definitions = {}

export type Definition = Types.SickleDefinition

local definitions: { [string]: Definition } = {}
local order: { string } = {}

--[[
	Registers a sickle. Rejects duplicates so a typo can't silently shadow one.
	@param definition Definition The sickle to register; frozen on the way in.
]]
function Definitions.Register(definition: Definition)
	assert(type(definition.id) == "string" and definition.id ~= "", "Sickle id is required")
	assert(definitions[definition.id] == nil, "Duplicate sickle: " .. definition.id)
	definitions[definition.id] = table.freeze(definition)
	table.insert(order, definition.id)
end

--[[
	Looks up a sickle by id.
	@param id string Sickle id such as "jade_reaper".
	@return Definition? The definition, or nil for an unknown id.
]]
function Definitions.Get(id: string): Definition?
	return definitions[id]
end

--[[
	Every registered sickle, in registration order.
	@return { Definition } All definitions.
]]
function Definitions.List(): { Definition }
	local list: { Definition } = {}
	for _, id in order do
		table.insert(list, definitions[id])
	end
	return list
end

--[[
	Whether an id refers to a real sickle. Used to validate saved data and
	client requests before acting on them.
	@param id any Value to check.
	@return boolean True only for a registered id.
]]
function Definitions.Exists(id: any): boolean
	return type(id) == "string" and definitions[id] ~= nil
end

return Definitions
