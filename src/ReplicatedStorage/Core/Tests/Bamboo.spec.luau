--!strict

local Bamboo = require(script.Parent.Parent:WaitForChild("Shared"):WaitForChild("Domains"):WaitForChild("Bamboo"))

return function(t)
	t.test("rarity chances total 100", function()
		local total = 0
		for _, id in Bamboo.Rarity.RollOrder do
			total += Bamboo.Rarity.Definitions[id].chance
		end
		t.expect(total).toBe(100)
	end)

	t.test("every defined rarity is in the roll order", function()
		local count = 0
		for _ in Bamboo.Rarity.Definitions do
			count += 1
		end
		t.expect(count).toBe(#Bamboo.Rarity.RollOrder)
	end)

	t.test("unknown rarities fall back to Normal instead of erroring", function()
		t.expect(Bamboo.Rarity.Get("not_a_rarity").id).toBe("Normal")
	end)

	t.test("rarity rolls are reproducible from a seed", function()
		local a, b = Random.new(1234), Random.new(1234)
		for _ = 1, 20 do
			t.expect(Bamboo.Rarity.Roll(a)).toBe(Bamboo.Rarity.Roll(b))
		end
	end)

	t.test("growth stages walk Shoot to Young to Mature", function()
		local field = Bamboo.Field
		t.expect(field.StageAt(0)).toBe(field.Stage.Shoot)
		t.expect(field.StageAt(field.ShootSeconds)).toBe(field.Stage.Young)
		t.expect(field.StageAt(field.RegrowSeconds)).toBe(field.Stage.Mature)
	end)

	t.test("swing time starts at the tool's base swing time", function()
		t.expect(Bamboo.Value.SwingTime(0)).toBe(Bamboo.Tool.BaseSwingTime)
	end)

	t.test("swing time matches the design table", function()
		local expected = { [1] = 0.74, [2] = 0.69, [3] = 0.65, [5] = 0.57, [8] = 0.49 }
		for level, seconds in expected do
			t.expect(Bamboo.Value.SwingTime(level)).toBeCloseTo(seconds, 0.01)
		end
	end)

	t.test("swing time never increases with level", function()
		for level = 1, 25 do
			t.expect(Bamboo.Value.SwingTime(level) < Bamboo.Value.SwingTime(level - 1)).toBeTruthy()
		end
	end)

	t.test("multi-hit follows the every-two-levels progression", function()
		local expected = { [0] = 3, [1] = 3, [2] = 4, [3] = 4, [4] = 5, [5] = 5, [6] = 6 }
		for level, targets in expected do
			t.expect(Bamboo.Value.MultiHitTargets(level)).toBe(targets)
		end
	end)

	t.test("yield follows the every-two-levels progression", function()
		local expected = { [0] = 2, [1] = 2, [2] = 3, [3] = 3, [4] = 4, [5] = 4, [6] = 5 }
		for level, perStalk in expected do
			t.expect(Bamboo.Value.YieldPerStalk(level)).toBe(perStalk)
		end
	end)

	t.test("stalk reward applies the rarity multiplier", function()
		t.expect(Bamboo.Value.StalkReward("Normal", 0)).toBe(2)
		t.expect(Bamboo.Value.StalkReward("Tall", 0)).toBe(6)
		t.expect(Bamboo.Value.StalkReward("Thick", 0)).toBe(20)
	end)

	t.test("storage adds capacity on top of the base bag", function()
		t.expect(Bamboo.Value.BagCapacity(0)).toBe(Bamboo.Economy.BagCapacity)
		t.expect(Bamboo.Value.BagCapacity(4)).toBe(Bamboo.Economy.BagCapacity + 100)
	end)

	t.test("growth speed only ever shortens regrow time", function()
		t.expect(Bamboo.Value.RegrowSeconds(0)).toBe(Bamboo.Field.RegrowSeconds)
		for level = 1, 20 do
			t.expect(Bamboo.Value.RegrowSeconds(level) < Bamboo.Value.RegrowSeconds(level - 1)).toBeTruthy()
		end
	end)

	t.test("growth stages stay proportional at every growth speed level", function()
		for _, level in { 0, 5, 20 } do
			local regrow = Bamboo.Value.RegrowSeconds(level)
			t.expect(Bamboo.Value.StageAt(0, level)).toBe(Bamboo.Field.Stage.Shoot)
			t.expect(Bamboo.Value.StageAt(Bamboo.Value.ShootSeconds(level), level)).toBe(Bamboo.Field.Stage.Young)
			t.expect(Bamboo.Value.StageAt(regrow, level)).toBe(Bamboo.Field.Stage.Mature)
		end
	end)

	t.test("density grows the field three stalks at a time", function()
		t.expect(Bamboo.Value.MaxStalks(0)).toBe(Bamboo.Field.MaxStalks)
		t.expect(Bamboo.Value.MaxStalks(3)).toBe(Bamboo.Field.MaxStalks + 9)
	end)

	t.test("plots can be pre-built for the largest reachable field", function()
		local density = Bamboo.Upgrades.Get("Density")
		t.expect(Bamboo.Value.MaxPossibleStalks()).toBe(Bamboo.Value.MaxStalks(density.maxLevel))
		t.expect(Bamboo.Value.MaxPossibleStalks() >= Bamboo.Field.MaxStalks).toBeTruthy()
	end)

	t.test("every upgrade in the order has a stat formula", function()
		for _, id in Bamboo.Upgrades.Order do
			t.expect(Bamboo.Value.StatAtLevel(id, 1) > 0).toBeTruthy()
		end
	end)

	t.test("drop despawn leaves a warning window", function()
		t.expect(Bamboo.Drops.IsExpiring(0)).toBe(false)
		t.expect(Bamboo.Drops.IsExpiring(Bamboo.Drops.DespawnSeconds)).toBe(true)
		t.expect(Bamboo.Drops.WarnSeconds < Bamboo.Drops.DespawnSeconds).toBeTruthy()
	end)

	t.test("upgrades start at their advertised price", function()
		t.expect(Bamboo.Value.UpgradeCost("SwingSpeed", 0)).toBe(150)
		t.expect(Bamboo.Value.UpgradeCost("MultiHit", 0)).toBe(400)
		t.expect(Bamboo.Value.UpgradeCost("Yield", 0)).toBe(250)
	end)

	t.test("upgrade cost grows with level", function()
		for _, id in Bamboo.Upgrades.Order do
			t.expect(Bamboo.Value.UpgradeCost(id, 3) > Bamboo.Value.UpgradeCost(id, 2)).toBeTruthy()
		end
	end)

	t.test("an unknown upgrade is unaffordable rather than free", function()
		t.expect(Bamboo.Value.UpgradeCost("NotAnUpgrade", 0)).toBe(math.huge)
		t.expect(Bamboo.Value.CanUpgrade("NotAnUpgrade", 0)).toBe(false)
	end)

	t.test("upgrades stop at their max level", function()
		for _, definition in Bamboo.Upgrades.List() do
			t.expect(Bamboo.Value.CanUpgrade(definition.id, definition.maxLevel)).toBe(false)
			t.expect(Bamboo.Value.CanUpgrade(definition.id, definition.maxLevel - 1)).toBe(true)
		end
	end)

	-- ── combo ────────────────────────────────────────────────────────────────

	t.test("no combo means no bonuses", function()
		local rewards = Bamboo.Combo.Rewards(0)
		t.expect(rewards.moveSpeed).toBe(0)
		t.expect(rewards.swingSpeed).toBe(0)
		t.expect(rewards.value).toBe(0)
		t.expect(rewards.rarityLuck).toBe(0)
	end)

	t.test("combo rewards only ever improve with the streak", function()
		local previous = Bamboo.Combo.Rewards(0)
		for combo = 1, 250 do
			local rewards = Bamboo.Combo.Rewards(combo)
			t.expect(rewards.moveSpeed >= previous.moveSpeed).toBeTruthy()
			t.expect(rewards.swingSpeed >= previous.swingSpeed).toBeTruthy()
			t.expect(rewards.value >= previous.value).toBeTruthy()
			t.expect(rewards.rarityLuck >= previous.rarityLuck).toBeTruthy()
			previous = rewards
		end
	end)

	t.test("combo bonuses stay conservative against permanent upgrades", function()
		local best = Bamboo.Combo.Rewards(1000)
		-- A maxed combo must not out-scale even a few levels of Swing Speed,
		-- or the permanent upgrade stops being the primary progression.
		local upgradeGain = 1 - Bamboo.Value.SwingTime(3) / Bamboo.Value.SwingTime(0)
		t.expect(best.swingSpeed < upgradeGain).toBeTruthy()
		-- Likewise value: Yield doubles output by level 4.
		t.expect(best.value < 1).toBeTruthy()
	end)

	t.test("the value bonus survives being applied to small rewards", function()
		-- A Normal stalk at Yield 0 is worth 2. Flooring +10% per stalk would
		-- pay nothing at all, so the tier has to carry its remainder.
		local reward = Bamboo.Value.StalkReward("Normal", 0)
		local bonus = Bamboo.Combo.Rewards(50).value

		local granted, remainder = 0, 0
		local stalks = 20
		for _ = 1, stalks do
			local paid
			paid, remainder = Bamboo.Combo.ApplyValueBonus(reward, bonus, remainder)
			granted += paid
			t.expect(paid).toBe(math.floor(paid))
		end

		-- Over enough stalks the payout converges on the advertised percentage.
		local expected = reward * stalks * (1 + bonus)
		t.expect(math.abs(granted - expected) <= 1).toBeTruthy()
		t.expect(granted > reward * stalks).toBeTruthy()
	end)

	t.test("no value bonus leaves the reward and remainder untouched", function()
		local paid, remainder = Bamboo.Combo.ApplyValueBonus(7, 0, 0.4)
		t.expect(paid).toBe(7)
		t.expect(remainder).toBe(0.4)
	end)

	t.test("milestones fire once, and a big swing reports only the highest", function()
		t.expect(Bamboo.Combo.MilestoneCrossed(0, 9)).toBeNil()
		t.expect(Bamboo.Combo.MilestoneCrossed(9, 10)).toBe(10)
		-- Already past it: crossing again should not re-announce.
		t.expect(Bamboo.Combo.MilestoneCrossed(10, 11)).toBeNil()
		-- One swing leaping several milestones announces the best one only.
		t.expect(Bamboo.Combo.MilestoneCrossed(8, 60)).toBe(50)
	end)

	t.test("every milestone is reachable and ordered", function()
		for index = 2, #Bamboo.Combo.Milestones do
			t.expect(Bamboo.Combo.Milestones[index] > Bamboo.Combo.Milestones[index - 1]).toBeTruthy()
		end
		for _, milestone in Bamboo.Combo.Milestones do
			t.expect(Bamboo.Combo.MilestoneCrossed(milestone - 1, milestone)).toBe(milestone)
		end
	end)

	t.test("combo heat and pitch stay bounded", function()
		t.expect(Bamboo.Combo.Heat(0)).toBe(0)
		t.expect(Bamboo.Combo.Heat(10000)).toBe(1)
		t.expect(Bamboo.Combo.Pitch(0)).toBe(1)
		t.expect(Bamboo.Combo.Pitch(10000) <= 1.5).toBeTruthy()
	end)

	t.test("the next reward threshold is reported until every tier is active", function()
		t.expect(Bamboo.Combo.NextRewardAt(0)).toBe(10)
		t.expect(Bamboo.Combo.NextRewardAt(10)).toBe(25)
		t.expect(Bamboo.Combo.NextRewardAt(500)).toBeNil()
	end)

	t.test("the combo window is generous enough to cross a clump gap", function()
		-- Walking between neighbouring clumps must not drop the streak.
		local walkSeconds = Bamboo.Field.ClumpSeparationStuds / 16
		t.expect(Bamboo.Combo.TimeoutSeconds > walkSeconds).toBeTruthy()
	end)

	-- ── field planting ───────────────────────────────────────────────────────

	t.test("planting is deterministic for a given seed", function()
		local a = Bamboo.Field.BuildSlots(34, 48, Random.new(7))
		local b = Bamboo.Field.BuildSlots(34, 48, Random.new(7))
		t.expect(#a).toBe(#b)
		for index, slot in a do
			t.expect((slot - b[index]).Magnitude).toBeCloseTo(0, 1e-4)
		end
	end)

	t.test("planting returns every requested stalk, inside the field", function()
		local slots = Bamboo.Field.BuildSlots(Bamboo.Value.MaxPossibleStalks(), 48, Random.new(3))
		t.expect(#slots).toBe(Bamboo.Value.MaxPossibleStalks())
		for _, slot in slots do
			t.expect(math.abs(slot.X) <= 48).toBeTruthy()
			t.expect(math.abs(slot.Z) <= 48).toBeTruthy()
		end
	end)

	t.test("planting clusters rather than gridding", function()
		local slots = Bamboo.Field.BuildSlots(34, 48, Random.new(11))

		-- In a clustered layout most stalks have a close neighbour. A uniform
		-- grid over the same area would put everything ~14 studs apart.
		local close = 0
		for _, slot in slots do
			local nearest = math.huge
			for _, other in slots do
				if other ~= slot then
					nearest = math.min(nearest, (other - slot).Magnitude)
				end
			end
			if nearest <= Bamboo.Tool.Range then
				close += 1
			end
		end
		t.expect(close / #slots > 0.9).toBeTruthy()
	end)

	t.test("a prefix of a prebuilt field is still clustered", function()
		-- Plots lay out slots for a fully upgraded field and then plant only the
		-- first N. That prefix is what a new player actually sees, so it has to
		-- be as dense as a field built for exactly that count.
		local slots = Bamboo.Field.BuildSlots(Bamboo.Value.MaxPossibleStalks(), 48, Random.new(5))

		local neighbours = 0
		for index = 1, Bamboo.Field.StartingStalks do
			local slot = slots[index]
			for other = 1, Bamboo.Field.StartingStalks do
				if other ~= index and (slots[other] - slot).Magnitude <= Bamboo.Tool.Range then
					neighbours += 1
				end
			end
		end

		-- Every stalk should average at least a full starter multi-hit of
		-- neighbours, or the rotor drops to idle between every stalk.
		local average = neighbours / Bamboo.Field.StartingStalks
		t.expect(average >= Bamboo.Tool.BaseMultiHit).toBeTruthy()
	end)

	t.test("density still meaningfully grows the field", function()
		local base = Bamboo.Value.MaxStalks(0)
		local maxed = Bamboo.Value.MaxPossibleStalks()
		t.expect(maxed >= base * 2).toBeTruthy()
	end)

	-- ── rarity luck ──────────────────────────────────────────────────────────

	t.test("replant luck biases toward rarer bamboo without guaranteeing it", function()
		local baseThick = Bamboo.Rarity.ChanceOf("Thick", 0)
		local luckyThick = Bamboo.Rarity.ChanceOf("Thick", 0.5)
		t.expect(luckyThick > baseThick).toBeTruthy()
		t.expect(luckyThick < 100).toBeTruthy()

		local total = 0
		for _, id in Bamboo.Rarity.RollOrder do
			total += Bamboo.Rarity.ChanceOf(id, 0.5)
		end
		t.expect(total).toBeCloseTo(100, 0.001)
	end)

	t.test("rarity rolls stay reproducible with and without luck", function()
		for _, luck in { 0, 0.5 } do
			local a, b = Random.new(21), Random.new(21)
			for _ = 1, 20 do
				t.expect(Bamboo.Rarity.Roll(a, luck)).toBe(Bamboo.Rarity.Roll(b, luck))
			end
		end
	end)

	t.test("selling converts the bag at the configured rate", function()
		t.expect(Bamboo.Economy.SellValue(Bamboo.Economy.BagCapacity))
			.toBe(Bamboo.Economy.BagCapacity * Bamboo.Economy.MoneyPerBamboo)
	end)
end
