--!strict

local Janitor = {}
Janitor.__index = Janitor

type Task = {
	task: any,
	method: string?,
}

export type JanitorType = typeof(setmetatable({} :: { _keyed: { [any]: Task }, _unkeyed: { Task } }, Janitor))

function Janitor.new(): JanitorType
	return setmetatable({ _keyed = {}, _unkeyed = {} }, Janitor)
end

-- runs a single cleanup task
local function runTask(t: Task)
	local task = t.task
	local method = t.method
	if method then
		-- table with named method
		if type(task) == "table" and type(task[method]) == "function" then
			task[method](task)
		else
			warn("Janitor: task does not have method " .. tostring(method))
		end
	elseif type(task) == "function" then
		task()
	elseif typeof(task) == "RBXScriptConnection" then
		task:Disconnect()
	elseif typeof(task) == "Instance" then
		task:Destroy()
	else
		warn("Janitor: unknown task type " .. typeof(task))
	end
end

function Janitor:Add(task: any, methodName: string?)
	table.insert(self._unkeyed, { task = task, method = methodName })
end

function Janitor:AddKey(key: any, task: any, methodName: string?)
	if self._keyed[key] then
		runTask(self._keyed[key])
	end
	self._keyed[key] = { task = task, method = methodName }
end

function Janitor:Remove(key: any)
	local t = self._keyed[key]
	if t then
		runTask(t)
		self._keyed[key] = nil
	end
end

function Janitor:Cleanup()
	-- keyed first
	for key, t in self._keyed do
		runTask(t)
		self._keyed[key] = nil
	end
	-- unkeyed in reverse
	for i = #self._unkeyed, 1, -1 do
		runTask(self._unkeyed[i])
	end
	table.clear(self._unkeyed)
end

function Janitor:Destroy()
	self:Cleanup()
end

return Janitor
