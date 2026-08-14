--!strict

local Definitions = require(script.Parent.Definitions)

local Models = {}

function Models.GetName(definitionId: string): string?
	local definition = Definitions.Get(definitionId)
	return definition and definition.modelName
end

return Models
