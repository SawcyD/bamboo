--!strict
-- The crates themselves.
--
-- Each crate overlaps the one below it: the cheap crate's best sickle is the
-- expensive crate's floor. That keeps a cheap crate worth opening early and
-- makes upgrading to the next crate a visible jump rather than a reroll.
--
-- Costs are priced against selling: a full 50-bag is $50, so the Wooden Crate
-- is roughly 30 bags for a new player and the Celestial Crate is a long-term
-- goal for a fully upgraded one.

local Definitions = require(script.Parent:WaitForChild("Definitions"))

Definitions.Register({
	id = "wooden_crate",
	name = "Wooden Crate",
	cost = 1500,
	color = Color3.fromRGB(158, 118, 74),
	contents = {
		worn_sickle = 60,
		iron_sickle = 25,
		honed_sickle = 12,
		jade_sickle = 3,
	},
})

Definitions.Register({
	id = "iron_crate",
	name = "Iron Crate",
	cost = 8000,
	color = Color3.fromRGB(176, 186, 198),
	contents = {
		iron_sickle = 45,
		honed_sickle = 30,
		jade_sickle = 16,
		hunters_scythe = 7,
		stormcutter = 2,
	},
})

Definitions.Register({
	id = "jade_crate",
	name = "Jade Crate",
	cost = 40000,
	color = Color3.fromRGB(96, 214, 168),
	contents = {
		jade_sickle = 40,
		hunters_scythe = 28,
		stormcutter = 18,
		harvest_moon = 11,
		dragons_fang = 2.5,
		golden_scythe = 0.5,
	},
})

Definitions.Register({
	id = "celestial_crate",
	name = "Celestial Crate",
	cost = 200000,
	color = Color3.fromRGB(186, 132, 255),
	contents = {
		stormcutter = 38,
		harvest_moon = 30,
		dragons_fang = 20,
		golden_scythe = 11,
		worldreaper = 1,
	},
})

return Definitions
