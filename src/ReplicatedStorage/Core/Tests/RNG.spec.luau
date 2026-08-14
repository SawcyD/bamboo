--!strict

local RNG = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("RNG"))

return function(t)
	local drops = {
		{ name = "Common", weight = 80, rarity = "Common" },
		{ name = "Rare", weight = 15, rarity = "Rare" },
		{ name = "Legendary", weight = 5, rarity = "Legendary" },
	}

	t.test("seeded streams are reproducible", function()
		local a = RNG.NewStream(42)
		local b = RNG.NewStream(42)
		for _ = 1, 10 do
			t.expect(a:Roll(drops).name).toBe(b:Roll(drops).name)
		end
	end)

	t.test("luck increases rare odds without guaranteeing", function()
		local base = RNG.GetChance(drops, "Legendary", 0)
		local lucky = RNG.GetChance(drops, "Legendary", 10)
		t.expect(lucky > base).toBeTruthy()
		t.expect(lucky < 100).toBeTruthy()
		-- common stays possible
		t.expect(RNG.GetChance(drops, "Common", 10) > 0).toBeTruthy()
	end)

	t.test("chances sum to 100", function()
		local total = 0
		for _, name in { "Common", "Rare", "Legendary" } do
			total += RNG.GetChance(drops, name, 3)
		end
		t.expect(total).toBeCloseTo(100, 1e-3)
	end)

	t.test("pity hard cap forces a rare", function()
		local roller = RNG.NewPityRoller({
			isRare = function(entry)
				return entry.rarity == "Legendary"
			end,
			softStart = 4,
			hardCap = 8,
		})
		local _, wasRare = roller:Roll(drops, 0, 8)
		t.expect(wasRare).toBeTruthy()
	end)

	t.test("empty drops throws", function()
		t.expect(function()
			RNG.Roll({})
		end).toThrow()
	end)
end
