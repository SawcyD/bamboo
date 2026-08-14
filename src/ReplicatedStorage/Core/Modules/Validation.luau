--!strict
-- Small runtime validation helpers for profiles, payloads, and definitions.

local Validation = {}

export type Rule = {
	Type: string?,
	Required: boolean?,
	Min: number?,
	Max: number?,
	Validate: ((value: any) -> boolean)?,
}

function Validation.IsFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Validation.Type(value: any, expected: string): boolean
	return type(value) == expected
end

function Validation.Number(value: any, minimum: number?, maximum: number?): boolean
	if not Validation.IsFiniteNumber(value) then
		return false
	end
	return (not minimum or value >= minimum) and (not maximum or value <= maximum)
end

function Validation.String(value: any, minimumLength: number?, maximumLength: number?): boolean
	if type(value) ~= "string" then
		return false
	end
	return (not minimumLength or #value >= minimumLength) and (not maximumLength or #value <= maximumLength)
end

function Validation.Enum(value: any, enum: any): boolean
	return enum and type(enum.Is) == "function" and enum.Is(value) == true
end

function Validation.Instance(value: any, className: string?): boolean
	if typeof(value) ~= "Instance" then
		return false
	end
	return not className or value:IsA(className)
end

function Validation.Table(value: any, schema: { [string]: Rule }): (boolean, { string })
	if type(value) ~= "table" then
		return false, { "expected table" }
	end
	local errors = {}
	for key, rule in schema do
		local current = value[key]
		if current == nil and rule.Required then
			table.insert(errors, key .. " is required")
			continue
		end
		if current == nil then
			continue
		end
		if rule.Type and type(current) ~= rule.Type then
			table.insert(errors, key .. " must be a " .. rule.Type)
			continue
		end
		if rule.Min or rule.Max then
			if not Validation.Number(current, rule.Min, rule.Max) then
				table.insert(errors, key .. " is outside the allowed range")
				continue
			end
		end
		if rule.Validate and not rule.Validate(current) then
			table.insert(errors, key .. " failed validation")
		end
	end
	return #errors == 0, errors
end

function Validation.Assert(condition: boolean, message: string)
	assert(condition, "Validation: " .. message)
end

return Validation
