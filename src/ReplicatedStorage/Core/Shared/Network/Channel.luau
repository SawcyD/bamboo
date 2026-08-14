--!strict
-- Channel: thin BridgeNet2 wrapper that gives every bridge a schema, direction label, and
-- the dot-call surface (.send / .sendTo / .sendToAll / .listen) previously provided by ByteNet.
--
-- Built-in middleware:
--   * Schema validation: `value = { field = function(v) ... end }` checks every payload
--     in both directions; failing payloads are dropped with a warning.
--   * Rate limiting (server inbound): c2s channels default to 60 msgs/sec per player.
--     Override with `rateLimit = <number>` or disable with `rateLimit = false`.
--   * Telemetry (client): per-bridge sent/received counts + byte estimates for the
--     performance profiler. Free until enabled — set Channel.Telemetry.Enabled = true.

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Core = require(game:GetService("ReplicatedStorage"):WaitForChild("Core"))
local BridgeNet2 = Core:GetPackage("BridgeNet2")

local _isServer = RunService:IsServer()

-- ── network telemetry (client-side; powers the performance profiler) ─────────
export type TelemetryEntry = {
	count: number,
	bytes: number,
}

export type TelemetryData = {
	Enabled: boolean,
	Sent: { [string]: TelemetryEntry },
	Received: { [string]: TelemetryEntry },
}

local Telemetry: TelemetryData = {
	-- Byte estimation JSON-encodes payloads, so tracking stays off until the
	-- profiler flips this on (it never needs to be on for regular players).
	Enabled = false,
	Sent = {},
	Received = {},
}

local function estimateSize(payload: any): number
	if payload == nil then
		return 0
	end
	if typeof(payload) == "buffer" then
		return buffer.len(payload)
	end
	if type(payload) == "string" then
		return #payload
	end
	local success, encoded = pcall(HttpService.JSONEncode, HttpService, payload)
	if success and encoded then
		return #encoded
	end
	if type(payload) == "table" then
		return 40
	end
	return 8
end

local function trackTelemetry(direction: "Sent" | "Received", bridgeName: string, payload: any)
	if _isServer or not Telemetry.Enabled then
		return
	end
	local dict = Telemetry[direction] :: { [string]: TelemetryEntry }
	local entry = dict[bridgeName]
	if not entry then
		entry = { count = 0, bytes = 0 }
		dict[bridgeName] = entry
	end
	entry.count += 1
	entry.bytes += estimateSize(payload)
end

-- ── server inbound rate limiting ─────────────────────────────────────────────
local DEFAULT_C2S_RATE_LIMIT = 60 -- msgs/sec per player

type RateWindow = { count: number, windowStart: number }
-- one shared registry so PlayerRemoving cleanup covers every channel
local _rateWindows: { [string]: { [Player]: RateWindow } } = {}

if _isServer then
	Players.PlayerRemoving:Connect(function(player: Player)
		for _, perPlayer in _rateWindows do
			perPlayer[player] = nil
		end
	end)
end

-- Returns true when the message is allowed. Sliding 1-second window per player.
local function checkRateLimit(bridgeName: string, player: Player, limit: number): boolean
	local perPlayer = _rateWindows[bridgeName]
	if not perPlayer then
		perPlayer = {}
		_rateWindows[bridgeName] = perPlayer
	end
	local now = os.clock()
	local window = perPlayer[player]
	if not window or now - window.windowStart >= 1 then
		perPlayer[player] = { count = 1, windowStart = now }
		return true
	end
	window.count += 1
	if window.count > limit then
		-- warn once per window so an exploiter can't spam the output either
		if window.count == limit + 1 then
			warn(
				string.format(
					"[Relay.Channel:%s] rate limit exceeded by %s (%d msgs/sec)",
					bridgeName,
					player.Name,
					limit
				)
			)
		end
		return false
	end
	return true
end

-- ── direction normalization ──────────────────────────────────────────────────
local DIRECTION_MAP: { [string]: string } = {
	c2s = "c2s",
	clienttoserver = "c2s",
	s2c = "s2c",
	servertoclient = "s2c",
	s2all = "s2all",
	servertoall = "s2all",
	s2some = "s2some",
	servertoplayers = "s2some",
}

local function normalizeDirection(dir: string): string
	local canonical = DIRECTION_MAP[string.lower(dir)]
	if not canonical then
		error(
			string.format(
				"[Relay.Channel] Unknown direction %q. Use c2s, s2c, s2all, or s2some (or their full-name equivalents).",
				dir
			),
			3
		)
	end
	return canonical
end

-- ── schema validation ────────────────────────────────────────────────────────
-- validators: { fieldName -> (value: any) -> boolean }
-- Returns true if the payload passes all field validators (extras allowed).
-- A nil/missing payload is accepted for empty-struct channels (no validators).
local function validatePayload(validators: { [string]: (any) -> boolean }?, payload: any): boolean
	if validators == nil then
		return true
	end
	if type(payload) ~= "table" then
		return false
	end
	for field, check in validators do
		if not check((payload :: any)[field]) then
			return false
		end
	end
	return true
end

-- ── channel constructor ──────────────────────────────────────────────────────
export type ChannelDef = {
	bridge: string,
	kind: string?, -- "fire" | "invoke"  (default "fire")
	direction: string,
	value: { [string]: (any) -> boolean }?,
	-- Server inbound msgs/sec per player. Defaults to 60 for c2s/invoke; false disables.
	rateLimit: (number | boolean)?,
}

export type Channel = {
	_bridge: any,
	_direction: string,
	_kind: string,
	_validators: { [string]: (any) -> boolean }?,
	-- dot-call API
	send: (payload: any) -> (),
	sendTo: (payload: any, player: Player) -> (),
	sendToAll: (payload: any) -> (),
	listen: (handler: (...any) -> ()) -> { Disconnect: () -> (), Destroy: () -> () },
	invokeAsync: (payload: any) -> any,
}

local function Channel(def: ChannelDef): Channel
	assert(type(def) == "table", "[Relay.Channel] def must be a table")
	assert(type(def.bridge) == "string" and #def.bridge > 0, "[Relay.Channel] bridge name is required")
	assert(type(def.direction) == "string", "[Relay.Channel] direction is required")

	local direction = normalizeDirection(def.direction)
	local kind = def.kind or "fire"
	local validators = def.value
	local bridge = BridgeNet2.ReferenceBridge(def.bridge)
	local bridgeName = def.bridge

	-- effective inbound rate limit (only meaningful for channels the server listens on)
	local rateLimit: number? = nil
	if def.rateLimit ~= false then
		if type(def.rateLimit) == "number" then
			rateLimit = def.rateLimit
		elseif direction == "c2s" or kind == "invoke" then
			rateLimit = DEFAULT_C2S_RATE_LIMIT
		end
	end

	local ch = {} :: Channel
	ch._bridge = bridge
	ch._direction = direction
	ch._kind = kind
	ch._validators = validators

	-- ── client → server ───────────────────────────────────────────────────
	function ch.send(payload: any)
		assert(not _isServer, string.format("[Relay.Channel:%s] .send can only be called from the client", def.bridge))
		assert(
			direction == "c2s",
			string.format("[Relay.Channel:%s] .send used on a %s channel", def.bridge, direction)
		)
		if validators and not validatePayload(validators, payload) then
			warn(string.format("[Relay.Channel:%s] .send payload failed schema validation", def.bridge))
			return
		end
		trackTelemetry("Sent", bridgeName, payload)
		bridge:Fire(payload)
	end

	-- ── server → one client ───────────────────────────────────────────────
	function ch.sendTo(payload: any, player: Player)
		assert(_isServer, string.format("[Relay.Channel:%s] .sendTo can only be called from the server", def.bridge))
		if validators and not validatePayload(validators, payload) then
			warn(string.format("[Relay.Channel:%s] .sendTo payload failed schema validation", def.bridge))
			return
		end
		bridge:Fire(BridgeNet2.Players({ player }), payload)
	end

	-- ── server → all clients ──────────────────────────────────────────────
	function ch.sendToAll(payload: any)
		assert(_isServer, string.format("[Relay.Channel:%s] .sendToAll can only be called from the server", def.bridge))
		if validators and not validatePayload(validators, payload) then
			warn(string.format("[Relay.Channel:%s] .sendToAll payload failed schema validation", def.bridge))
			return
		end
		bridge:Fire(BridgeNet2.AllPlayers(), payload)
	end

	-- ── listen (server + client) ──────────────────────────────────────────
	-- Server callbacks receive (payload, player) — same order as old ByteNet handlers.
	-- Client callbacks receive (payload).
	function ch.listen(handler: (...any) -> ()): { Disconnect: () -> (), Destroy: () -> () }
		local connection
		if _isServer then
			-- BridgeNet2 server: callback(player, content) — swap for ByteNet compat
			connection = bridge:Connect(function(player: Player, content: any)
				if rateLimit and not checkRateLimit(bridgeName, player, rateLimit) then
					return
				end
				if validators and not validatePayload(validators, content) then
					warn(
						string.format(
							"[Relay.Channel:%s] inbound payload from %s failed schema validation",
							def.bridge,
							player.Name
						)
					)
					return
				end
				handler(content, player)
			end)
		else
			-- BridgeNet2 client: callback(content)
			connection = bridge:Connect(function(content: any)
				trackTelemetry("Received", bridgeName, content)
				handler(content)
			end)
		end

		local function disconnect()
			connection:Disconnect()
		end
		-- Expose both Disconnect (manual callers) and Destroy (so a Janitor that
		-- cleans tables via :Destroy() handles this without a methodName).
		return {
			Disconnect = disconnect,
			Destroy = disconnect,
		}
	end

	-- ── invoke (kind = "invoke", client only) ─────────────────────────────
	-- Server handler is registered via .listen and must return a value;
	-- it is wired to bridge.OnServerInvoke by Channel when on the server.
	-- On client: yields and returns the server response.
	if kind == "invoke" then
		if _isServer then
			-- OnServerInvoke is set by the first .listen call for invoke channels
			ch.listen = function(handler: (...any) -> ()): { Disconnect: () -> (), Destroy: () -> () }
				bridge.OnServerInvoke = function(player: Player, content: any)
					if rateLimit and not checkRateLimit(bridgeName, player, rateLimit) then
						return nil
					end
					if validators and not validatePayload(validators, content) then
						warn(
							string.format(
								"[Relay.Channel:%s] invoke payload from %s failed schema validation",
								def.bridge,
								player.Name
							)
						)
						return nil
					end
					return handler(content, player)
				end
				local function disconnect()
					bridge.OnServerInvoke = function() end
				end
				return {
					Disconnect = disconnect,
					Destroy = disconnect,
				}
			end
		else
			function ch.invokeAsync(payload: any): any
				if validators and not validatePayload(validators, payload) then
					warn(string.format("[Relay.Channel:%s] .invokeAsync payload failed schema validation", def.bridge))
					return nil
				end
				trackTelemetry("Sent", bridgeName, payload)
				local response = bridge:InvokeServerAsync(payload)
				trackTelemetry("Received", bridgeName, response)
				return response
			end
		end
	end

	return ch
end

local ChannelModule = setmetatable({
	Telemetry = Telemetry,
}, {
	__call = function(_, def: ChannelDef): Channel
		return Channel(def)
	end,
})

return ChannelModule :: any
