--!strict
--[[
	LoadController: asset preloading + a single "game is ready" signal.

	Tag Instances (sounds, images, meshes, or containers of them) with "Preload"
	in Studio and they're loaded through ContentProvider before GameLoaded fires.
	Player data readiness is included, so "loaded" means playable, not just rendered.

		local Load = ClientRuntime:GetController("LoadController")
		Load:OnLoaded(function() hud.Visible = true end)  -- fires immediately if already loaded
		Load.Progress:Connect(function(done, total) bar.Size = UDim2.fromScale(done / total, 1) end)
		Load:IsLoaded()

	For a loading screen: build it in ReplicatedFirst (so it shows instantly) and
	tear it down from an OnLoaded callback.
]]

local ContentProvider = game:GetService("ContentProvider")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Relay = Core:GetShared("Network")
local Replica = Core:Get("Replica")

local LoadController = {}

LoadController.GameLoaded = Relay.Signal.new()
LoadController.Progress = Relay.Signal.new()

local PRELOAD_TAG = "Preload"
local PRELOAD_TIMEOUT = 20 -- don't hold the game hostage on a slow asset

local _loaded = false

function LoadController:IsLoaded(): boolean
	return _loaded
end

--- Runs `callback` once loading completes (immediately if already done).
function LoadController:OnLoaded(callback: () -> ())
	if _loaded then
		task.spawn(callback)
	else
		LoadController.GameLoaded:Once(callback)
	end
end

local function collectPreloadTargets(): { Instance }
	local targets: { Instance } = {}
	for _, tagged in CollectionService:GetTagged(PRELOAD_TAG) do
		table.insert(targets, tagged)
		for _, descendant in tagged:GetDescendants() do
			table.insert(targets, descendant)
		end
	end
	return targets
end

function LoadController:Start(_fw: any)
	task.spawn(function()
		local targets = collectPreloadTargets()
		local total = math.max(1, #targets)
		local done = 0

		local preloadFinished = false
		task.spawn(function()
			-- per-item callback gives us progress without batching everything
			ContentProvider:PreloadAsync(targets, function()
				done += 1
				LoadController.Progress:Fire(done, total)
			end)
			preloadFinished = true
		end)

		local deadline = os.clock() + PRELOAD_TIMEOUT
		while not preloadFinished and os.clock() < deadline do
			task.wait(0.1)
		end
		if not preloadFinished then
			warn("LoadController: preload timed out; continuing with partial assets")
		end

		-- playable = assets in + player data replicated
		local dataReady = false
		Replica:WaitForData("Player"):andThen(function()
			dataReady = true
		end)
		local dataDeadline = os.clock() + PRELOAD_TIMEOUT
		while not dataReady and os.clock() < dataDeadline do
			task.wait(0.1)
		end

		_loaded = true
		LoadController.GameLoaded:Fire()
	end)
end

return LoadController
