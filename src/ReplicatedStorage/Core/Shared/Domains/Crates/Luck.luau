--!strict
-- Luck: how far crate odds bend toward the rare end.
--
-- Luck is expressed to the player as a multiplier ("x2.15"). Internally it is
-- the `luck` value `Core:Get("RNG")` takes, where 0 is base odds and higher
-- values scale the rarest entry's weight up hardest. The two differ by one:
--
--	displayed x1.00  →  luck 0    (base odds)
--	displayed x2.15  →  luck 1.15
--
-- Keeping the conversion here means no caller has to remember which is which.

local Luck = {}

-- Nothing can push luck past this, however many sources stack.
Luck.MaxLuck = 4

-- Each friend in the server is worth this much luck, capped below.
Luck.LuckPerFriend = 0.1
Luck.MaxFriendLuck = 0.5

--[[
	Converts a stored luck value into the multiplier shown on the UI.
	@param luck number Internal luck, where 0 is base odds.
	@return number Multiplier for display, where 1 is base odds.
]]
function Luck.ToMultiplier(luck: number): number
	return 1 + math.max(luck, 0)
end

--[[
	Converts a displayed multiplier back into internal luck.
	@param multiplier number Multiplier as shown, where 1 is base odds.
	@return number Internal luck, clamped to the maximum.
]]
function Luck.FromMultiplier(multiplier: number): number
	return math.clamp(multiplier - 1, 0, Luck.MaxLuck)
end

--[[
	Formats luck for the LuckBoost chip.
	@param luck number Internal luck.
	@return string Multiplier text such as "x2.15".
]]
function Luck.Format(luck: number): string
	return string.format("x%.2f", Luck.ToMultiplier(luck))
end

--[[
	Luck contributed by friends in the server.
	@param friendCount number How many friends are in this server.
	@return number Luck from friends, capped at MaxFriendLuck.
]]
function Luck.FromFriends(friendCount: number): number
	return math.min(friendCount * Luck.LuckPerFriend, Luck.MaxFriendLuck)
end

--[[
	Combines every luck source into the value a roll should use.
	@param boost number Luck from an active timed boost; 0 when none.
	@param friends number Luck from friends in the server.
	@return number Total luck, clamped to MaxLuck.
]]
function Luck.Total(boost: number, friends: number): number
	return math.clamp(math.max(boost, 0) + math.max(friends, 0), 0, Luck.MaxLuck)
end

return Luck
