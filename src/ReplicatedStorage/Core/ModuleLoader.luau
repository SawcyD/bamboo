--!strict
-- Shared lazy module loader behind Core, ClientRuntime, and ServerRuntime.
-- One loader per folder: caches results, supports the folder-with-init pattern,
-- and lets concurrent loads of the same module wait instead of erroring.

local ModuleLoader = {}
ModuleLoader.__index = ModuleLoader

export type ModuleLoaderType = typeof(setmetatable(
	{} :: {
		_folder: Folder,
		_cache: { [string]: any },
		_loading: { [string]: boolean },
	},
	ModuleLoader
))

function ModuleLoader.new(folder: Folder): ModuleLoaderType
	return setmetatable({
		_folder = folder,
		_cache = {},
		_loading = {},
	}, ModuleLoader)
end

-- Resolves `name` to a requireable ModuleScript: either the child itself, or
-- (for folders / nested trees) an `init` child or first ModuleScript inside it.
local function resolveModule(folder: Folder, name: string): ModuleScript
	local child = folder:FindFirstChild(name)
	if not child then
		error(folder.Name .. " does not contain: " .. name)
	end
	if child:IsA("ModuleScript") then
		return child
	end
	local init = child:FindFirstChild("init") or child:FindFirstChildOfClass("ModuleScript")
	if not init or not init:IsA("ModuleScript") then
		error(folder.Name .. "/" .. name .. " has no loadable ModuleScript")
	end
	return init
end

function ModuleLoader.Get(self: ModuleLoaderType, name: string): any
	local cache = self._cache
	if cache[name] ~= nil then
		return cache[name]
	end

	-- Another thread may already be loading this module (e.g. two services requiring
	-- the same package during parallel :Start); wait for it instead of re-requiring.
	local loading = self._loading
	if loading[name] then
		while loading[name] do
			task.wait()
		end
		assert(cache[name] ~= nil, self._folder.Name .. " concurrent load failed or missing: " .. name)
		return cache[name]
	end
	loading[name] = true

	local ok, result = pcall(function()
		return require(resolveModule(self._folder, name)) :: any
	end)

	if not ok then
		loading[name] = nil
		error(result)
	end

	-- Populate cache before clearing the loading flag so waiters never see a gap.
	cache[name] = result
	loading[name] = nil
	return result
end

--- Pre-seeds the cache (used by StartAll so :Get returns already-started modules).
function ModuleLoader.Seed(self: ModuleLoaderType, name: string, value: any)
	self._cache[name] = value
end

--- Recursively collects ModuleScripts under `root` (descends into Folders only,
--- so a module's children — init pattern, mixins — stay owned by that module).
function ModuleLoader.Collect(root: Instance): { ModuleScript }
	local result: { ModuleScript } = {}
	local function walk(parent: Instance)
		for _, child in parent:GetChildren() do
			if child:IsA("ModuleScript") then
				table.insert(result, child)
			elseif child:IsA("Folder") then
				walk(child)
			end
		end
	end
	walk(root)
	return result
end

--- Requires every module under the loader's folder (skipping "_" templates), seeds the
--- cache, and calls module:Start(runtime) when present. Each module starts on its own
--- thread; failures are warned, not fatal.
function ModuleLoader.StartAll(self: ModuleLoaderType, label: string, runtime: any)
	for _, module in ModuleLoader.Collect(self._folder) do
		if module.Name:sub(1, 1) == "_" then
			continue
		end
		task.spawn(function()
			local ok, result = pcall(require, module)
			if not ok then
				warn(label .. ": failed to load", module:GetFullName(), result)
				return
			end
			self._cache[module.Name] = result
			if type(result) == "table" and type(result.Start) == "function" then
				local startOk, startErr = pcall(result.Start, result, runtime)
				if startOk then
					print(label .. ": started", module.Name)
				else
					warn(label .. ": error starting", module.Name, startErr)
				end
			end
		end)
	end
end

return ModuleLoader
