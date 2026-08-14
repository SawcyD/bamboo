--!strict
local RunService = game:GetService("RunService")

assert(not RunService:IsServer(), "UI must only be required on the client")

type ModuleCache = { [string]: any }
type LoadGuard = { [string]: boolean }

local UI = {}

local _buttonsFolder = script:WaitForChild("Buttons") :: Folder
local _framesFolder = script:WaitForChild("Frames") :: Folder
local _modulesFolder = script:WaitForChild("Modules") :: Folder

local _buttonModules: ModuleCache = {}
local _frameModules: ModuleCache = {}
local _sharedModules: ModuleCache = {}
local _loadingButton: LoadGuard = {}
local _loadingFrame: LoadGuard = {}
local _loadingModule: LoadGuard = {}

local _started = false

local function lazyRequire(folder: Folder, name: string, cache: ModuleCache, loading: LoadGuard): any
	local hit = cache[name]
	if hit ~= nil then
		return hit
	end

	assert(not loading[name], "Circular dependency in UI: " .. name)
	loading[name] = true

	local mod = folder:FindFirstChild(name)
	assert(mod ~= nil and mod:IsA("ModuleScript"), string.format("%s has no ModuleScript %q", folder.Name, name))

	local exports = require(mod :: ModuleScript)
	cache[name] = exports
	loading[name] = nil

	return exports
end

local function listModuleNames(folder: Folder): { string }
	local names = {}
	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") and child.Name:sub(1, 1) ~= "_" then
			table.insert(names, child.Name)
		end
	end
	table.sort(names)
	return names
end

local function startFolderModules(kind: string, folder: Folder, cache: ModuleCache, loading: LoadGuard)
	for _, name in listModuleNames(folder) do
		local exports = lazyRequire(folder, name, cache, loading)
		if type(exports) == "table" and type((exports :: any).Start) == "function" then
			local ok, err = pcall(function()
				(exports :: any):Start(UI)
			end)
			if not ok then
				warn("[UI] Start failed:", kind, name, err)
			end
		end
	end
end

--- Client-only. Requires each Buttons/Frames module and calls :Start(UI) when defined. Call once from Client.client after ClientRuntime:Start (or alongside it).
function UI:Start()
	assert(not _started, "UI:Start() called more than once")
	_started = true

	startFolderModules("Button", _buttonsFolder, _buttonModules, _loadingButton)
	startFolderModules("Frame", _framesFolder, _frameModules, _loadingFrame)
end

function UI:GetButton(name: string): any
	return lazyRequire(_buttonsFolder, name, _buttonModules, _loadingButton)
end

function UI:GetFrame(name: string): any
	return lazyRequire(_framesFolder, name, _frameModules, _loadingFrame)
end

--- Shared UI helpers from UI/Modules (Ripple, MessageToast...). Not auto-started.
function UI:GetModule(name: string): any
	return lazyRequire(_modulesFolder, name, _sharedModules, _loadingModule)
end

return UI
