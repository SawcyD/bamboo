--!strict

local Domains = script.Parent.Parent:WaitForChild("Shared"):WaitForChild("Domains")
local Sickles = require(Domains:WaitForChild("Sickles"))
local Crates = require(Domains:WaitForChild("Crates"))
local Bamboo = require(Domains:WaitForChild("Bamboo"))

return function(t)
	-- ── sickles ──────────────────────────────────────────────────────────────

	t.test("the starter sickle exists and is the fallback", function()
		local starter = Sickles.Definitions.Get(Sickles.Definitions.StarterId)
		t.expect(starter).toBeTruthy()
		t.expect(Sickles.Stats.Resolve(nil).id).toBe(Sickles.Definitions.StarterId)
		t.expect(Sickles.Stats.Resolve("not_a_sickle").id).toBe(Sickles.Definitions.StarterId)
	end)

	t.test("the starter sickle matches the base tool it replaced", function()
		local starter = Sickles.Stats.Resolve(Sickles.Definitions.StarterId)
		t.expect(starter.damage).toBe(Bamboo.Tool.Damage)
		t.expect(starter.range).toBe(Bamboo.Tool.Range)
		t.expect(starter.baseMultiHit).toBe(Bamboo.Tool.BaseMultiHit)
	end)

	t.test("every sickle has a known tier and stays inside the stat budget", function()
		for _, sickle in Sickles.Definitions.List() do
			t.expect(Sickles.Tiers.Definitions[sickle.tier]).toBeTruthy()
			-- Stalks have 3 health, so damage above 3 would be wasted.
			t.expect(sickle.damage >= 1 and sickle.damage <= 3).toBeTruthy()
			t.expect(sickle.range >= Bamboo.Tool.Range).toBeTruthy()
			t.expect(sickle.baseMultiHit >= Bamboo.Tool.BaseMultiHit).toBeTruthy()
		end
	end)

	t.test("every sickle ability is a real ability with a potency", function()
		for _, sickle in Sickles.Definitions.List() do
			if sickle.ability then
				t.expect(Sickles.Abilities.Get(sickle.ability)).toBeTruthy()
				t.expect(type(sickle.abilityPotency)).toBe("number")
				t.expect(Sickles.Abilities.Describe(sickle.ability, sickle.abilityPotency or 0)).toBeTruthy()
			end
		end
	end)

	t.test("tier ranks order worst to best", function()
		for index = 2, #Sickles.Tiers.Order do
			local previous = Sickles.Tiers.Order[index - 1]
			local current = Sickles.Tiers.Order[index]
			t.expect(Sickles.Tiers.Rank(current) > Sickles.Tiers.Rank(previous)).toBeTruthy()
			t.expect(Sickles.Tiers.Best(previous, current)).toBe(current)
		end
	end)

	t.test("sickle sets the base multi-hit and the upgrade adds on top", function()
		local golden = Sickles.Definitions.Get("golden_scythe")
		local stats = Sickles.Stats.Compute("golden_scythe", 0, 4, Bamboo.Tool.BaseSwingTime)
		-- +1 target every two levels, exactly as the Multi-Hit upgrade does alone.
		t.expect(stats.multiHit).toBe(golden.baseMultiHit + 2)
	end)

	t.test("swing time comes from upgrades, not the sickle", function()
		local a = Sickles.Stats.Compute("starter_sickle", 3, 0, Bamboo.Tool.BaseSwingTime)
		local b = Sickles.Stats.Compute("worldreaper", 3, 0, Bamboo.Tool.BaseSwingTime)
		t.expect(a.swingTime).toBe(b.swingTime)
		t.expect(a.swingTime).toBe(Bamboo.Value.SwingTime(3))
	end)

	-- ── crates ───────────────────────────────────────────────────────────────

	t.test("every crate only contains real sickles", function()
		for _, crate in Crates.Definitions.List() do
			for sickleId in crate.contents do
				t.expect(Sickles.Definitions.Exists(sickleId)).toBe(true)
			end
		end
	end)

	t.test("crate odds total 100 percent", function()
		for _, crate in Crates.Definitions.List() do
			local total = 0
			for _, entry in Crates.Odds.Entries(crate.id) do
				total += entry.chance
			end
			t.expect(total).toBeCloseTo(100, 0.001)
		end
	end)

	t.test("crate odds are listed rarest first", function()
		for _, crate in Crates.Definitions.List() do
			local entries = Crates.Odds.Entries(crate.id)
			for index = 2, #entries do
				t.expect(entries[index].chance >= entries[index - 1].chance).toBeTruthy()
			end
		end
	end)

	t.test("crates get more expensive as their peak tier rises", function()
		local list = Crates.Definitions.List()
		for index = 2, #list do
			local previous = list[index - 1]
			local current = list[index]
			t.expect(current.cost > previous.cost).toBeTruthy()
			local previousPeak = Sickles.Tiers.Rank(Crates.Odds.PeakTier(previous.id))
			local currentPeak = Sickles.Tiers.Rank(Crates.Odds.PeakTier(current.id))
			t.expect(currentPeak >= previousPeak).toBeTruthy()
		end
	end)

	t.test("rolls are reproducible from a seed and always land in the crate", function()
		for _, crate in Crates.Definitions.List() do
			local a, b = Random.new(99), Random.new(99)
			for _ = 1, 25 do
				local rolled = Crates.Odds.Roll(crate.id, a)
				t.expect(rolled).toBe(Crates.Odds.Roll(crate.id, b))
				t.expect(crate.contents[rolled :: string]).toBeTruthy()
			end
		end
	end)

	t.test("unknown crates roll nothing rather than erroring", function()
		t.expect(Crates.Odds.Roll("not_a_crate", Random.new())).toBeNil()
		t.expect(Crates.Odds.TotalWeight("not_a_crate")).toBe(0)
		t.expect(#Crates.Odds.Entries("not_a_crate")).toBe(0)
	end)

	t.test("bulk amounts never exceed the declared maximum", function()
		for _, amount in Crates.BulkAmounts do
			t.expect(amount >= 1 and amount <= Crates.MaxBulk).toBeTruthy()
		end
	end)

	-- ── luck ─────────────────────────────────────────────────────────────────

	t.test("luck converts between internal value and displayed multiplier", function()
		t.expect(Crates.Luck.ToMultiplier(0)).toBe(1)
		t.expect(Crates.Luck.ToMultiplier(1.15)).toBeCloseTo(2.15, 0.0001)
		t.expect(Crates.Luck.FromMultiplier(2.15)).toBeCloseTo(1.15, 0.0001)
		t.expect(Crates.Luck.Format(1.15)).toBe("x2.15")
	end)

	t.test("luck never goes negative or past its cap", function()
		t.expect(Crates.Luck.FromMultiplier(0.5)).toBe(0)
		t.expect(Crates.Luck.Total(-5, -5)).toBe(0)
		t.expect(Crates.Luck.Total(99, 99)).toBe(Crates.Luck.MaxLuck)
	end)

	t.test("friend luck is capped however many friends are present", function()
		t.expect(Crates.Luck.FromFriends(0)).toBe(0)
		t.expect(Crates.Luck.FromFriends(100)).toBe(Crates.Luck.MaxFriendLuck)
	end)

	t.test("odds still total 100 percent with luck applied", function()
		for _, crate in Crates.Definitions.List() do
			for _, luck in { 0, 0.5, 2, Crates.Luck.MaxLuck } do
				local total = 0
				for _, entry in Crates.Odds.Entries(crate.id, luck) do
					total += entry.chance
				end
				t.expect(total).toBeCloseTo(100, 0.001)
			end
		end
	end)

	t.test("luck raises rare odds and lowers common ones", function()
		local crateId = "jade_crate"
		local base = Crates.Odds.Entries(crateId, 0)
		local rarest = base[1].sickleId
		local commonest = base[#base].sickleId

		t.expect(Crates.Odds.ChanceOf(crateId, rarest, 2) > Crates.Odds.ChanceOf(crateId, rarest, 0)).toBeTruthy()
		t.expect(Crates.Odds.ChanceOf(crateId, commonest, 2) < Crates.Odds.ChanceOf(crateId, commonest, 0)).toBeTruthy()
	end)

	t.test("luck never makes a rare drop certain", function()
		for _, crate in Crates.Definitions.List() do
			for _, entry in Crates.Odds.Entries(crate.id, Crates.Luck.MaxLuck) do
				t.expect(entry.chance < 100).toBeTruthy()
				t.expect(entry.chance > 0).toBeTruthy()
			end
		end
	end)

	t.test("auto-open paces itself slower than the server rate limit", function()
		-- The OpenCrate channel allows 8 messages a second.
		t.expect(Crates.AutoOpenIntervalSeconds > 1 / 8).toBeTruthy()
	end)
end
