--!strict
-- Small, tick-driven behavior tree runtime.

local Signal = require(script.Parent.Parent:WaitForChild("Signal"))

local BehaviorTree = {}
BehaviorTree.__index = BehaviorTree

export type Status = "Running" | "Success" | "Failure"
export type Node = {
	Name: string,
	Tick: (self: Node, context: any, deltaTime: number) -> Status,
	Reset: (self: Node) -> (),
	Abort: (self: Node, context: any) -> (),
}

export type BehaviorTreeType = {
	StatusChanged: any,
	Start: (self: BehaviorTreeType) -> (),
	Pause: (self: BehaviorTreeType) -> (),
	Resume: (self: BehaviorTreeType) -> (),
	Tick: (self: BehaviorTreeType, deltaTime: number) -> Status?,
	Reset: (self: BehaviorTreeType) -> (),
	Abort: (self: BehaviorTreeType) -> (),
	GetStatus: (self: BehaviorTreeType) -> Status?,
	GetContext: (self: BehaviorTreeType) -> any,
	Destroy: (self: BehaviorTreeType) -> (),
}

type BehaviorTreeImpl = BehaviorTreeType & {
	_root: Node,
	_context: any,
	_status: Status?,
	_started: boolean,
	_paused: boolean,
	_destroyed: boolean,
}

function BehaviorTree.new(root: Node, context: any?): BehaviorTreeType
	assert(root and type(root.Tick) == "function", "Brain.BehaviorTree: a root node is required")
	return setmetatable({
		_root = root,
		_context = context,
		_status = nil,
		_started = false,
		_paused = false,
		_destroyed = false,
		StatusChanged = Signal.new(),
	}, BehaviorTree) :: BehaviorTreeImpl
end

function BehaviorTree:Start()
	if self._destroyed then
		return
	end
	self._started = true
	self._paused = false
end

function BehaviorTree:Pause()
	self._paused = true
end

function BehaviorTree:Resume()
	if self._started then
		self._paused = false
	end
end

function BehaviorTree:Tick(deltaTime: number): Status?
	if self._destroyed or not self._started or self._paused then
		return self._status
	end
	assert(deltaTime >= 0, "Brain.BehaviorTree: deltaTime cannot be negative")
	if self._status == "Success" or self._status == "Failure" then
		return self._status
	end

	local status = self._root:Tick(self._context, deltaTime)
	if status ~= self._status then
		local previous = self._status
		self._status = status
		self.StatusChanged:Fire(status, previous)
	end
	return status
end

function BehaviorTree:Reset()
	if self._destroyed then
		return
	end
	self._root:Reset()
	local previous = self._status
	self._status = nil
	if previous then
		self.StatusChanged:Fire(nil, previous)
	end
end

function BehaviorTree:Abort()
	if self._destroyed then
		return
	end
	self._root:Abort(self._context)
	local previous = self._status
	self._status = "Failure"
	if previous ~= "Failure" then
		self.StatusChanged:Fire("Failure", previous)
	end
end

function BehaviorTree:GetStatus(): Status?
	return self._status
end

function BehaviorTree:GetContext(): any
	return self._context
end

function BehaviorTree:Destroy()
	if self._destroyed then
		return
	end
	self:Abort()
	self._destroyed = true
	self.StatusChanged:Destroy()
	self._context = nil
end

return BehaviorTree
