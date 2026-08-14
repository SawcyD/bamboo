--!strict
-- Example spec; run via require(game.ReplicatedStorage.Core.Tests).Run()

local MathUtil = require(script.Parent.Parent:WaitForChild("Utils"):WaitForChild("MathUtil"))

return function(t)
	t.test("lerp interpolates", function()
		t.expect(MathUtil.lerp(0, 10, 0.5)).toBe(5)
		t.expect(MathUtil.lerp(10, 20, 0)).toBe(10)
	end)

	t.test("remap converts ranges", function()
		t.expect(MathUtil.remap(5, 0, 10, 0, 100)).toBe(50)
	end)

	t.test("smoothstep clamps and eases", function()
		t.expect(MathUtil.smoothstep(-1)).toBe(0)
		t.expect(MathUtil.smoothstep(2)).toBe(1)
		t.expect(MathUtil.smoothstep(0.5)).toBeCloseTo(0.5)
	end)

	t.test("sign", function()
		t.expect(MathUtil.sign(-3)).toBe(-1)
		t.expect(MathUtil.sign(0)).toBe(0)
		t.expect(MathUtil.sign(9)).toBe(1)
	end)
end
