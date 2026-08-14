--!strict
-- Small named-section profiler for AI and gameplay systems.

local Profiler = {}
Profiler.__index = Profiler

export type Sample = {
	Calls: number,
	TotalTime: number,
	LastTime: number,
	MaxTime: number,
}

export type ProfilerType = {
	Enabled: boolean,
	Begin: (self: ProfilerType, name: string) -> (),
	End: (self: ProfilerType, name: string) -> number,
	Measure: (self: ProfilerType, name: string, callback: () -> ()) -> (),
	Record: (self: ProfilerType, name: string, duration: number) -> (),
	Get: (self: ProfilerType, name: string) -> Sample?,
	Snapshot: (self: ProfilerType) -> { [string]: Sample },
	Reset: (self: ProfilerType) -> (),
	Destroy: (self: ProfilerType) -> (),
}

type ProfilerImpl = ProfilerType & {
	_name: string,
	_active: { [string]: number },
	_samples: { [string]: Sample },
	_destroyed: boolean,
}

function Profiler.new(name: string?): ProfilerType
	return setmetatable({
		_name = name or "Profiler",
		_active = {},
		_samples = {},
		Enabled = true,
		_destroyed = false,
	}, Profiler) :: ProfilerImpl
end

function Profiler:Begin(name: string)
	if self.Enabled and not self._destroyed then
		self._active[name] = os.clock()
	end
end

function Profiler:End(name: string): number
	local started = self._active[name]
	if not started then
		return 0
	end
	self._active[name] = nil
	local duration = os.clock() - started
	self:Record(name, duration)
	return duration
end

function Profiler:Measure(name: string, callback: () -> ())
	if not self.Enabled or self._destroyed then
		callback()
		return
	end
	self:Begin(name)
	local ok, err = pcall(callback)
	self:End(name)
	if not ok then
		error(err, 2)
	end
end

function Profiler:Record(name: string, duration: number)
	if not self.Enabled or self._destroyed then
		return
	end
	local sample = self._samples[name]
	if not sample then
		sample = { Calls = 0, TotalTime = 0, LastTime = 0, MaxTime = 0 }
		self._samples[name] = sample
	end
	sample.Calls += 1
	sample.TotalTime += duration
	sample.LastTime = duration
	sample.MaxTime = math.max(sample.MaxTime, duration)
end

function Profiler:Get(name: string): Sample?
	return self._samples[name]
end

function Profiler:Snapshot(): { [string]: Sample }
	local result = {}
	for name, sample in self._samples do
		result[name] = table.clone(sample)
	end
	return result
end

function Profiler:Reset()
	table.clear(self._active)
	table.clear(self._samples)
end

function Profiler:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	self:Reset()
end

return Profiler
