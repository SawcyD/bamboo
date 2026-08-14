--!strict
-- Harvesting combo: the reward for staying in the field and chaining cuts.
--
-- A combo counts *stalks felled*, nothing else. Damaging a stalk without
-- breaking it, collecting a drop, selling, and buying upgrades all leave it
-- untouched — so the number always means "bamboo I cut".
--
-- Every value the combo affects lives here, so tuning is one file rather than a
-- hunt through the service and three controllers. The bonuses are deliberately
-- small: permanent upgrades stay the primary progression, and a combo should
-- read as "I'm playing well and the game is heating up", not as a replacement
-- for buying Swing Speed.

local Combo = {}

-- ── timing ───────────────────────────────────────────────────────────────────

-- Grace period after the last break before the combo drops. Generous enough to
-- walk between neighbouring clumps, short enough that standing still ends it.
Combo.TimeoutSeconds = 3.5

-- Combos above this still count, but stop scaling the feel effects — otherwise
-- a 300 combo would just be a wall of noise.
Combo.FeelCeiling = 100

-- ── milestones ───────────────────────────────────────────────────────────────

Combo.Milestones = table.freeze({ 10, 25, 50, 100, 200 })

-- ── rewards ──────────────────────────────────────────────────────────────────

export type Rewards = {
	-- Extra walk speed in studs/sec, applied server-side to the Humanoid.
	moveSpeed: number,
	-- Fraction the swing cooldown is shortened by, e.g. 0.08 for 8% faster.
	swingSpeed: number,
	-- Fraction added to every stalk's bamboo value, e.g. 0.15 for +15%.
	value: number,
	-- Luck applied when a cut stalk reseeds, biasing it toward rarer bamboo.
	rarityLuck: number,
}

-- Thresholds are checked highest-first, and each tier *replaces* the one below
-- rather than stacking, so the numbers here are absolute.
local TIERS: { { at: number, rewards: Rewards } } = {
	{ at = 100, rewards = { moveSpeed = 4, swingSpeed = 0.10, value = 0.15, rarityLuck = 0.5 } },
	{ at = 50, rewards = { moveSpeed = 3, swingSpeed = 0.08, value = 0.10, rarityLuck = 0 } },
	{ at = 25, rewards = { moveSpeed = 2, swingSpeed = 0.06, value = 0, rarityLuck = 0 } },
	{ at = 10, rewards = { moveSpeed = 2, swingSpeed = 0, value = 0, rarityLuck = 0 } },
}

local NO_REWARDS: Rewards = table.freeze({
	moveSpeed = 0,
	swingSpeed = 0,
	value = 0,
	rarityLuck = 0,
})

--[[
	The bonuses active at a given combo.
	Server-side callers own the real values; the client may call this to preview
	but must never send the result anywhere.
	@param combo number Current combo count.
	@return Rewards Bonuses at that combo; all zero below the first threshold.
]]
function Combo.Rewards(combo: number): Rewards
	for _, tier in TIERS do
		if combo >= tier.at then
			return tier.rewards
		end
	end
	return NO_REWARDS
end

--[[
	Applies the combo's value bonus to one stalk's reward, carrying the fraction.

	Bamboo is whole units and a Normal stalk is worth 2, so flooring each stalk
	independently would throw a +10% bonus away entirely — the tier would be
	invisible for exactly the bamboo a new player cuts most. Carrying the
	remainder across the streak pays a whole extra bamboo every fifth stalk
	instead, which is what +10% actually means.

	@param reward number The stalk's reward before the combo bonus.
	@param valueBonus number Fractional bonus from Rewards().value.
	@param remainder number Fraction carried from earlier stalks in this streak.
	@return number The reward to grant, always a whole number.
	@return number The new remainder to carry forward.
]]
function Combo.ApplyValueBonus(reward: number, valueBonus: number, remainder: number): (number, number)
	if valueBonus <= 0 then
		return reward, remainder
	end

	local carried = remainder + reward * valueBonus
	local whole = math.floor(carried)
	return reward + whole, carried - whole
end

--[[
	The combo at which the next reward tier unlocks, for UI hints.
	@param combo number Current combo count.
	@return number? The next threshold, or nil once every tier is active.
]]
function Combo.NextRewardAt(combo: number): number?
	local best: number? = nil
	for _, tier in TIERS do
		if tier.at > combo and (best == nil or tier.at < best) then
			best = tier.at
		end
	end
	return best
end

-- ── milestones ───────────────────────────────────────────────────────────────

--[[
	The milestone crossed by going from one combo to another.
	A single swing can leap past several; the highest one is what gets announced,
	so a four-stalk break never fires two callouts at once.
	@param before number Combo before the swing.
	@param after number Combo after the swing.
	@return number? The milestone crossed, or nil when none was.
]]
function Combo.MilestoneCrossed(before: number, after: number): number?
	local crossed: number? = nil
	for _, milestone in Combo.Milestones do
		if before < milestone and after >= milestone then
			if crossed == nil or milestone > crossed then
				crossed = milestone
			end
		end
	end
	return crossed
end

-- ── presentation ─────────────────────────────────────────────────────────────

--[[
	How far along the combo ladder a streak is, for scaling effects.
	@param combo number Current combo count.
	@return number 0 at no combo, 1 at the feel ceiling.
]]
function Combo.Heat(combo: number): number
	return math.clamp(combo / Combo.FeelCeiling, 0, 1)
end

-- Visual tiers for the HUD. Each is a colour and a label; the HUD gets more
-- energetic as the tier climbs.
local UI_TIERS = table.freeze({
	{ at = 0, color = Color3.fromRGB(255, 255, 255) },
	{ at = 10, color = Color3.fromRGB(150, 255, 160) },
	{ at = 25, color = Color3.fromRGB(120, 210, 255) },
	{ at = 50, color = Color3.fromRGB(255, 196, 96) },
	{ at = 100, color = Color3.fromRGB(255, 120, 130) },
	{ at = 200, color = Color3.fromRGB(216, 128, 255) },
})

--[[
	The colour the combo counter should show at a given combo.
	@param combo number Current combo count.
	@return Color3 Tier colour, escalating with the streak.
]]
function Combo.Color(combo: number): Color3
	local color = UI_TIERS[1].color
	for _, tier in UI_TIERS do
		if combo >= tier.at then
			color = tier.color
		end
	end
	return color
end

--[[
	Playback pitch for the collection ladder, so a hot combo sounds hotter.
	@param combo number Current combo count.
	@return number Multiplier applied to collection/hit sounds.
]]
function Combo.Pitch(combo: number): number
	return 1 + Combo.Heat(combo) * 0.45
end

return Combo
