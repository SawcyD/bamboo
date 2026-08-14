--!strict
--[[
	AntiCheatService: server-authoritative cheat detection.

	The golden rule: the client is the exploiter's machine, so nothing the client
	says is proof. This service makes its own judgements from server-side state
	(where each character actually is, how fast it moved) and treats client signals
	(the heartbeat, UI-injection reports) only as corroborating hints.

	Built-in checks
	---------------
	  • Speed      — horizontal travel faster than the character's own WalkSpeed
	                 (server value) allows, beyond a tolerance.
	  • Teleport   — a single huge jump in position while not falling/jumping.
	  • Flight     — sustained upward motion outside jump/freefall (off by default;
	                 noisy — enable per game).
	  • Watchdog   — the client must Heartbeat; going silent past a timeout is flagged
	                 (catches a deleted/disabled client controller).

	Default response is LOG + FLAG only — violations accrue a per-player score you
	can read, but nobody is kicked until you opt in. Tune, watch your logs, then
	flip AutoKick on.

		local AntiCheat = Framework:GetService("AntiCheatService")
		AntiCheat.OnViolation:Connect(function(player, reason, severity, total) ... end)
		AntiCheat.AutoKick = true                 -- opt into kicking
		AntiCheat.ViolationKickThreshold = 100

	Other systems report their own suspicions through the same pipeline:

		AntiCheat.ReportViolation(player, "BoughtItemWithoutFunds", 25)

	High-mobility games (dashes, launchers, vehicles, in-place teleports) should
	either raise SpeedTolerance or call AntiCheat.Forgive(player) right after a
	legitimate big move so the next sample re-baselines instead of flagging.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Relay = Core:GetShared("Network")
local Scheduler = Core:Get("Scheduler")
local Log = Core:Get("Log")

local log = Log.new("AntiCheat")

local AntiCheatService = {}

-- ── configuration (override before/at Start) ────────────────────────────────
AntiCheatService.Enabled = true
AntiCheatService.SampleRate = 5 -- movement checks per second

AntiCheatService.SpeedTolerance = 1.4 -- allow 40% over WalkSpeed before flagging
AntiCheatService.SpeedFlatBonus = 8 -- studs/s of slack for jitter/knockback
AntiCheatService.TeleportStuds = 60 -- single-sample displacement = teleport

AntiCheatService.FlightCheckEnabled = false
AntiCheatService.FlightVerticalSpeed = 50 -- studs/s upward outside jump/freefall

AntiCheatService.HeartbeatTimeout = 12 -- seconds of silence before flagging
AntiCheatService.HeartbeatGrace = 20 -- seconds after join before the watchdog arms

AntiCheatService.ViolationDecayPerSecond = 2 -- score bleeds off so blips don't pile up
AntiCheatService.AutoKick = false -- LOG + FLAG only by default
AntiCheatService.ViolationKickThreshold = 100
AntiCheatService.KickMessage = "Disconnected by anti-cheat."

-- Severity points per detection (tune to taste)
AntiCheatService.Severity = {
	Speed = 8,
	Teleport = 20,
	Flight = 8,
	HeartbeatMissing = 12,
	ClientReport = 5,
}

-- Optional custom responder. If set, it fully owns the response (AutoKick is
-- ignored): function(player, reason, severity, total)
AntiCheatService.ResponseHandler = nil :: ((Player, string, number, number) -> ())?

AntiCheatService.OnViolation = Relay.Signal.new()

-- ── per-player state ────────────────────────────────────────────────────────

type Record = {
	lastPos: Vector3?,
	lastSampleTime: number,
	lastHeartbeat: number,
	joinTime: number,
	violations: number,
}

local records: { [Player]: Record } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

--------------------------------------------------------------------------------
-- violation pipeline
--------------------------------------------------------------------------------

--- Record a violation against a player. `severity` defaults to 10. Safe to call
--- from any service for game-specific cheats (economy, ability spam, etc.).
function AntiCheatService.ReportViolation(player: Player, reason: string, severity: number?)
	local record = records[player]
	if not record then
		return
	end
	local points = severity or 10
	record.violations += points

	log:Warn(string.format("%s — %s (+%d, total %d)", player.Name, reason, points, math.floor(record.violations)))
	AntiCheatService.OnViolation:Fire(player, reason, points, record.violations)

	local handler = AntiCheatService.ResponseHandler
	if handler then
		handler(player, reason, points, record.violations)
	elseif AntiCheatService.AutoKick and record.violations >= AntiCheatService.ViolationKickThreshold then
		player:Kick(AntiCheatService.KickMessage)
	end
end

--- Current accumulated violation score (0 = clean).
function AntiCheatService.GetViolations(player: Player): number
	local record = records[player]
	return record and record.violations or 0
end

--- Convenience 0–100 trust readout (100 = clean).
function AntiCheatService.GetTrust(player: Player): number
	return math.clamp(100 - AntiCheatService.GetViolations(player), 0, 100)
end

--- Forget the movement baseline (call after a legitimate teleport/launch so the
--- next sample doesn't read the jump as cheating).
function AntiCheatService.Forgive(player: Player)
	local record = records[player]
	if record then
		record.lastPos = nil
		record.lastHeartbeat = now()
	end
end

--- Reduce a player's violation score (e.g. after manual review). nil clears it.
function AntiCheatService.Pardon(player: Player, amount: number?)
	local record = records[player]
	if record then
		record.violations = if amount then math.max(0, record.violations - amount) else 0
	end
end

--------------------------------------------------------------------------------
-- movement checks
--------------------------------------------------------------------------------

local function checkMovement(player: Player, record: Record)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and root:IsA("BasePart")) then
		record.lastPos = nil
		return
	end

	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Dead then
		record.lastPos = nil
		return
	end
	-- seated / vehicle movement is legitimately unbounded — re-baseline, don't flag
	if humanoid.Sit or humanoid.PlatformStand then
		record.lastPos = root.Position
		record.lastSampleTime = now()
		return
	end

	local position = root.Position
	local previous = record.lastPos
	local t = now()

	if previous then
		local dt = t - record.lastSampleTime
		if dt > 0 then
			local horizontal = Vector2.new(position.X - previous.X, position.Z - previous.Z).Magnitude
			local speed = horizontal / dt
			local maxSpeed = math.max(humanoid.WalkSpeed, 16) * AntiCheatService.SpeedTolerance
				+ AntiCheatService.SpeedFlatBonus

			local airborne = state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping

			if (position - previous).Magnitude > AntiCheatService.TeleportStuds and not airborne then
				AntiCheatService.ReportViolation(player, "Teleport", AntiCheatService.Severity.Teleport)
			elseif speed > maxSpeed then
				-- scale severity by how far over the limit they were
				local over = speed / maxSpeed
				AntiCheatService.ReportViolation(
					player,
					string.format("Speed (%.0f/%.0f studs/s)", speed, maxSpeed),
					AntiCheatService.Severity.Speed * math.clamp(over, 1, 4)
				)
			elseif AntiCheatService.FlightCheckEnabled and not airborne then
				local verticalSpeed = (position.Y - previous.Y) / dt
				if verticalSpeed > AntiCheatService.FlightVerticalSpeed then
					AntiCheatService.ReportViolation(player, "Flight", AntiCheatService.Severity.Flight)
				end
			end
		end
	end

	record.lastPos = position
	record.lastSampleTime = t
end

local function checkHeartbeat(player: Player, record: Record, t: number)
	if t - record.joinTime < AntiCheatService.HeartbeatGrace then
		return
	end
	if t - record.lastHeartbeat > AntiCheatService.HeartbeatTimeout then
		-- bump so we flag once per timeout window, not every tick
		record.lastHeartbeat = t
		AntiCheatService.ReportViolation(player, "HeartbeatMissing", AntiCheatService.Severity.HeartbeatMissing)
	end
end

--------------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	records[player] = {
		lastPos = nil,
		lastSampleTime = now(),
		lastHeartbeat = now(),
		joinTime = now(),
		violations = 0,
	}
end

function AntiCheatService:Start(_fw: any)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		records[player] = nil
	end)

	-- client liveness ping
	Relay.AntiCheat.Heartbeat.listen(function(_payload: any, player: Player)
		local record = records[player]
		if record then
			record.lastHeartbeat = now()
		end
	end)

	-- client tripwire reports (untrusted, low severity)
	Relay.AntiCheat.Report.listen(function(payload: any, player: Player)
		local reason = if type(payload) == "table" then tostring(payload.reason) else "Unknown"
		AntiCheatService.ReportViolation(player, "ClientReport:" .. reason, AntiCheatService.Severity.ClientReport)
	end)

	-- single sampling loop on the shared scheduler
	Scheduler.Every(AntiCheatService.SampleRate, function(dt)
		if not AntiCheatService.Enabled then
			return
		end
		local t = now()
		local decay = AntiCheatService.ViolationDecayPerSecond * dt
		for player, record in records do
			if record.violations > 0 then
				record.violations = math.max(0, record.violations - decay)
			end
			checkMovement(player, record)
			checkHeartbeat(player, record, t)
		end
	end)

	log:Info(
		string.format(
			"started (sample %dHz, %s)",
			AntiCheatService.SampleRate,
			if AntiCheatService.AutoKick then "auto-kick on" else "log+flag only"
		)
	)
end

return AntiCheatService
