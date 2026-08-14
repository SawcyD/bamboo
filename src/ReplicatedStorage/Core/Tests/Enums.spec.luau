--!strict

local Enums = require(script.Parent.Parent:WaitForChild("Shared"):WaitForChild("Enums"):WaitForChild("init"))

return function(t)
	t.test("exposes stable string-backed values", function()
		t.expect(Enums.Brain.State.Idle).toBe("Idle")
		t.expect(Enums.Motion.Layer.Action).toBe("Action")
	end)

	t.test("validates and lists values", function()
		t.expect(Enums.Brain.State.Is("Chase")).toBe(true)
		t.expect(Enums.Brain.State.Is("Missing")).toBe(false)
		t.expect(#Enums.Collectibles.Rarity.List()).toBe(5)
	end)

	t.test("supports metadata", function()
		local EnumFactory =
			require(script.Parent.Parent:WaitForChild("Shared"):WaitForChild("Enums"):WaitForChild("Enum"))
		local testEnum = EnumFactory.Create({ "Attack" }, {
			Attack = { Priority = 10, Interruptible = false },
		})
		t.expect(testEnum.Metadata("Attack").Priority).toBe(10)
	end)
end
