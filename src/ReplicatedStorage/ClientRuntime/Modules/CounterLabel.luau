--!strict
--[[
	Fast expo pop, abbreviated (good for big reward moments)
	local bigReward = CounterLabel.new(label, {
		duration = 0.5,
		easing = "EaseOutExpo",
		format = "abbreviated",
		suffix = " coins",
	})

	Slow smooth count, comma formatted (good for passive income ticking)
	local passiveIncome = CounterLabel.new(label, {
		duration = 1.2,
		easing = "EaseOutQuad",
		format = "comma",
	})

	Instant snap on data load, then animate on changes
	local statLabel = CounterLabel.new(label, { format = "int" })
	statLabel:SetImmediate(playerData.Coins)
	-- later, on update:
	statLabel:SetTarget(playerData.Coins)

	Time meters: use format "time", optional odometerRoll for stepped seconds
	local timerLabel = CounterLabel.new(label, {
		format = "time",
		timeStyle = "MM:SS",
		odometerRoll = true,
		duration = 0.4,
	})
	timerLabel:SetImmediate(90)
	timerLabel:SetTarget(0) -- rolls second-by-second toward zero

	Static helper for any TextLabel (no CounterLabel instance):
	label.Text = CounterLabel.FormatSeconds(125, "MM:SS") -- "2:05"
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local FormatUtil = Core:GetUtil("FormatUtil")

export type CounterFormat = "int" | "comma" | "abbreviated" | "time"

export type CounterEasing = "EaseOutExpo" | "EaseOutQuart" | "EaseOutQuad"

--- Used when `format == "time"` (e.g. timers / countdown meters).
export type TimeFormatStyle = "MM:SS" | "HH:MM:SS"

export type CounterConfig = {
	duration: number?,
	easing: CounterEasing?,
	format: CounterFormat?,
	--- When `format == "time"`, how to render seconds. Default `"MM:SS"`.
	timeStyle: TimeFormatStyle?,
	--- If true, `SetTarget` advances in whole-unit steps (odometer-style) spread across `duration`
	--- instead of smooth easing. For `format == "time"`, one step = one second. Good for timers.
	odometerRoll: boolean?,
	prefix: string?,
	suffix: string?,
	onComplete: (() -> ())?,
}

local DEFAULT_DURATION = 0.6
local DEFAULT_EASING: CounterEasing = "EaseOutExpo"
local DEFAULT_FORMAT: CounterFormat = "comma"

local function easeOutExpo(t: number): number
	return 1 - 2 ^ (-10 * t)
end

local function easeOutQuart(t: number): number
	return 1 - (1 - t) ^ 4
end

local function easeOutQuad(t: number): number
	return 1 - (1 - t) ^ 2
end

local EASINGS: { [CounterEasing]: (number) -> number } = {
	EaseOutExpo = easeOutExpo,
	EaseOutQuart = easeOutQuart,
	EaseOutQuad = easeOutQuad,
}

local function roundNonNegative(n: number): number
	return math.max(0, math.floor(n + 0.5))
end

local CounterLabel = {}
CounterLabel.__index = CounterLabel

--- Formats a duration in **seconds** for HUD timers (shared by all time meters).
function CounterLabel.FormatSeconds(seconds: number, style: TimeFormatStyle): string
	local s = math.max(0, math.floor(seconds + 0.5))
	if style == "HH:MM:SS" then
		local h = math.floor(s / 3600)
		local m = math.floor((s % 3600) / 60)
		local r = s % 60
		return string.format("%02d:%02d:%02d", h, m, r)
	end
	local m = math.floor(s / 60)
	local r = s % 60
	return string.format("%d:%02d", m, r)
end

export type CounterLabelInstance = {
	Destroy: (self: CounterLabelInstance) -> (),
	SetImmediate: (self: CounterLabelInstance, value: number) -> (),
	SetTarget: (self: CounterLabelInstance, newTarget: number) -> (),
}

type CounterLabelSelf = CounterLabelInstance & {
	_label: TextLabel,
	_config: CounterConfig,
	_value: number,
	_renderConn: RBXScriptConnection?,
	_destroyed: boolean,
	_animStartClock: number?,
	_animFrom: number?,
	_animTo: number?,
	_animDuration: number?,
}

function CounterLabel.new(label: TextLabel, config: any?): CounterLabelInstance
	assert(RunService:IsClient(), "CounterLabel is client-only")
	assert(label:IsA("TextLabel"), "CounterLabel.new: expected TextLabel")

	local cfg = config :: CounterConfig?

	local easing: CounterEasing = DEFAULT_EASING
	if cfg and cfg.easing then
		easing = cfg.easing :: CounterEasing
	end
	local fmt: CounterFormat = DEFAULT_FORMAT
	if cfg and cfg.format then
		fmt = cfg.format :: CounterFormat
	end

	local timeStyle: TimeFormatStyle = "MM:SS"
	if cfg and cfg.timeStyle then
		timeStyle = cfg.timeStyle :: TimeFormatStyle
	end

	local odometerRoll = if cfg and cfg.odometerRoll ~= nil then cfg.odometerRoll else false

	local merged: CounterConfig = {
		duration = (cfg and cfg.duration) or DEFAULT_DURATION,
		easing = easing,
		format = fmt,
		timeStyle = timeStyle,
		odometerRoll = odometerRoll,
		prefix = (cfg and cfg.prefix) or "",
		suffix = (cfg and cfg.suffix) or "",
		onComplete = if cfg then cfg.onComplete else nil,
	}

	local raw = setmetatable({
		_label = label,
		_config = merged,
		_value = 0,
		_renderConn = nil :: RBXScriptConnection?,
		_destroyed = false,
		_animStartClock = nil :: number?,
		_animFrom = nil :: number?,
		_animTo = nil :: number?,
		_animDuration = nil :: number?,
	}, CounterLabel)

	return (raw :: any) :: CounterLabelInstance
end

function CounterLabel._stopAnimation(self: CounterLabelSelf)
	local conn = self._renderConn
	if conn then
		conn:Disconnect()
		self._renderConn = nil
	end
	self._animStartClock = nil
	self._animFrom = nil
	self._animTo = nil
	self._animDuration = nil
end

function CounterLabel._formatDisplay(self: CounterLabelSelf, n: number): string
	local fmt = self._config.format or DEFAULT_FORMAT
	local prefix = self._config.prefix or ""
	local suffix = self._config.suffix or ""

	local body: string
	if fmt == "comma" then
		body = FormatUtil.Number(roundNonNegative(n), { precision = 0 })
	elseif fmt == "abbreviated" then
		body = FormatUtil.Compact(n, { precision = 1 })
	elseif fmt == "time" then
		local style: TimeFormatStyle = (self._config.timeStyle :: TimeFormatStyle?) or "MM:SS"
		body = CounterLabel.FormatSeconds(n, style)
	else
		body = tostring(roundNonNegative(n))
	end

	return prefix .. body .. suffix
end

function CounterLabel._writeText(self: CounterLabelSelf)
	local label = self._label
	if self._destroyed or not label.Parent then
		return
	end
	label.Text = CounterLabel._formatDisplay(self, self._value)
end

function CounterLabel.SetImmediate(self: CounterLabelSelf, value: number)
	if self._destroyed then
		return
	end
	CounterLabel._stopAnimation(self)
	self._value = value
	CounterLabel._writeText(self)
end

function CounterLabel.SetTarget(self: CounterLabelSelf, newTarget: number)
	if self._destroyed then
		return
	end

	CounterLabel._stopAnimation(self)

	local cfg = self._config
	local duration = math.max(1e-4, cfg.duration or DEFAULT_DURATION)

	local from = self._value
	local to = newTarget

	if cfg.odometerRoll then
		CounterLabel._runOdometerRoll(self, from, to, duration)
		return
	end

	local easingName: CounterEasing = (cfg.easing :: CounterEasing?) or DEFAULT_EASING
	local easeFn = EASINGS[easingName] or easeOutExpo

	if from == to then
		CounterLabel._writeText(self)
		local oc = cfg.onComplete
		if oc then
			oc()
		end
		return
	end

	self._animStartClock = os.clock()
	self._animFrom = from
	self._animTo = to
	self._animDuration = duration

	self._renderConn = RunService.RenderStepped:Connect(function()
		if self._destroyed then
			CounterLabel._stopAnimation(self)
			return
		end

		local lbl = self._label
		if not lbl.Parent then
			CounterLabel._stopAnimation(self)
			return
		end

		local startClock = self._animStartClock
		local animFrom = self._animFrom
		local animTo = self._animTo
		local animDur = self._animDuration
		if not startClock or animFrom == nil or animTo == nil or not animDur then
			CounterLabel._stopAnimation(self)
			return
		end

		local elapsed = os.clock() - startClock
		local t = math.clamp(elapsed / animDur, 0, 1)
		local eased = easeFn(t)
		self._value = animFrom + (animTo - animFrom) * eased
		CounterLabel._writeText(self)

		if t >= 1 then
			self._value = animTo
			CounterLabel._writeText(self)
			CounterLabel._stopAnimation(self)
			local oc = self._config.onComplete
			if oc then
				oc()
			end
		end
	end)
end

--- Discrete whole-unit steps (odometer-style) over `duration`. For `format == "time"`, each step is one second.
function CounterLabel._runOdometerRoll(self: CounterLabelSelf, from: number, to: number, duration: number)
	local fromI = math.floor(from + 0.5)
	local toI = math.floor(to + 0.5)
	local delta = toI - fromI
	local steps = math.abs(delta)
	if steps == 0 then
		self._value = to
		CounterLabel._writeText(self)
		local oc = self._config.onComplete
		if oc then
			oc()
		end
		return
	end

	local sign = if delta > 0 then 1 else -1
	local stepDuration = math.max(1e-4, duration / steps)
	local startClock = os.clock()

	self._renderConn = RunService.RenderStepped:Connect(function()
		if self._destroyed then
			CounterLabel._stopAnimation(self)
			return
		end

		local lbl = self._label
		if not lbl.Parent then
			CounterLabel._stopAnimation(self)
			return
		end

		local elapsed = os.clock() - startClock
		local idx = math.floor(elapsed / stepDuration)
		if idx >= steps then
			self._value = to
			CounterLabel._writeText(self)
			CounterLabel._stopAnimation(self)
			local oc = self._config.onComplete
			if oc then
				oc()
			end
		else
			self._value = fromI + sign * idx
			CounterLabel._writeText(self)
		end
	end)
end

function CounterLabel.Destroy(self: CounterLabelSelf)
	if self._destroyed then
		return
	end
	self._destroyed = true
	CounterLabel._stopAnimation(self)
end

return CounterLabel
