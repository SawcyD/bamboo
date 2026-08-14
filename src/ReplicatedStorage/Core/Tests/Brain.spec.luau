--!strict

local Brain = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("Brain"):WaitForChild("init"))

return function(t)
	t.test("state machine transitions and runs state updates", function()
		local updates = 0
		local machine = Brain.StateMachine.new({
			Idle = {
				Update = function(_, _)
					updates += 1
					return "Done"
				end,
			},
			Done = {},
		}, nil, "Idle")

		t.expect(machine:Start()).toBe(true)
		machine:Update(0.1)
		t.expect(updates).toBe(1)
		t.expect(machine:GetState()).toBe("Done")
		machine:Destroy()
	end)

	t.test("behavior tree sequences complete in order", function()
		local steps = {}
		local tree = Brain.BehaviorTree.new(Brain.Nodes.Sequence("Root", {
			Brain.Nodes.Action("First", function()
				table.insert(steps, "first")
				return "Success"
			end),
			Brain.Nodes.Action("Second", function()
				table.insert(steps, "second")
				return "Success"
			end),
		}))

		tree:Start()
		t.expect(tree:Tick(0.1)).toBe("Success")
		t.expect(steps[1]).toBe("first")
		t.expect(steps[2]).toBe("second")
		tree:Destroy()
	end)
end
