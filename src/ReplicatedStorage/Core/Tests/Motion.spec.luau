--!strict

local Motion = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("Motion"):WaitForChild("init"))

return function(t)
	t.test("creates reusable animation profiles", function()
		local profile = Motion.Profiles.Create({
			Idle = Motion.Profiles.Animation("rbxassetid://1", true),
		}, {
			Idle = "Idle",
			WalkSpeed = 8,
		})

		t.expect(profile.Animations.Idle.Id).toBe("rbxassetid://1")
		t.expect(profile.Locomotion.Idle).toBe("Idle")
	end)
end
