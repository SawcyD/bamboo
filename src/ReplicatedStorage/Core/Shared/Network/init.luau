--!strict
-- Relay: combines all Event namespaces and provides Signal + Util
-- Transport: BridgeNet2 (replaces ByteNet). Table payloads are used in v1;
-- optional buffer encode/decode layer in Util is planned for a future pass.

local Relay = {}

-- standalone signal implementation
local Signal = {}
Signal.__index = Signal

type Connection = {
	_signal: any,
	_callback: (...any) -> (),
	Disconnect: (Connection) -> (),
}

type SignalType = typeof(setmetatable({} :: { _connections: { Connection }, _firing: boolean }, Signal))

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	local connections = self._signal._connections
	for i, c in connections do
		if c == self then
			table.remove(connections, i)
			break
		end
	end
end

function Signal.new(): SignalType
	return setmetatable({ _connections = {}, _firing = false }, Signal)
end

function Signal:Connect(callback: (...any) -> ()): Connection
	local conn = setmetatable({ _signal = self, _callback = callback }, Connection)
	table.insert(self._connections, conn)
	return conn :: any
end

function Signal:Once(callback: (...any) -> ())
	local conn: any
	conn = self:Connect(function(...)
		conn:Disconnect()
		callback(...)
	end)
end

function Signal:Fire(...)
	-- iterate a copy so mid-fire disconnects are safe
	local snapshot = table.clone(self._connections)
	local args = { ... }
	for _, conn in snapshot do
		task.spawn(conn._callback, table.unpack(args))
	end
end

function Signal:Wait(): ...any
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	table.clear(self._connections)
end

function Signal:Destroy()
	self:DisconnectAll()
end

Relay.Signal = Signal
Relay.RelaySignal = Signal

-- BridgeNet2-backed channel factory
Relay.Channel = require(script:WaitForChild("Channel"))

-- attach Util
Relay.Util = require(script:WaitForChild("Util"))

-- load all event namespace modules from the Events subfolder
local eventsFolder = script:WaitForChild("Events")
for _, child in eventsFolder:GetChildren() do
	if child:IsA("ModuleScript") and child.Name:sub(1, 1) ~= "_" then
		Relay[child.Name] = require(child)
	end
end

return Relay
