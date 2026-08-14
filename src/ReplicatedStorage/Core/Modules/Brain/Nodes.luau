--!strict
-- Behavior-tree node constructors used by Brain.BehaviorTree.

local Nodes = {}

export type Status = "Running" | "Success" | "Failure"
export type Node = {
	Name: string,
	Tick: (self: Node, context: any, deltaTime: number) -> Status,
	Reset: (self: Node) -> (),
	Abort: (self: Node, context: any) -> (),
}

local function _makeNode(
	name: string,
	tick: (node: Node, context: any, deltaTime: number) -> Status,
	reset: ((node: Node) -> ())?,
	abort: ((node: Node, context: any) -> ())?
): Node
	local node = {} :: Node
	node.Name = name
	node.Tick = tick
	node.Reset = reset or function() end
	node.Abort = abort or function() end
	return node
end

local function _resetChildren(children: { Node })
	for _, child in children do
		child:Reset()
	end
end

local function _abortChildren(children: { Node }, context: any)
	for _, child in children do
		child:Abort(context)
	end
end

function Nodes.Action(
	name: string,
	onTick: (context: any, deltaTime: number) -> Status?,
	onEnter: ((context: any) -> ())?,
	onExit: ((context: any, status: Status) -> ())?,
	onAbort: ((context: any) -> ())?
): Node
	local active = false
	local node = _makeNode(name, function(_, context, deltaTime)
		if not active then
			active = true
			if onEnter then
				onEnter(context)
			end
		end
		local status = onTick(context, deltaTime) or "Success"
		assert(status == "Running" or status == "Success" or status == "Failure", "Invalid behavior-tree status")
		if status ~= "Running" then
			active = false
			if onExit then
				onExit(context, status)
			end
		end
		return status
	end, function()
		active = false
	end, function(_, context)
		if active and onAbort then
			onAbort(context)
		end
		active = false
	end)
	return node
end

function Nodes.Condition(name: string, predicate: (context: any) -> boolean): Node
	return _makeNode(name, function(_, context)
		return if predicate(context) then "Success" else "Failure"
	end)
end

function Nodes.Wait(name: string, duration: number): Node
	assert(duration >= 0, "Brain.Nodes.Wait: duration cannot be negative")
	local elapsed = 0
	return _makeNode(name, function(_, _, deltaTime)
		elapsed += deltaTime
		return if elapsed >= duration then "Success" else "Running"
	end, function()
		elapsed = 0
	end)
end

function Nodes.Sequence(name: string, children: { Node }): Node
	assert(#children > 0, "Brain.Nodes.Sequence: children are required")
	local index = 1
	return _makeNode(name, function(_, context, deltaTime)
		while index <= #children do
			local status = children[index]:Tick(context, deltaTime)
			if status == "Running" then
				return "Running"
			elseif status == "Failure" then
				return "Failure"
			end
			index += 1
		end
		return "Success"
	end, function()
		index = 1
		_resetChildren(children)
	end, function(_, context)
		_abortChildren(children, context)
		index = 1
		_resetChildren(children)
	end)
end

function Nodes.Selector(name: string, children: { Node }): Node
	assert(#children > 0, "Brain.Nodes.Selector: children are required")
	local index = 1
	return _makeNode(name, function(_, context, deltaTime)
		while index <= #children do
			local status = children[index]:Tick(context, deltaTime)
			if status == "Running" then
				return "Running"
			elseif status == "Success" then
				return "Success"
			end
			index += 1
		end
		return "Failure"
	end, function()
		index = 1
		_resetChildren(children)
	end, function(_, context)
		_abortChildren(children, context)
		index = 1
		_resetChildren(children)
	end)
end

function Nodes.Inverter(name: string, child: Node): Node
	local node = _makeNode(name, function(_, context, deltaTime)
		local status = child:Tick(context, deltaTime)
		if status == "Success" then
			return "Failure"
		elseif status == "Failure" then
			return "Success"
		end
		return "Running"
	end, function()
		child:Reset()
	end, function(_, context)
		child:Abort(context)
		child:Reset()
	end)
	return node
end

function Nodes.Cooldown(name: string, child: Node, duration: number): Node
	assert(duration >= 0, "Brain.Nodes.Cooldown: duration cannot be negative")
	local remaining = 0
	return _makeNode(name, function(_, context, deltaTime)
		remaining = math.max(0, remaining - deltaTime)
		if remaining > 0 then
			return "Failure"
		end
		local status = child:Tick(context, deltaTime)
		if status == "Success" then
			remaining = duration
		end
		return status
	end, function()
		remaining = 0
		child:Reset()
	end, function(_, context)
		remaining = 0
		child:Abort(context)
		child:Reset()
	end)
end

return Nodes
