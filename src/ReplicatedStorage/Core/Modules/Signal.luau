--!strict
--[[
	Signal: a tiny, typed event primitive.

	A framework-wide replacement for BindableEvents and for the ad-hoc signal that
	used to live inside the networking module. Generic over its fired arguments:

		local hit: Signal.Signal<Player, number> = Signal.new()
		local conn = hit:Connect(function(player, damage) ... end)
		hit:Fire(somePlayer, 25)
		conn:Disconnect()

	Handlers run on their own thread (task.spawn), so a slow or erroring handler
	never blocks Fire or the other handlers. Connecting/disconnecting mid-fire is
	safe — Fire iterates a snapshot.
]]

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Wait: (self: Signal<T...>) -> T...,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
	Destroy: (self: Signal<T...>) -> (),
}

type ConnectionImpl = typeof(setmetatable(
	{} :: {
		Connected: boolean,
		_signal: any,
		_callback: (...any) -> (),
	},
	Connection
))

function Connection.Disconnect(self: ConnectionImpl)
	if not self.Connected then
		return
	end
	self.Connected = false
	local connections = self._signal._connections
	local index = table.find(connections, self)
	if index then
		-- swap-remove: order of handlers is not contractual, so this stays O(1)
		local n = #connections
		connections[index] = connections[n]
		connections[n] = nil
	end
end

function Signal.new<T...>(): Signal<T...>
	return (setmetatable({ _connections = {} }, Signal) :: any) :: Signal<T...>
end

function Signal.Connect(self: any, callback: (...any) -> ()): Connection
	local connection = setmetatable({
		Connected = true,
		_signal = self,
		_callback = callback,
	}, Connection)
	table.insert(self._connections, connection)
	return (connection :: any) :: Connection
end

function Signal.Once(self: any, callback: (...any) -> ()): Connection
	local connection: any
	connection = Signal.Connect(self, function(...)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

function Signal.Fire(self: any, ...)
	-- snapshot so handlers may connect/disconnect during the fire
	local snapshot = table.clone(self._connections)
	for i = 1, #snapshot do
		local connection = snapshot[i]
		if connection.Connected then
			task.spawn(connection._callback, ...)
		end
	end
end

function Signal.Wait(self: any): ...any
	local thread = coroutine.running()
	local connection: any
	connection = Signal.Connect(self, function(...)
		connection:Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal.DisconnectAll(self: any)
	for _, connection in self._connections do
		connection.Connected = false
	end
	table.clear(self._connections)
end

function Signal.Destroy(self: any)
	Signal.DisconnectAll(self)
end

return Signal
