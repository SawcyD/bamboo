--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Core = require(game:GetService("ReplicatedStorage"):WaitForChild("Core"))
local BridgeNet2 = Core:GetPackage("BridgeNet2")

local Util = {}

local _isServer = RunService:IsServer()

-- ── channel detection ────────────────────────────────────────────────────────
-- A Relay channel is a plain table created by Channel.luau.
local function isRelayChannel(x: any): boolean
	return type(x) == "table"
		and type(x._bridge) ~= "nil"
		and type(x.listen) == "function"
		and type(x._direction) == "string"
end

-- ── token-bucket rate limiting (per channel per player) ──────────────────────
type Bucket = { tokens: number, lastRefill: number }
local _buckets: { [Player]: { [any]: Bucket } } = {}
local _rateLimits: { [any]: { rate: number, burst: number } } = {}

local function getBucket(channel: any, player: Player): Bucket
	if not _buckets[player] then
		_buckets[player] = {}
	end
	if not _buckets[player][channel] then
		_buckets[player][channel] = { tokens = 0, lastRefill = os.clock() }
	end
	return _buckets[player][channel]
end

local function checkRateLimit(channel: any, player: Player): boolean
	local limit = _rateLimits[channel]
	if not limit then
		return true
	end
	local bucket = getBucket(channel, player)
	local now = os.clock()
	local elapsed = now - bucket.lastRefill
	bucket.tokens = math.min(limit.burst, bucket.tokens + elapsed * limit.rate)
	bucket.lastRefill = now
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

Players.PlayerRemoving:Connect(function(player: Player)
	_buckets[player] = nil
end)

function Util.SetRateLimit(channel: any, opts: { rate: number, burst: number })
	assert(isRelayChannel(channel), "[Relay.Util] SetRateLimit expects a Relay channel")
	_rateLimits[channel] = opts
end

-- ── schema validation helper ─────────────────────────────────────────────────
-- Re-exposed so callers can run validation outside listen/send if needed.
function Util.SetSchema(channel: any, validators: { [string]: (any) -> boolean })
	assert(isRelayChannel(channel), "[Relay.Util] SetSchema expects a Relay channel")
	channel._validators = validators
end

-- ── server fire helpers ───────────────────────────────────────────────────────

function Util.FireAll(channel: any, payload: any)
	assert(_isServer, "FireAll can only be called from the server")
	assert(isRelayChannel(channel), "[Relay.Util] FireAll expects a Relay channel")
	local validators = channel._validators
	if validators then
		for field, check in validators do
			if not check((payload :: any)[field]) then
				warn(string.format("[Relay.Util] FireAll payload failed schema validation on field %q", field))
				return
			end
		end
	end
	channel._bridge:Fire(BridgeNet2.AllPlayers(), payload)
end

function Util.FirePlayer(channel: any, player: Player, payload: any)
	assert(_isServer, "FirePlayer can only be called from the server")
	assert(isRelayChannel(channel), "[Relay.Util] FirePlayer expects a Relay channel")
	local validators = channel._validators
	if validators then
		for field, check in validators do
			if not check((payload :: any)[field]) then
				warn(string.format("[Relay.Util] FirePlayer payload failed schema validation on field %q", field))
				return
			end
		end
	end
	channel._bridge:Fire(BridgeNet2.Players({ player }), payload)
end

function Util.FirePlayers(channel: any, players: { Player }, payload: any)
	assert(_isServer, "FirePlayers can only be called from the server")
	assert(isRelayChannel(channel), "[Relay.Util] FirePlayers expects a Relay channel")
	local validators = channel._validators
	if validators then
		for field, check in validators do
			if not check((payload :: any)[field]) then
				warn(string.format("[Relay.Util] FirePlayers payload failed schema validation on field %q", field))
				return
			end
		end
	end
	channel._bridge:Fire(BridgeNet2.Players(players), payload)
end

function Util.FireExcept(channel: any, except: Player, payload: any)
	assert(_isServer, "FireExcept can only be called from the server")
	assert(isRelayChannel(channel), "[Relay.Util] FireExcept expects a Relay channel")
	local validators = channel._validators
	if validators then
		for field, check in validators do
			if not check((payload :: any)[field]) then
				warn(string.format("[Relay.Util] FireExcept payload failed schema validation on field %q", field))
				return
			end
		end
	end
	channel._bridge:Fire(BridgeNet2.PlayersExcept({ except }), payload)
end

function Util.FireServer(channel: any, payload: any)
	assert(not _isServer, "FireServer can only be called from the client")
	assert(isRelayChannel(channel), "[Relay.Util] FireServer expects a Relay channel")
	local validators = channel._validators
	if validators then
		for field, check in validators do
			if not check((payload :: any)[field]) then
				warn(string.format("[Relay.Util] FireServer payload failed schema validation on field %q", field))
				return
			end
		end
	end
	channel._bridge:Fire(payload)
end

-- ── connect helpers ───────────────────────────────────────────────────────────

function Util.Connect(channel: any, handler: (...any) -> ()): { Disconnect: () -> () }
	assert(isRelayChannel(channel), "[Relay.Util] Connect expects a Relay channel")
	return channel.listen(handler)
end

function Util.SafeConnect(channel: any, handler: (...any) -> ()): { Disconnect: () -> () }
	local wrapped: (...any) -> () = function(...)
		local results = table.pack(pcall(handler, ...))
		if not results[1] then
			warn("[Relay.Util] SafeConnect handler error:", results[2])
		end
	end
	return Util.Connect(channel, wrapped)
end

function Util.ConnectOnce(channel: any, handler: (...any) -> ())
	assert(isRelayChannel(channel), "[Relay.Util] ConnectOnce expects a Relay channel")
	local conn: { Disconnect: () -> () }
	conn = channel.listen(function(...)
		conn.Disconnect()
		handler(...)
	end)
end

-- ConnectRateLimited: wraps ServerBridge:Connect with per-player token-bucket.
-- opts is applied immediately when provided; can also call SetRateLimit beforehand.
function Util.ConnectRateLimited(
	channel: any,
	handler: (payload: any, player: Player) -> (),
	opts: { rate: number, burst: number }?
): { Disconnect: () -> () }
	assert(_isServer, "ConnectRateLimited can only be used server-side")
	assert(isRelayChannel(channel), "[Relay.Util] ConnectRateLimited expects a Relay channel")
	if opts then
		Util.SetRateLimit(channel, opts)
	end
	-- bypass channel.listen so we can intercept before the channel's schema check
	-- (we still want the schema check to run, so we call listen and wrap it)
	return channel._bridge:Connect(function(player: Player, content: any)
		if not checkRateLimit(channel, player) then
			warn(
				string.format(
					"[Relay.Util] Rate limit exceeded for %s on bridge %s",
					player.Name,
					channel._bridge._name or "?"
				)
			)
			return
		end
		local validators = channel._validators
		if validators then
			for field, check in validators do
				if not check((content :: any)[field]) then
					warn(
						string.format(
							"[Relay.Util] ConnectRateLimited inbound payload failed schema on field %q",
							field
						)
					)
					return
				end
			end
		end
		handler(content, player)
	end)
end

function Util.SafeConnectRateLimited(
	channel: any,
	handler: (payload: any, player: Player) -> (),
	opts: { rate: number, burst: number }?
): { Disconnect: () -> () }
	local wrapped: (any, Player) -> () = function(payload: any, player: Player)
		local results = table.pack(pcall(handler, payload, player))
		if not results[1] then
			warn("[Relay.Util] SafeConnectRateLimited handler error:", results[2])
		end
	end
	return Util.ConnectRateLimited(channel, wrapped, opts)
end

-- ── invoke helpers (kind = "invoke" channels) ─────────────────────────────────

-- Server: register a handler that returns a value.  Wire via channel.listen which
-- sets bridge.OnServerInvoke for invoke-kind channels.
function Util.OnInvoke(channel: any, handler: (payload: any, player: Player) -> any)
	assert(_isServer, "OnInvoke can only be registered on the server")
	assert(isRelayChannel(channel), "[Relay.Util] OnInvoke expects a Relay channel")
	assert(channel._kind == "invoke", "[Relay.Util] OnInvoke requires a channel with kind = 'invoke'")
	channel.listen(handler)
end

function Util.SafeOnInvoke(channel: any, handler: (payload: any, player: Player) -> any)
	assert(_isServer, "SafeOnInvoke can only be registered on the server")
	assert(isRelayChannel(channel), "[Relay.Util] SafeOnInvoke expects a Relay channel")
	assert(channel._kind == "invoke", "[Relay.Util] SafeOnInvoke requires a channel with kind = 'invoke'")
	channel.listen(function(payload: any, player: Player)
		local ok, result = pcall(handler, payload, player)
		if not ok then
			warn("[Relay.Util] SafeOnInvoke handler error:", result)
			return nil
		end
		return result
	end)
end

-- Client: invoke the server and yield for a response.
function Util.Invoke(channel: any, payload: any): any
	assert(not _isServer, "Invoke can only be called from the client")
	assert(isRelayChannel(channel), "[Relay.Util] Invoke expects a Relay channel")
	assert(channel._kind == "invoke", "[Relay.Util] Invoke requires a channel with kind = 'invoke'")
	return channel.invokeAsync(payload)
end

-- ── debug helpers ─────────────────────────────────────────────────────────────

function Util.Reference(channel: any): any
	assert(isRelayChannel(channel), "[Relay.Util] Reference expects a Relay channel")
	return channel._bridge
end

function Util.DebugGetPlayerTokens(channel: any, player: Player): number?
	local pb = _buckets[player]
	if pb and pb[channel] then
		return pb[channel].tokens
	end
	return nil
end

return Util
