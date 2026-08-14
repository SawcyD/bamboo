--!strict

local TableUtil = {}

-- returns a shallow copy of a table
function TableUtil.copy<T>(t: { T }): { T }
	return table.clone(t)
end

-- returns a deep copy of a table
function TableUtil.deepCopy(t: any): any
	if type(t) ~= "table" then
		return t
	end
	local copy = {}
	for k, v in t do
		copy[k] = TableUtil.deepCopy(v)
	end
	return copy
end

-- merges source into target, returns target
function TableUtil.merge<T>(target: { [any]: T }, source: { [any]: T }): { [any]: T }
	for k, v in source do
		target[k] = v
	end
	return target
end

-- returns all keys of a dictionary
function TableUtil.keys(t: { [any]: any }): { any }
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	return keys
end

-- returns all values of a dictionary
function TableUtil.values(t: { [any]: any }): { any }
	local vals = {}
	for _, v in t do
		table.insert(vals, v)
	end
	return vals
end

-- returns true if predicate returns true for any element
function TableUtil.some<T>(t: { T }, predicate: (T) -> boolean): boolean
	for _, v in t do
		if predicate(v) then
			return true
		end
	end
	return false
end

-- returns true if predicate returns true for every element
function TableUtil.every<T>(t: { T }, predicate: (T) -> boolean): boolean
	for _, v in t do
		if not predicate(v) then
			return false
		end
	end
	return true
end

-- filters elements by predicate
function TableUtil.filter<T>(t: { T }, predicate: (T) -> boolean): { T }
	local result = {}
	for _, v in t do
		if predicate(v) then
			table.insert(result, v)
		end
	end
	return result
end

-- maps elements through transform
function TableUtil.map<T, U>(t: { T }, transform: (T) -> U): { U }
	local result = {}
	for i, v in t do
		result[i] = transform(v)
	end
	return result
end

-- finds first element matching predicate, returns value and index
function TableUtil.find<T>(t: { T }, predicate: (T) -> boolean): (T?, number?)
	for i, v in t do
		if predicate(v) then
			return v, i
		end
	end
	return nil, nil
end

return TableUtil
