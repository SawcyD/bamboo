--!strict
-- Manages debounced and autosave for a single profile

local DEBOUNCE_TIME = 2
local AUTOSAVE_TIME = 300

local SaveQueue = {}
SaveQueue.__index = SaveQueue

-- explicit type: typeof(setmetatable(...)) inferred _pending/_autosave as literal nil on self
export type SaveQueueType = {
	_profile: any,
	_saveFn: (any) -> (),
	_pending: thread?,
	_autosave: thread?,
	_destroyed: boolean,
	MarkDirty: (self: SaveQueueType) -> (),
	ForceSave: (self: SaveQueueType) -> (),
	Destroy: (self: SaveQueueType) -> (),
}

function SaveQueue.new(profile: any, saveFn: (any) -> ()): SaveQueueType
	local self = setmetatable({
		_profile = profile,
		_saveFn = saveFn,
		_pending = nil,
		_autosave = nil,
		_destroyed = false,
	}, SaveQueue) :: SaveQueueType

	-- autosave loop owned by the queue
	self._autosave = task.delay(AUTOSAVE_TIME, function()
		while not self._destroyed do
			SaveQueue.ForceSave(self)
			task.wait(AUTOSAVE_TIME)
		end
	end)

	return self
end

function SaveQueue.MarkDirty(self: SaveQueueType)
	if self._destroyed then
		return
	end
	if self._pending then
		task.cancel(self._pending)
	end
	self._pending = task.delay(DEBOUNCE_TIME, function()
		self._pending = nil
		if not self._destroyed then
			self._saveFn(self._profile)
		end
	end)
end

function SaveQueue.ForceSave(self: SaveQueueType)
	if self._destroyed then
		return
	end
	if self._pending then
		task.cancel(self._pending)
		self._pending = nil
	end
	self._saveFn(self._profile)
end

function SaveQueue.Destroy(self: SaveQueueType)
	self._destroyed = true
	if self._pending then
		task.cancel(self._pending)
		self._pending = nil
	end
	if self._autosave then
		task.cancel(self._autosave)
		self._autosave = nil
	end
end

return SaveQueue
