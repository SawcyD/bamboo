--!strict
-- Settings for the PerformanceDebug profiler (ClientRuntime/Controllers/PerformanceDebug).

return {
	-- Key that toggles the profiler UI.
	ToggleKey = Enum.KeyCode.L,

	-- The profiler is always available in Studio. In live servers it only
	-- initializes for these UserIds (leave empty to keep it Studio-only).
	DeveloperIds = {} :: { number },
}
