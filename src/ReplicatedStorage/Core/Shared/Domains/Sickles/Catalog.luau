--!strict
-- The sickles themselves.
--
-- Stat budget, deliberately narrow so the ladder stays readable:
--   damage      1–3   (stalks have 3 health, so 3 is a one-shot; never go past it)
--   range       7–15  (the starter's 7 is the floor)
--   multi-hit   3–8   (base only; the Multi-Hit upgrade adds on top of this)
--
-- Abilities are what make the top tiers exciting; stats alone would just be
-- "the same thing, slightly more".

local Definitions = require(script.Parent:WaitForChild("Definitions"))

-- ── Common ───────────────────────────────────────────────────────────────────

Definitions.Register({
	id = "starter_sickle",
	name = "Starter Sickle",
	tier = "Common",
	damage = 1,
	range = 7,
	baseMultiHit = 3,
	bladeColor = Color3.fromRGB(214, 220, 228),
	trailColor = Color3.fromRGB(190, 255, 170),
})

Definitions.Register({
	id = "worn_sickle",
	name = "Worn Sickle",
	tier = "Common",
	damage = 1,
	range = 8,
	baseMultiHit = 3,
	bladeColor = Color3.fromRGB(168, 160, 148),
	trailColor = Color3.fromRGB(196, 210, 180),
})

-- ── Uncommon ─────────────────────────────────────────────────────────────────

Definitions.Register({
	id = "iron_sickle",
	name = "Iron Sickle",
	tier = "Uncommon",
	damage = 1,
	range = 9,
	baseMultiHit = 4,
	bladeColor = Color3.fromRGB(196, 204, 214),
	trailColor = Color3.fromRGB(150, 226, 160),
})

Definitions.Register({
	id = "honed_sickle",
	name = "Honed Sickle",
	tier = "Uncommon",
	damage = 2,
	range = 7,
	baseMultiHit = 3,
	bladeColor = Color3.fromRGB(228, 236, 244),
	trailColor = Color3.fromRGB(150, 226, 160),
})

-- ── Rare ─────────────────────────────────────────────────────────────────────

Definitions.Register({
	id = "jade_sickle",
	name = "Jade Sickle",
	tier = "Rare",
	damage = 2,
	range = 10,
	baseMultiHit = 4,
	bladeColor = Color3.fromRGB(96, 214, 168),
	trailColor = Color3.fromRGB(94, 200, 255),
	ability = "Chain",
	abilityPotency = 0.15,
})

Definitions.Register({
	id = "hunters_scythe",
	name = "Hunter's Scythe",
	tier = "Rare",
	damage = 1,
	range = 12,
	baseMultiHit = 5,
	bladeColor = Color3.fromRGB(148, 176, 220),
	trailColor = Color3.fromRGB(94, 162, 255),
	ability = "Magnet",
	abilityPotency = 1,
})

-- ── Epic ─────────────────────────────────────────────────────────────────────

Definitions.Register({
	id = "stormcutter",
	name = "Stormcutter",
	tier = "Epic",
	damage = 2,
	range = 11,
	baseMultiHit = 5,
	bladeColor = Color3.fromRGB(186, 148, 255),
	trailColor = Color3.fromRGB(178, 106, 255),
	ability = "Chain",
	abilityPotency = 0.30,
})

Definitions.Register({
	id = "harvest_moon",
	name = "Harvest Moon",
	tier = "Epic",
	damage = 2,
	range = 10,
	baseMultiHit = 5,
	bladeColor = Color3.fromRGB(226, 208, 255),
	trailColor = Color3.fromRGB(178, 106, 255),
	ability = "Bountiful",
	abilityPotency = 0.20,
})

-- ── Legendary ────────────────────────────────────────────────────────────────

Definitions.Register({
	id = "dragons_fang",
	name = "Dragon's Fang",
	tier = "Legendary",
	damage = 3,
	range = 12,
	baseMultiHit = 6,
	bladeColor = Color3.fromRGB(255, 168, 72),
	trailColor = Color3.fromRGB(255, 186, 64),
	ability = "Reaper",
	abilityPotency = 0.15,
})

Definitions.Register({
	id = "golden_scythe",
	name = "Golden Scythe",
	tier = "Legendary",
	damage = 2,
	range = 13,
	baseMultiHit = 7,
	bladeColor = Color3.fromRGB(255, 214, 110),
	trailColor = Color3.fromRGB(255, 186, 64),
	ability = "Bountiful",
	abilityPotency = 0.35,
})

-- ── Mythic ───────────────────────────────────────────────────────────────────

Definitions.Register({
	id = "worldreaper",
	name = "Worldreaper",
	tier = "Mythic",
	damage = 3,
	range = 15,
	baseMultiHit = 8,
	bladeColor = Color3.fromRGB(255, 118, 142),
	trailColor = Color3.fromRGB(255, 92, 118),
	ability = "Reaper",
	abilityPotency = 0.30,
})

-- The sickle every player starts with and can always fall back to.
Definitions.StarterId = "starter_sickle"

return Definitions
