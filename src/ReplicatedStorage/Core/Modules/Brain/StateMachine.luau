--!strict
-- Generic state machine for NPCs, characters, and other runtime actors.

local Signal = require(script.Parent.Parent:WaitForChild("Signal"))

local StateMachine = {}
StateMachine.__index = StateMachine

export type StateDefinition = {
	Enter: ((context: any) -> (() -> ())?)?,
	Update: ((context: any, deltaTime: number) -> string?)?,
	Exit: ((context: any) -> ())?,
	CanEnter: ((context: any) -> boolean)?,
	CanExit: ((context: any) -> boolean)?,
	Timeout: number?,
	TimeoutState: string?,
}

export type StateMachineType = {
	Changed: any,
	Start: (self: StateMachineType, initialState: string?) -> boolean,
	Stop: (self: StateMachineType) -> (),
	Pause: (self: StateMachineType) -> (),
	Resume: (self: StateMachineType) -> (),
	Update: (self: StateMachineType, deltaTime: number) -> (),
	Transition: (self: StateMachineType, stateName: string, reason: string?) -> boolean,
	Register: (self: StateMachineType, stateName: string, definition: StateDefinition) -> (),
	GetState: (self: StateMachineType) -> string?,
	GetStateTime: (self: StateMachineType) -> number,
	GetContext: (self: StateMachineType) -> any,
	Destroy: (self: StateMachineType) -> (),
}

type StateMachineImpl = StateMachineType & {
	_states: { [string]: StateDefinition },
	_context: any,
	_initialState: string?,
	_currentState: string?,
	_stateTime: number,
	_cleanup: (() -> ())?,
	_started: boolean,
	_paused: boolean,
	_destroyed: boolean,
	_transitioning: boolean,
	_queuedTransition: { name: string, reason: string? }?,
}

local function _validateStateName(stateName: string)
	assert(type(stateName) == "string" and #stateName > 0, "Brain.StateMachine: state name is required")
end

local function _runCleanup(machine: StateMachineImpl)
	local cleanup = machine._cleanup
	machine._cleanup = nil
	if cleanup then
		cleanup()
	end
end

function StateMachine.new(
	states: { [string]: StateDefinition }?,
	context: any?,
	initialState: string?
): StateMachineType
	local machine = setmetatable({
		_states = states or {},
		_context = context,
		_initialState = initialState,
		_currentState = nil,
		_stateTime = 0,
		_cleanup = nil,
		_started = false,
		_paused = false,
		_destroyed = false,
		_transitioning = false,
		_queuedTransition = nil,
		Changed = Signal.new(),
	}, StateMachine) :: StateMachineImpl
	return machine
end

function StateMachine:Register(stateName: string, definition: StateDefinition)
	_validateStateName(stateName)
	assert(type(definition) == "table", "Brain.StateMachine: state definition is required")
	assert(not self._started, "Brain.StateMachine: cannot register states after Start")
	self._states[stateName] = definition
end

function StateMachine:Start(initialState: string?): boolean
	if self._destroyed or self._started then
		return false
	end
	local stateName = initialState or self._initialState
	if not stateName then
		return false
	end
	self._started = true
	local started = self:Transition(stateName, "Start")
	if not started then
		self._started = false
	end
	return started
end

function StateMachine:Stop()
	if not self._started then
		return
	end
	local previous = self._currentState
	self._transitioning = true
	if previous then
		local definition = self._states[previous]
		if definition and definition.Exit then
			definition.Exit(self._context)
		end
	end
	_runCleanup(self)
	self._transitioning = false
	self._currentState = nil
	self._stateTime = 0
	self._started = false
	self._paused = false
	if previous then
		self.Changed:Fire(nil, previous, "Stop")
	end
end

function StateMachine:Pause()
	self._paused = true
end

function StateMachine:Resume()
	if self._started then
		self._paused = false
	end
end

function StateMachine:Transition(stateName: string, reason: string?): boolean
	if self._destroyed or not self._started then
		return false
	end
	_validateStateName(stateName)
	if self._transitioning then
		self._queuedTransition = { name = stateName, reason = reason }
		return true
	end

	local nextDefinition = self._states[stateName]
	if not nextDefinition then
		warn("Brain.StateMachine: unknown state " .. stateName)
		return false
	end
	if self._currentState == stateName then
		return true
	end

	local currentName = self._currentState
	local currentDefinition = if currentName then self._states[currentName] else nil
	if currentDefinition and currentDefinition.CanExit and not currentDefinition.CanExit(self._context) then
		return false
	end
	if nextDefinition.CanEnter and not nextDefinition.CanEnter(self._context) then
		return false
	end

	self._transitioning = true
	if currentDefinition and currentDefinition.Exit then
		currentDefinition.Exit(self._context)
	end
	_runCleanup(self)

	self._currentState = stateName
	self._stateTime = 0
	if nextDefinition.Enter then
		self._cleanup = nextDefinition.Enter(self._context)
	end
	self._transitioning = false
	self.Changed:Fire(stateName, currentName, reason)

	local queued = self._queuedTransition
	self._queuedTransition = nil
	if queued then
		self:Transition(queued.name, queued.reason)
	end
	return true
end

function StateMachine:Update(deltaTime: number)
	if self._destroyed or not self._started or self._paused or not self._currentState then
		return
	end
	assert(deltaTime >= 0, "Brain.StateMachine: deltaTime cannot be negative")
	local stateName = self._currentState
	local definition = self._states[stateName]
	if not definition then
		return
	end
	self._stateTime += deltaTime

	local nextState: string?
	if definition.Timeout and self._stateTime >= definition.Timeout then
		nextState = definition.TimeoutState
	elseif definition.Update then
		nextState = definition.Update(self._context, deltaTime)
	end
	if nextState then
		self:Transition(nextState, "Update")
	end
end

function StateMachine:GetState(): string?
	return self._currentState
end

function StateMachine:GetStateTime(): number
	return self._stateTime
end

function StateMachine:GetContext(): any
	return self._context
end

function StateMachine:Destroy()
	if self._destroyed then
		return
	end
	self:Stop()
	self._destroyed = true
	self.Changed:Destroy()
	table.clear(self._states)
	self._context = nil
	self._queuedTransition = nil
end

return StateMachine
