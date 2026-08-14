--!strict
--[[
	Cooldown: per-key cooldown tracking on a server-synced clock.

	Uses workspace:GetServerTimeNow(), which Roblox keeps synchronized between
	server and clients — so a client can predict "ability ready" UI on the same
	timeline the server enforces. The server check is always authoritative.

		-- server (authoritative)
		local dashCooldown = Cooldown.new(3)
		Relay.Combat.Dash.listen(function(payload, player)
			if not dashCooldown:Try(player) then
				return -- still cooling down; ignore
			end
			doDash(player)
		end)

		-- client (prediction for UI)
		local localDash = Cooldown.new(3)
		if localDash:Try("local") then playDashAnimation() end
		bar.Size = UDim2.fromScale(localDash:Fraction("local"), 1)

	Key by Player on the server (call :Release(player) from PlayerRemoving, or pass
	cleanupOnLeave = true to do it automatically).
]]

local Players = game:GetService("Players")

local Cooldown = {}
Cooldown.__index = Cooldown

export type CooldownType = typeof(setmetatable(
	{} :: {
		Duration: number,
		_readyAt: { [any]: number },
	},
	Cooldown
))

function Cooldown.new(duration: number, opts: { cleanupOnLeave: boolean? }?): CooldownType
	assert(type(duration) == "number" and duration > 0, "Cooldown.new: duration must be > 0")
	local self = setmetatable({
		Duration = duration,
		_readyAt = {},
	}, Cooldown)

	if opts and opts.cleanupOnLeave then
		Players.PlayerRemoving:Connect(function(player: Player)
			self._readyAt[player] = nil
		end)
	end

	return self
end

--- If `key` is off cooldown, starts the cooldown and returns true; otherwise false.
function Cooldown.Try(self: CooldownType, key: any): boolean
	local now = workspace:GetServerTimeNow()
	local readyAt = self._readyAt[key]
	if readyAt and now < readyAt then
		return false
	end
	self._readyAt[key] = now + self.Duration
	return true
end

--- True when off cooldown, without starting it.
function Cooldown.IsReady(self: CooldownType, key: any): boolean
	local readyAt = self._readyAt[key]
	return not readyAt or workspace:GetServerTimeNow() >= readyAt
end

--- Seconds until ready (0 when ready).
function Cooldown.TimeLeft(self: CooldownType, key: any): number
	local readyAt = self._readyAt[key]
	if not readyAt then
		return 0
	end
	return math.max(0, readyAt - workspace:GetServerTimeNow())
end

--- Progress toward ready: 0 = just used, 1 = ready. For cooldown bars/radials.
function Cooldown.Fraction(self: CooldownType, key: any): number
	return 1 - math.clamp(Cooldown.TimeLeft(self, key) / self.Duration, 0, 1)
end

--- Ends the cooldown for `key` immediately.
function Cooldown.Reset(self: CooldownType, key: any)
	self._readyAt[key] = nil
end

--- Drops the key entirely (call for Players on PlayerRemoving).
function Cooldown.Release(self: CooldownType, key: any)
	self._readyAt[key] = nil
end

return Cooldown
