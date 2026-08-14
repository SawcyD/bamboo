--!strict

local ObjectPool = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("ObjectPool"))

return function(t)
	t.test("reuses returned objects instead of creating new ones", function()
		local created = 0
		local pool = ObjectPool.new(function()
			created += 1
			return { id = created }
		end)

		local a = pool:Get()
		t.expect(created).toBe(1)
		pool:Return(a)
		local b = pool:Get()
		t.expect(created).toBe(1) -- reused, not re-created
		t.expect(b).toBe(a)
	end)

	t.test("tracks active and idle counts", function()
		local pool = ObjectPool.new(function()
			return {}
		end)
		pool:Prewarm(3)
		t.expect(pool:GetIdleCount()).toBe(3)
		t.expect(pool:GetActiveCount()).toBe(0)

		local one = pool:Get()
		t.expect(pool:GetIdleCount()).toBe(2)
		t.expect(pool:GetActiveCount()).toBe(1)

		pool:Return(one)
		t.expect(pool:GetIdleCount()).toBe(3)
		t.expect(pool:GetActiveCount()).toBe(0)
	end)

	t.test("max cap discards overflow on return", function()
		local pool = ObjectPool.new(function()
			return {}
		end, { max = 1 })
		local a = pool:Get()
		local b = pool:Get()
		pool:Return(a)
		pool:Return(b) -- idle already at cap (1) -> b is discarded
		t.expect(pool:GetIdleCount()).toBe(1)
	end)

	t.test("returning a foreign or already-returned object is a no-op", function()
		local pool = ObjectPool.new(function()
			return {}
		end)
		local a = pool:Get()
		pool:Return(a)
		pool:Return(a) -- second return ignored
		t.expect(pool:GetIdleCount()).toBe(1)
		pool:Return({ foreign = true })
		t.expect(pool:GetIdleCount()).toBe(1)
	end)
end
