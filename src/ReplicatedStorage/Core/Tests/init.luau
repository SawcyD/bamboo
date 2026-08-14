--!strict
--[[
	Lightweight test runner (no external deps). Spec modules live next to this
	file, named <Thing>.spec.luau, and return a function receiving the harness:

		return function(t)
			t.test("adds numbers", function()
				t.expect(1 + 1).toBe(2)
			end)
		end

	Run from the Studio command bar (or a temporary script):

		require(game.ReplicatedStorage.Core.Tests).Run()

	Keep specs to pure modules (utils, math, RNG) — anything needing players or
	DataStores belongs in manual play testing.
]]

export type Expectation = {
	toBe: (expected: any) -> (),
	toEqual: (expected: any) -> (), -- deep equality for tables
	toBeNil: () -> (),
	toBeTruthy: () -> (),
	toBeCloseTo: (expected: number, epsilon: number?) -> (),
	toThrow: () -> (),
}

export type Harness = {
	test: (name: string, body: () -> ()) -> (),
	expect: (value: any) -> Expectation,
}

local Tests = {}

local function deepEquals(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not deepEquals(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function makeExpect(value: any): Expectation
	return {
		toBe = function(expected: any)
			if value ~= expected then
				error(`expected {tostring(expected)}, got {tostring(value)}`, 3)
			end
		end,
		toEqual = function(expected: any)
			if not deepEquals(value, expected) then
				error("tables are not deeply equal", 3)
			end
		end,
		toBeNil = function()
			if value ~= nil then
				error(`expected nil, got {tostring(value)}`, 3)
			end
		end,
		toBeTruthy = function()
			if not value then
				error(`expected truthy, got {tostring(value)}`, 3)
			end
		end,
		toBeCloseTo = function(expected: number, epsilon: number?)
			local e = epsilon or 1e-6
			if type(value) ~= "number" or math.abs(value - expected) > e then
				error(`expected ~{expected}, got {tostring(value)}`, 3)
			end
		end,
		toThrow = function()
			if type(value) ~= "function" then
				error("toThrow expects a function", 3)
			end
			if pcall(value) then
				error("expected function to throw", 3)
			end
		end,
	}
end

function Tests.Run(): boolean
	local passed = 0
	local failed = 0
	local failures: { string } = {}

	for _, child in script:GetChildren() do
		if not child:IsA("ModuleScript") or not child.Name:match("%.spec$") then
			continue
		end
		local specName = child.Name:gsub("%.spec$", "")
		local spec = require(child) :: (Harness) -> ()

		local harness: Harness = {
			test = function(name: string, body: () -> ())
				local ok, err = pcall(body)
				if ok then
					passed += 1
				else
					failed += 1
					table.insert(failures, `{specName} > {name}: {err}`)
				end
			end,
			expect = makeExpect,
		}

		spec(harness)
	end

	print(`Tests: {passed} passed, {failed} failed`)
	for _, failure in failures do
		warn("  FAIL", failure)
	end
	return failed == 0
end

return Tests
