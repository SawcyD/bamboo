--!strict

local Odds = {}

function Odds.Weighted<T>(entries: { { value: T, weight: number } }, random: number?): T
	assert(#entries > 0, "Cannot roll an empty odds table")
	local total = 0
	for _, entry in entries do
		assert(entry.weight > 0, "Odds weights must be positive")
		total += entry.weight
	end
	local target = (random or math.random()) * total
	for _, entry in entries do
		target -= entry.weight
		if target <= 0 then
			return entry.value
		end
	end
	return entries[#entries].value
end

return Odds
