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

	t.test("density thickens the field eight stalks at a time", function()
		t.expect(Bamboo.Value.MaxStalks(0)).toBe(Bamboo.Field.MaxStalks)
		t.expect(Bamboo.Value.MaxStalks(3)).toBe(Bamboo.Field.MaxStalks + 24)
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

	t.test("the combo window survives crossing a sparse stretch", function()
		-- Tied to the sickle's reach rather than a layout tuning knob: crossing
		-- three reaches' worth of thin forest must not drop the streak.
		local walkSeconds = Bamboo.Tool.Range * 3 / 16
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

	t.test("the field is planted as a forest, not scattered stalks", function()
		local slots = Bamboo.Field.BuildSlots(Bamboo.Field.StartingStalks, 48, Random.new(11))
		t.expect(#slots).toBe(Bamboo.Field.StartingStalks)

		-- Coverage: sample a grid over the plot and require bamboo near every
		-- sample, so there are no bald regions.
		local samples, covered = 0, 0
		for gx = 0, 9 do
			for gz = 0, 9 do
				local point = Vector3.new(-48 + (gx + 0.5) * 9.6, 0, -48 + (gz + 0.5) * 9.6)
				samples += 1
				for _, slot in slots do
					if (slot - point).Magnitude <= 12 then
						covered += 1
						break
					end
				end
			end
		end
		t.expect(covered / samples > 0.95).toBeTruthy()
	end)

	t.test("density varies, so the forest has thickets and lanes", function()
		local slots = Bamboo.Field.BuildSlots(Bamboo.Field.StartingStalks, 48, Random.new(12))

		local thinnest, thickest = math.huge, 0
		for _, slot in slots do
			local n = 0
			for _, other in slots do
				if other ~= slot and (other - slot).Magnitude <= Bamboo.Tool.Range then
					n += 1
				end
			end
			thinnest = math.min(thinnest, n)
			thickest = math.max(thickest, n)
		end

		-- A uniform scatter would have every stalk with the same neighbour count.
		t.expect(thickest > thinnest + 2).toBeTruthy()
	end)

	t.test("a prefix of a prebuilt field still covers the whole plot", function()
		-- Plots lay out slots for a fully upgraded forest and plant only the
		-- first N, so the prefix has to be spread rather than grown from a corner.
		local slots = Bamboo.Field.BuildSlots(Bamboo.Value.MaxPossibleStalks(), 48, Random.new(5))

		local samples, covered = 0, 0
		for gx = 0, 9 do
			for gz = 0, 9 do
				local point = Vector3.new(-48 + (gx + 0.5) * 9.6, 0, -48 + (gz + 0.5) * 9.6)
				samples += 1
				for index = 1, Bamboo.Field.StartingStalks do
					if (slots[index] - point).Magnitude <= 12 then
						covered += 1
						break
					end
				end
			end
		end
		t.expect(covered / samples > 0.95).toBeTruthy()
	end)

	t.test("density meaningfully thickens what the rotor reaches", function()
		-- Raw stalk count is the wrong measure for a forest: what the player
		-- feels is how much bamboo is inside the rotor's reach at once.
		local function reachAt(count: number): number
			local slots = Bamboo.Field.BuildSlots(count, 48, Random.new(9))
			local total = 0
			for _, slot in slots do
				for _, other in slots do
					if other ~= slot and (other - slot).Magnitude <= Bamboo.Tool.Range then
						total += 1
					end
				end
			end
			return total / #slots
		end

		local base = reachAt(Bamboo.Value.MaxStalks(0))
		local maxed = reachAt(Bamboo.Value.MaxPossibleStalks())
		t.expect(maxed > base * 1.5).toBeTruthy()
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

	-- ── mutations ────────────────────────────────────────────────────────────

	t.test("every mutation in the order is defined and well formed", function()
		for _, id in Bamboo.Mutations.Order do
			local m = Bamboo.Mutations.Definitions[id]
			t.expect(m).toBeTruthy()
			t.expect(m.weight > 0).toBeTruthy()
			t.expect(m.valueMultiplier >= 1).toBeTruthy()
		end
	end)

	t.test("unknown and nil mutations fall back to None", function()
		t.expect(Bamboo.Mutations.Get(nil).id).toBe("None")
		t.expect(Bamboo.Mutations.Get("not_a_mutation").id).toBe("None")
		t.expect(Bamboo.Mutations.IsMutated(nil)).toBe(false)
		t.expect(Bamboo.Mutations.IsMutated("None")).toBe(false)
		t.expect(Bamboo.Mutations.IsMutated("Golden")).toBe(true)
	end)

	t.test("mutation odds total 100 at every luck level", function()
		for _, luck in { 0, 1, Bamboo.Mutations.MaxLuck } do
			local total = 0
			for _, id in Bamboo.Mutations.Order do
				total += Bamboo.Mutations.ChanceOf(id, luck)
			end
			t.expect(total).toBeCloseTo(100, 0.001)
		end
	end)

	t.test("rarer mutations are rarer, and plain bamboo dominates", function()
		local previous = math.huge
		for _, id in Bamboo.Mutations.Order do
			local chance = Bamboo.Mutations.ChanceOf(id, 0)
			t.expect(chance < previous).toBeTruthy()
			previous = chance
		end
		t.expect(Bamboo.Mutations.ChanceOf("None", 0) > 80).toBeTruthy()
	end)

	t.test("luck raises rare mutations but never makes them common", function()
		local maxLuck = Bamboo.Mutations.MaxLuck
		t.expect(Bamboo.Mutations.ChanceOf("Golden", maxLuck) > Bamboo.Mutations.ChanceOf("Golden", 0)).toBeTruthy()
		t.expect(Bamboo.Mutations.ChanceOf("Ancient", maxLuck) > Bamboo.Mutations.ChanceOf("Ancient", 0)).toBeTruthy()
		-- Even fully lucky, the headline mutations stay genuinely rare.
		t.expect(Bamboo.Mutations.ChanceOf("Golden", maxLuck) < 2).toBeTruthy()
		t.expect(Bamboo.Mutations.ChanceOf("Ancient", maxLuck) < 1).toBeTruthy()
	end)

	t.test("luck is clamped, so no caller can push odds past the cap", function()
		local capped = Bamboo.Mutations.ChanceOf("Ancient", Bamboo.Mutations.MaxLuck)
		t.expect(Bamboo.Mutations.ChanceOf("Ancient", 9999)).toBeCloseTo(capped, 0.0001)
	end)

	t.test("mutation rolls are reproducible and always a defined id", function()
		for _, luck in { 0, 2 } do
			local a, b = Random.new(77), Random.new(77)
			for _ = 1, 30 do
				local rolled = Bamboo.Mutations.Roll(a, luck)
				t.expect(rolled).toBe(Bamboo.Mutations.Roll(b, luck))
				t.expect(Bamboo.Mutations.Definitions[rolled]).toBeTruthy()
			end
		end
	end)

	t.test("value multiplies type and mutation exactly once each", function()
		local yieldLevel = 0
		local plainNormal = Bamboo.Value.StalkReward("Normal", yieldLevel, "None")
		local plainThick = Bamboo.Value.StalkReward("Thick", yieldLevel, "None")
		local goldenThick = Bamboo.Value.StalkReward("Thick", yieldLevel, "Golden")

		t.expect(plainNormal).toBe(Bamboo.Value.YieldPerStalk(yieldLevel))
		t.expect(plainThick).toBe(plainNormal * Bamboo.Rarity.Get("Thick").rewardMultiplier)
		t.expect(goldenThick).toBe(plainThick * Bamboo.Mutations.Get("Golden").valueMultiplier)
	end)

	t.test("omitting the mutation is the same as passing None", function()
		t.expect(Bamboo.Value.StalkReward("Tall", 3)).toBe(Bamboo.Value.StalkReward("Tall", 3, "None"))
	end)

	t.test("display names combine mutation and type", function()
		t.expect(Bamboo.Mutations.DisplayName("Thick", "Golden")).toBe("Golden Thick Bamboo")
		t.expect(Bamboo.Mutations.DisplayName("Normal", "None")).toBe("Normal Bamboo")
		t.expect(Bamboo.Mutations.DisplayName("Tall", nil)).toBe("Tall Bamboo")
	end)

	t.test("only the big mutations get the event treatment", function()
		t.expect(Bamboo.Mutations.IsEvent("None")).toBe(false)
		t.expect(Bamboo.Mutations.IsEvent("Dewy")).toBe(false)
		t.expect(Bamboo.Mutations.IsEvent("Crystal")).toBe(true)
		t.expect(Bamboo.Mutations.IsEvent("Ancient")).toBe(true)
	end)

	t.test("every mutation is visually distinct from plain bamboo", function()
		local plain = Bamboo.Mutations.Get("None")
		for _, id in Bamboo.Mutations.Collectable do
			local m = Bamboo.Mutations.Get(id)
			-- At least two visual channels must differ, or it won't read at speed.
			local differences = 0
			if m.color ~= plain.color then
				differences += 1
			end
			if m.nodeColor ~= plain.nodeColor then
				differences += 1
			end
			if m.leafColor ~= plain.leafColor then
				differences += 1
			end
			if m.material ~= plain.material then
				differences += 1
			end
			if m.glow ~= plain.glow then
				differences += 1
			end
			t.expect(differences >= 2).toBeTruthy()
		end
	end)

	t.test("selling converts the bag at the configured rate", function()
		t.expect(Bamboo.Economy.SellValue(Bamboo.Economy.BagCapacity))
			.toBe(Bamboo.Economy.BagCapacity * Bamboo.Economy.MoneyPerBamboo)
	end)
end
