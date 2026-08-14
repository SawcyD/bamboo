--!strict
--[[
	Log: leveled, tagged logging for services/controllers.

		local log = Log.new("DataService")
		log:Debug("loaded profile for", player.Name)  -- hidden outside Studio by default
		log:Info("service started")
		log:Warn("save retry", attempt)
		log:Error("profile failed to load:", err)     -- error() without halting: prints stack

	Levels: Debug < Info < Warn < Error. Default minimum level is Debug in Studio,
	Info in live servers. Override globally or per tag:

		Log.SetLevel("Debug")               -- everything, everywhere
		Log.SetLevel("Warn", "OptimizedZone") -- quiet one noisy system

	Sinks: every record (even filtered-visible ones below the print threshold are
	skipped) is passed to registered sinks — hook analytics or a webhook here:

		Log.AddSink(function(record)
			-- record: { level, tag, message, timestamp }
		end)
]]

local RunService = game:GetService("RunService")

export type Level = "Debug" | "Info" | "Warn" | "Error"

export type LogRecord = {
	level: Level,
	tag: string,
	message: string,
	timestamp: number,
}

local LEVEL_ORDER: { [Level]: number } = {
	Debug = 1,
	Info = 2,
	Warn = 3,
	Error = 4,
}

local Log = {}

local _globalLevel: Level = if RunService:IsStudio() then "Debug" else "Info"
local _tagLevels: { [string]: Level } = {}
local _sinks: { (LogRecord) -> () } = {}

--- Minimum level to print. Pass a tag to override for that tag only.
function Log.SetLevel(level: Level, tag: string?)
	if tag then
		_tagLevels[tag] = level
	else
		_globalLevel = level
	end
end

--- Receives every record at or above the effective level. Keep sinks fast/non-yielding.
function Log.AddSink(sink: (LogRecord) -> ())
	table.insert(_sinks, sink)
end

local function joinArgs(...: any): string
	local parts = table.create(select("#", ...))
	for i = 1, select("#", ...) do
		parts[i] = tostring(select(i, ...))
	end
	return table.concat(parts, " ")
end

local function emit(tag: string, level: Level, ...: any)
	local minLevel = _tagLevels[tag] or _globalLevel
	if LEVEL_ORDER[level] < LEVEL_ORDER[minLevel] then
		return
	end

	local message = joinArgs(...)
	local line = `[{tag}] {message}`

	if level == "Warn" or level == "Error" then
		warn(line)
	else
		print(line)
	end

	if #_sinks > 0 then
		local record: LogRecord = {
			level = level,
			tag = tag,
			message = message,
			timestamp = os.time(),
		}
		for _, sink in _sinks do
			task.spawn(sink, record)
		end
	end
end

local Logger = {}
Logger.__index = Logger

export type LoggerType = typeof(setmetatable({} :: { _tag: string }, Logger))

function Logger.Debug(self: LoggerType, ...: any)
	emit(self._tag, "Debug", ...)
end

function Logger.Info(self: LoggerType, ...: any)
	emit(self._tag, "Info", ...)
end

function Logger.Warn(self: LoggerType, ...: any)
	emit(self._tag, "Warn", ...)
end

function Logger.Error(self: LoggerType, ...: any)
	emit(self._tag, "Error", ...)
end

--- Asserts with a tagged message; returns the value so it can wrap expressions.
function Logger.Assert(self: LoggerType, condition: any, ...: any): any
	if not condition then
		local message = joinArgs(...)
		emit(self._tag, "Error", message)
		error(`[{self._tag}] {message}`, 2)
	end
	return condition
end

local _loggers: { [string]: LoggerType } = {}

function Log.new(tag: string): LoggerType
	local existing = _loggers[tag]
	if existing then
		return existing
	end
	local logger = setmetatable({ _tag = tag }, Logger)
	_loggers[tag] = logger
	return logger
end

return Log
