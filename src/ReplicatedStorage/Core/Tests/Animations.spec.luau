--!strict

local Animations = require(script.Parent.Parent:WaitForChild("Shared"):WaitForChild("Animations"):WaitForChild("init"))

return function(t)
	t.test("resolves NPC profiles by stable ID", function()
		local profile = Animations.Registry.Get("shopkeeper")

		t.expect(profile).toBeTruthy()
		t.expect(profile.Locomotion.Idle).toBe("Idle")
	end)

	t.test("does not resolve an unknown profile", function()
		t.expect(Animations.Registry.Get("missing_profile")).toBeNil()
	end)

	t.test("lists catalog profiles without loading every track", function()
		t.expect(Animations.Registry.List()).toEqual({ "bartender", "gym_teacher", "shopkeeper" })
	end)
end
