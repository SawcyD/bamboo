--!strict

local DebounceUtil = {}

-- wraps fn so it can only fire once every `cooldown` seconds
function DebounceUtil.debounce<T...>(cooldown: number, fn: (T...) -> ()): (T...) -> ()
	local lastFired = 0
	return function(...: T...)
		local now = os.clock()
		if now - lastFired >= cooldown then
			lastFired = now
			fn(...)
		end
	end
end

-- wraps fn so calls within `delay` seconds collapse into one deferred call
function DebounceUtil.trailing<T...>(delay: number, fn: (T...) -> ()): (T...) -> ()
	local pending: thread? = nil
	return function(...: T...)
		if pending then
			task.cancel(pending)
		end
		local args = { ... }
		pending = task.delay(delay, function()
			pending = nil
			fn(table.unpack(args))
		end)
	end
end

-- Creates a per-key debounce gate. `check(key)` returns true if the key is not on
-- cooldown; `release(key)` clears a key's entry. When keying by Player, call release
-- from PlayerRemoving so entries don't accumulate across the server's lifetime.
function DebounceUtil.gate(cooldown: number): ((key: any) -> boolean, (key: any) -> ())
	local lastFired: { [any]: number } = {}
	local function check(key: any): boolean
		local now = os.clock()
		if not lastFired[key] or now - lastFired[key] >= cooldown then
			lastFired[key] = now
			return true
		end
		return false
	end
	local function release(key: any)
		lastFired[key] = nil
	end
	return check, release
end

return DebounceUtil
