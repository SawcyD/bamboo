--!strict
--[[
	Scheduler: run work at a rate (Hz) or after a delay, all on ONE shared
	Heartbeat instead of a RunService connection per caller.

	Every handle is ticked from a single connection, each at its own interval and
	staggered across frames so a hundred regen/AI/tick callbacks don't all fire on
	the same frame. Timing is driven by workspace:GetServerTimeNow() (the same
	clock Cooldown and leaderboards use), so it stays consistent on server/client.

		local Scheduler = Core:Get("Scheduler")

		-- repeat at a rate
		local handle = Scheduler.Every(10, function(dt) regen(dt) end)  -- 10 Hz
		handle:SetRate(20)
		handle:Pause(); handle:Resume()
		handle:Disconnect()                       -- stop (also :Destroy for Janitor)

		-- one-shot, cancelable
		Scheduler.Delay(2.5, function() spawnBoss() end)
		Scheduler.NextFrame(function() layoutUi() end)

		-- by period instead of frequency
		Scheduler.Interval(0.5, function(dt) ... end)

		-- wrappers
		local fire = Scheduler.Throttle(sendInput, 30)   -- leading edge, ≤30 Hz
		local save = Scheduler.Debounce(persist, 0.2)     -- trailing edge, 200ms

	Frame budget (optional): Scheduler.SetFrameBudget(2) caps dispatch at ~2ms per
	frame; overflow handles run next frame (round-robin, so none starve).

	dt passed to repeat callbacks is the real elapsed time since that handle last
	ran — safe to use for time-based integration (regen * dt, etc.).
]]

local RunService = game:GetService("RunService")

local Scheduler = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

--------------------------------------------------------------------------------
-- handle
--------------------------------------------------------------------------------

local Handle = {}
Handle.__index = Handle

export type Handle = typeof(setmetatable(
	{} :: {
		_interval: number,
		_lastFire: number,
		_callback: (number) -> (),
		_paused: boolean,
		_alive: boolean,
		_once: boolean,
	},
	Handle
))

function Handle.Pause(self: Handle)
	self._paused = true
end

function Handle.Resume(self: Handle)
	if not self._paused then
		return
	end
	self._paused = false
	self._lastFire = now() -- wait a full interval before the next fire
end

function Handle.SetRate(self: Handle, hz: number)
	assert(hz > 0, "Scheduler handle:SetRate expects hz > 0")
	self._interval = 1 / hz
end

function Handle.SetInterval(self: Handle, seconds: number)
	self._interval = math.max(seconds, 0)
end

function Handle.IsActive(self: Handle): boolean
	return self._alive and not self._paused
end

function Handle.Disconnect(self: Handle)
	self._alive = false
end

-- Janitor compatibility: janitor:Add(handle, "Destroy")
Handle.Destroy = Handle.Disconnect

--------------------------------------------------------------------------------
-- shared loop
--------------------------------------------------------------------------------

local handles: { Handle } = {}
local heartbeat: RBXScriptConnection? = nil
local frame = 0
local cursor = 0
local frameBudgetMs = math.huge

local function ensureRunning()
	if heartbeat then
		return
	end
	heartbeat = RunService.Heartbeat:Connect(function()
		frame += 1
		local count = #handles
		if count == 0 then
			heartbeat:Disconnect()
			heartbeat = nil
			return
		end

		local t = now()
		local frameStart = os.clock()

		-- round-robin start point so budget overflow doesn't always starve the tail
		for i = 1, count do
			local handle = handles[(cursor + i - 1) % count + 1]
			if handle and handle._alive and not handle._paused then
				if t - handle._lastFire >= handle._interval then
					if (os.clock() - frameStart) * 1000 > frameBudgetMs then
						break -- defer the rest to next frame
					end
					local elapsed = t - handle._lastFire
					handle._lastFire = t
					-- spawn: a slow/erroring/yielding callback can't break the loop
					task.spawn(handle._callback, elapsed)
					if handle._once then
						handle._alive = false
					end
				end
			end
		end
		cursor += 1

		-- compact out dead handles (swap-remove)
		for i = #handles, 1, -1 do
			if not handles[i]._alive then
				local n = #handles
				handles[i] = handles[n]
				handles[n] = nil
			end
		end
	end)
end

local function add(interval: number, callback: (number) -> (), once: boolean): Handle
	local handle = setmetatable({
		_interval = interval,
		-- one-shots wait the exact delay; repeats get a random phase to stagger
		_lastFire = if once then now() else now() - math.random() * interval,
		_callback = callback,
		_paused = false,
		_alive = true,
		_once = once,
	}, Handle)
	table.insert(handles, handle)
	ensureRunning()
	return handle
end

--------------------------------------------------------------------------------
-- public API
--------------------------------------------------------------------------------

-- run `callback(dt)` `hz` times per second
function Scheduler.Every(hz: number, callback: (number) -> ()): Handle
	assert(hz > 0, "Scheduler.Every expects hz > 0")
	return add(1 / hz, callback, false)
end

-- run `callback(dt)` every `seconds`
function Scheduler.Interval(seconds: number, callback: (number) -> ()): Handle
	assert(seconds > 0, "Scheduler.Interval expects seconds > 0")
	return add(seconds, callback, false)
end

-- run `callback` once after `seconds` (cancelable via the returned handle)
function Scheduler.Delay(seconds: number, callback: () -> ()): Handle
	return add(math.max(seconds, 0), function()
		callback()
	end, true)
end

-- run `callback` once on the next Heartbeat
function Scheduler.NextFrame(callback: () -> ()): Handle
	return add(0, function()
		callback()
	end, true)
end

-- returns a function that invokes `callback` at most `hz` times/sec (leading edge)
function Scheduler.Throttle<T...>(callback: (T...) -> (), hz: number): (T...) -> ()
	assert(hz > 0, "Scheduler.Throttle expects hz > 0")
	local interval = 1 / hz
	local last = -math.huge
	return function(...)
		local t = now()
		if t - last >= interval then
			last = t
			callback(...)
		end
	end
end

-- returns a function that runs `callback` only after `seconds` of quiet (trailing edge)
function Scheduler.Debounce<T...>(callback: (T...) -> (), seconds: number): (T...) -> ()
	local pending: Handle? = nil
	return function(...)
		local args = table.pack(...)
		if pending then
			pending:Disconnect()
		end
		pending = Scheduler.Delay(seconds, function()
			pending = nil
			callback(table.unpack(args, 1, args.n))
		end)
	end
end

-- cap dispatch time per frame (ms); overflow handles run next frame. Pass nil to clear.
function Scheduler.SetFrameBudget(milliseconds: number?)
	frameBudgetMs = milliseconds or math.huge
end

-- integer frame counter, incremented once per Heartbeat (handy for per-frame caches)
function Scheduler.GetFrame(): number
	return frame
end

-- number of live handles (for diagnostics)
function Scheduler.GetActiveCount(): number
	return #handles
end

return Scheduler
