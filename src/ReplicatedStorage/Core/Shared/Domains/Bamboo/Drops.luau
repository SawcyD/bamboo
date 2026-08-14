--!strict
-- Ground drops: bamboo that lands in the field instead of the bag.
--
-- A stalk cut with a full bag still pays out — the overflow falls where the
-- stalk stood and waits to be walked over. That turns "bag full" from wasted
-- swings into a reason to sell and come straight back.

local Drops = {}

-- Drops vanish after this long, so a full-bag player mowing the field can't
-- leave a permanent carpet of parts behind.
Drops.DespawnSeconds = 60

-- Walking this close with room in the bag vacuums a drop up. Matched to the
-- sickle's reach so anything you just cut is already in pickup range.
Drops.PickupRadius = 7

-- Hard ceiling per plot. Past this the oldest drop is cleared to make room.
Drops.MaxPerPlot = 40

-- Drops within this distance of each other merge into one, so a group break
-- leaves a few worthwhile piles rather than a dozen crumbs.
Drops.MergeRadius = 4

-- How long before a drop expires it starts blinking.
Drops.WarnSeconds = 12

--[[
	Fraction of a drop's life that has elapsed.
	@param secondsAlive number Seconds since the drop landed.
	@return number 0 when fresh, 1 at despawn.
]]
function Drops.Age(secondsAlive: number): number
	return math.clamp(secondsAlive / Drops.DespawnSeconds, 0, 1)
end

--[[
	Whether a drop should be blinking to warn it is about to vanish.
	@param secondsAlive number Seconds since the drop landed.
	@return boolean True once the drop is inside its warning window.
]]
function Drops.IsExpiring(secondsAlive: number): boolean
	return secondsAlive >= Drops.DespawnSeconds - Drops.WarnSeconds
end

return Drops
